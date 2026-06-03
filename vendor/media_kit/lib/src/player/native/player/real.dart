/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import 'dart:ffi';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:media_kit/src/models/subtitle.dart';
import 'package:meta/meta.dart';
import 'package:image/image.dart';
import 'package:synchronized/synchronized.dart';

import 'package:media_kit/ffi/ffi.dart';

import 'package:media_kit/src/player/platform_player.dart';

import 'package:media_kit/src/player/native/core/initializer.dart';
import 'package:media_kit/src/player/native/core/native_library.dart';
import 'package:media_kit/src/player/native/core/initializer_native_event_loop.dart';

import 'package:media_kit/src/player/native/utils/isolates.dart';
import 'package:media_kit/src/player/native/utils/android_helper.dart';

import 'package:media_kit/src/models/track.dart';
import 'package:media_kit/src/models/playable.dart';
import 'package:media_kit/src/models/player_log.dart';
import 'package:media_kit/src/models/audio_device.dart';
import 'package:media_kit/src/models/audio_params.dart';
import 'package:media_kit/src/models/video_params.dart';
import 'package:media_kit/src/models/playlist_mode.dart';

import 'package:media_kit/generated/libmpv/bindings.dart' as generated;

/// Initializes the native backend for package:media_kit.
void nativeEnsureInitialized({String? libmpv}) {
  if (Platform.isAndroid) AndroidHelper.ensureInitialized(libmpv: libmpv);
  NativeLibrary.ensureInitialized(libmpv: libmpv);
  InitializerNativeEventLoop.ensureInitialized();
}

/// {@template native_player}
///
/// NativePlayer
/// ------------
///
/// Native implementation of [PlatformPlayer].
///
/// {@endtemplate}
class NativePlayer extends PlatformPlayer {
  /// {@macro native_player}
  NativePlayer._({required super.configuration}) {
    _future = _create();
  }

  static Future<NativePlayer> create({
    PlayerConfiguration configuration = const PlayerConfiguration(),
  }) async {
    final player = NativePlayer._(configuration: configuration);
    await player.waitForPlayerInitialization;
    return player;
  }

  @pragma("vm:prefer-inline")
  void throwIfDisposed() {
    if (disposed) {
      throw AssertionError('[Player] has been disposed');
    }
  }

  /// Disposes the [Player] instance & releases the resources.
  @override
  Future<void> dispose() async {
    throwIfDisposed();

    _isDisposing = true;
    try {
      await stop(synchronized: false).timeout(const Duration(seconds: 2));
    } catch (e, s) {
      Zone.current.handleUncaughtError(e, s);
    }

    disposed = true;

    await super.dispose();

    Initializer.dispose(ctx);

    Timer(const Duration(seconds: 5), () => mpv.mpv_terminate_destroy(ctx));
  }

  /// Opens a [Media] or [Playlist] into the [Player].
  /// Passing [play] as `true` starts the playback immediately.
  ///
  /// ```dart
  /// await player.open(Media('asset:///assets/videos/sample.mp4'));
  /// await player.open(Media('file:///C:/Users/Hitesh/Music/Sample.mp3'));
  /// await player.open(
  ///   Playlist(
  ///     [
  ///       Media('file:///C:/Users/Hitesh/Music/Sample.mp3'),
  ///       Media('file:///C:/Users/Hitesh/Video/Sample.mkv'),
  ///       Media('https://www.example.com/sample.mp4'),
  ///       Media('rtsp://www.example.com/live'),
  ///     ],
  ///   ),
  /// );
  /// ```
  ///
  @override
  Future<void> open(
    Playable playable, {
    bool play = true,
    bool synchronized = true,
  }) {
    Future<void> function() async {
      throwIfDisposed();

      final int index;
      current.clear();
      switch (playable) {
        case Media():
          index = 0;
          current.add(playable);
        case Playlist():
          index = playable.index;
          current.addAll(playable.medias);
      }

      // NOTE: Handled as part of [stop] logic.
      // final commands = [
      //   // Clear existing playlist & change currently playing index to none.
      //   // This causes playback to stop & player to enter the idle state.
      //   'stop',
      //   'playlist-clear',
      //   'playlist-play-index none',
      // ];
      // for (final command in commands) {
      //   final args = command.toNativeUtf8();
      //   mpv.mpv_command_string(
      //     ctx,
      //     args,
      //   );
      //   calloc.free(args);
      // }

      // Restore original state & reset public [PlayerState] & [PlayerStream] values e.g. width=null, height=null, subtitle=['', ''] etc.
      await stop(open: true, synchronized: false);

      // Enter paused state.
      await _setPropertyFlag('pause', true);

      // NOTE: Handled as part of [stop] logic.
      // isShuffleEnabled = false;
      // isPlayingStateChangeAllowed = false;

      for (int i = 0; i < current.length; i++) {
        _add(current[i]);
      }

      // If [play] is `true`, then exit paused state.
      if (play) {
        isPlayingStateChangeAllowed = true;
        await _setPropertyFlag('pause', false);
        state.playing = true;
        if (!playingController.isClosed) {
          playingController.add(true);
        }
      }

      // Jump to the specified [index] (in both cases either [play] is `true` or `false`).
      await _setPropertyInt64('playlist-pos', index);
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Stops the [Player].
  /// Unloads the current [Media] or [Playlist] from the [Player]. This method is similar to [dispose] but does not release the resources & [Player] is still usable.
  @override
  Future<void> stop({bool open = false, bool synchronized = true}) {
    Future<void> function() async {
      throwIfDisposed();

      isShuffleEnabled = false;
      isPlayingStateChangeAllowed = false;
      isBufferingStateChangeAllowed = false;

      const commands = [
        ['stop'],
        ['playlist-clear'],
        ['playlist-play-index', 'none'],
      ];
      for (final c in commands) {
        await command(c);
      }

      // Reset the remaining attributes.
      state
        ..playlist = const Playlist([])
        ..playing = false
        ..completed = false
        ..position = Duration.zero
        ..duration = Duration.zero
        ..buffering = false
        ..buffer = Duration.zero
        ..audioParams = const AudioParams()
        ..videoParams = const VideoParams()
        ..track = const Track()
        ..tracks = const Tracks()
        ..width = 0
        ..height = 0
        ..subtitle = const Subtitle.raw();

      if (!_isDisposing) {
        if (!open) {
          // Do not emit PlayerStream.playlist if invoked from [open].
          if (!playlistController.isClosed) {
            playlistController.add(const Playlist([]));
          }
        }
        if (!playingController.isClosed) {
          playingController.add(false);
        }
        if (!completedController.isClosed) {
          completedController.add(false);
        }
        if (!positionController.isClosed) {
          positionController.add(Duration.zero);
        }
        if (!durationController.isClosed) {
          durationController.add(Duration.zero);
        }
        // if (!volumeController.isClosed) {
        //   volumeController.add(0.0);
        // }
        // if (!rateController.isClosed) {
        //   rateController.add(0.0);
        // }
        // if (!pitchController.isClosed) {
        //   pitchController.add(0.0);
        // }
        if (!bufferingController.isClosed) {
          bufferingController.add(false);
        }
        if (!bufferController.isClosed) {
          bufferController.add(Duration.zero);
        }
        // if (!playlistModeController.isClosed) {
        //   playlistModeController.add(PlaylistMode.none);
        // }
        if (!audioParamsController.isClosed) {
          audioParamsController.add(const AudioParams());
        }
        if (!videoParamsController.isClosed) {
          videoParamsController.add(const VideoParams());
        }
        // if (!audioBitrateController.isClosed) {
        //   audioBitrateController.add(null);
        // }
        // if (!audioDeviceController.isClosed) {
        //   audioDeviceController.add(AudioDevice.auto());
        // }
        // if (!audioDevicesController.isClosed) {
        //   audioDevicesController.add([AudioDevice.auto()]);
        // }
        if (!trackController.isClosed) {
          trackController.add(const Track());
        }
        if (!tracksController.isClosed) {
          tracksController.add(const Tracks());
        }
        if (!sizeController.isClosed) {
          sizeController.add(const (0, 0));
        }
        if (!subtitleController.isClosed) {
          subtitleController.add(const Subtitle.raw());
        }
      }
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Starts playing the [Player].
  @override
  Future<void> play({bool synchronized = true}) {
    Future<void> function() async {
      throwIfDisposed();

      state.playing = true;
      if (!playingController.isClosed) {
        playingController.add(true);
      }

      isPlayingStateChangeAllowed = true;

      // This condition is specifically for the case when the internal playlist is ended (with [PlaylistLoopMode.none]), and we want to play the playlist again if play/pause is pressed.
      if (state.completed) {
        await seek(Duration.zero, synchronized: false);
        await _setPropertyInt64('playlist-pos', 0);
      }
      await _setPropertyFlag('pause', false);
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Pauses the [Player].
  @override
  Future<void> pause({bool synchronized = true}) {
    Future<void> function() async {
      throwIfDisposed();

      state.playing = false;
      if (!playingController.isClosed) {
        playingController.add(false);
      }

      isPlayingStateChangeAllowed = state.playing;
      isBufferingStateChangeAllowed = false;
      await _setPropertyFlag('pause', true);
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Cycles between [play] & [pause] states of the [Player].
  @override
  Future<void> playOrPause({bool notify = true, bool synchronized = true}) {
    Future<void> function() async {
      throwIfDisposed();

      if (notify) {
        // Do not change the [state.playing] value if [playOrPause] was called from [play] or [pause]; where the [state.playing] value is already changed.
        state.playing = !state.playing;
        if (!playingController.isClosed) {
          playingController.add(state.playing);
        }
      }

      isPlayingStateChangeAllowed = state.playing;
      isBufferingStateChangeAllowed = false;

      // This condition is specifically for the case when the internal playlist is ended (with [PlaylistLoopMode.none]), and we want to play the playlist again if play/pause is pressed.
      if (state.completed) {
        await seek(Duration.zero, synchronized: false);
        await _setPropertyInt64('playlist-pos', 0);
      }
      await command(const ['cycle', 'pause']);
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  Future<void> _add(Media media) {
    if (media.extras case final extras?) {
      return command([
        'loadfile',
        media.uri,
        'append',
        if (apiVersion >= 0x20003) '-1',
        extras.entries.map((e) => '${e.key}=${e.value}').join(','),
      ]);
    } else {
      return command(['loadfile', media.uri, 'append']);
    }
  }

  /// Appends a [Media] to the [Player]'s playlist.
  @override
  Future<void> add(Media media, {bool synchronized = true}) {
    Future<void> function() {
      throwIfDisposed();

      // External List<Media>:
      // ---------------------------------------------
      current.add(media);
      // ---------------------------------------------

      return _add(media);
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Removes the [Media] at specified index from the [Player]'s playlist.
  @override
  Future<void> remove(int index, {bool synchronized = true}) {
    Future<void> function() {
      throwIfDisposed();

      // External List<Media>:
      // ---------------------------------------------
      current.removeAt(index);
      // ---------------------------------------------

      // If we remove the last item in the playlist while playlist mode is none or single, then playback will stop.
      // In this situation, the playlist doesn't seem to be updated, so we manually update it.
      if (state.playlist.index == index &&
          state.playlist.medias.length - 1 == index &&
          switch (state.playlistMode) {
            PlaylistMode.none || PlaylistMode.single => true,
            PlaylistMode.loop => false,
          }) {
        // Allow playOrPause /w state.completed code-path to play the playlist again.
        state
          ..completed = true
          ..playlist = state.playlist.copyWith(
            medias: state.playlist.medias.sublist(
              0,
              state.playlist.medias.length - 1,
            ),
            index: state.playlist.medias.length - 2 < 0
                ? 0
                : state.playlist.medias.length - 2,
          );
        if (!completedController.isClosed) {
          completedController.add(true);
        }
        if (!playlistController.isClosed) {
          playlistController.add(state.playlist);
        }
      }

      return command(['playlist-remove', index.toString()]);
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Jumps to next [Media] in the [Player]'s playlist.
  @override
  Future<void> next({bool synchronized = true}) {
    Future<void> function() async {
      throwIfDisposed();

      // Do nothing if currently present at the first or last index & playlist mode is [PlaylistMode.none] or [PlaylistMode.single].
      if (switch (state.playlistMode) {
            PlaylistMode.none || PlaylistMode.single => true,
            PlaylistMode.loop => false,
          } &&
          state.playlist.index == state.playlist.medias.length - 1) {
        return;
      }

      await play(synchronized: false);
      await command(const ['playlist-next']);
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Jumps to previous [Media] in the [Player]'s playlist.
  @override
  Future<void> previous({bool synchronized = true}) {
    Future<void> function() async {
      throwIfDisposed();

      // Do nothing if currently present at the first or last index & playlist mode is [PlaylistMode.none] or [PlaylistMode.single].
      if (switch (state.playlistMode) {
            PlaylistMode.none || PlaylistMode.single => true,
            PlaylistMode.loop => false,
          } &&
          state.playlist.index == 0) {
        return;
      }

      await play(synchronized: false);
      await command(const ['playlist-prev']);
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Jumps to specified [Media]'s index in the [Player]'s playlist.
  @override
  Future<void> jump(int index, {bool synchronized = true}) {
    Future<void> function() async {
      throwIfDisposed();

      await play(synchronized: false);
      await _setPropertyInt64('playlist-pos', index);
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Moves the playlist [Media] at [from], so that it takes the place of the [Media] [to].
  @override
  Future<void> move(int from, int to, {bool synchronized = true}) {
    Future<void> function() async {
      throwIfDisposed();

      // External List<Media>:
      // ---------------------------------------------
      current.insert(to > from ? to - 1 : to, current.removeAt(from));
      // ---------------------------------------------

      await command(['playlist-move', from.toString(), to.toString()]);
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Seeks the currently playing [Media] in the [Player] by specified [Duration].
  @override
  Future<void> seek(Duration duration, {bool synchronized = true}) {
    Future<void> function() async {
      throwIfDisposed();

      await command([
        'seek',
        (duration.inMilliseconds / 1000).toStringAsFixed(3),
        'absolute',
      ]);

      // It is self explanatory that PlayerState.completed & PlayerStream.completed must enter the false state if seek is called. Typically after EOF.
      // https://github.com/media-kit/media-kit/issues/221
      state.completed = false;
      if (!completedController.isClosed) {
        completedController.add(false);
      }
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Sets playlist mode.
  @override
  Future<void> setPlaylistMode(
    PlaylistMode playlistMode, {
    bool synchronized = true,
  }) {
    Future<void> function() async {
      throwIfDisposed();

      switch (playlistMode) {
        case PlaylistMode.none:
          await _setPropertyString('loop-file', 'no');
          await _setPropertyString('loop-playlist', 'no');
        case PlaylistMode.single:
          await _setPropertyString('loop-file', 'yes');
          await _setPropertyString('loop-playlist', 'no');
        case PlaylistMode.loop:
          await _setPropertyString('loop-file', 'no');
          await _setPropertyString('loop-playlist', 'yes');
      }

      state.playlistMode = playlistMode;
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Sets the playback volume of the [Player]. Defaults to `100.0`.
  @override
  Future<void> setVolume(double volume, {bool synchronized = true}) {
    Future<void> function() {
      throwIfDisposed();

      return _setPropertyDouble('volume', volume);
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Sets the playback rate of the [Player]. Defaults to `1.0`.
  @override
  Future<void> setRate(double rate, {bool synchronized = true}) {
    Future<void> function() async {
      throwIfDisposed();

      if (rate <= 0.0) {
        throw ArgumentError.value(rate, 'rate', 'Must be greater than 0.0');
      }

      if (configuration.pitch) {
        // Pitch shift control is enabled.

        state.rate = rate;
        // Apparently, using scaletempo:scale actually controls the playback rate as intended after setting audio-pitch-correction as FALSE.
        // speed on the other hand, changes the pitch when audio-pitch-correction is set to FALSE.
        // Since, it also alters the actual [speed], the scaletempo:scale is divided by the same value of [pitch] to compensate the speed change.
        await _setPropertyFlag('audio-pitch-correction', false);
        // Divide by [state.pitch] to compensate the speed change caused by pitch shift.
        await _setPropertyString(
          'af',
          'scaletempo:scale=${(state.rate / state.pitch).toStringAsFixed(8)}',
        );
      } else {
        // Pitch shift control is disabled.

        state.rate = rate;
        await _setPropertyDouble('speed', rate);
      }
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Sets the relative pitch of the [Player]. Defaults to `1.0`.
  @override
  Future<void> setPitch(double pitch, {bool synchronized = true}) {
    Future<void> function() async {
      throwIfDisposed();

      if (configuration.pitch) {
        if (pitch <= 0.0) {
          throw ArgumentError.value(pitch, 'pitch', 'Must be greater than 0.0');
        }

        // Pitch shift control is enabled.

        state.pitch = pitch;
        // Apparently, using scaletempo:scale actually controls the playback rate as intended after setting audio-pitch-correction as FALSE.
        // speed on the other hand, changes the pitch when audio-pitch-correction is set to FALSE.
        // Since, it also alters the actual [speed], the scaletempo:scale is divided by the same value of [pitch] to compensate the speed change.
        await _setPropertyFlag('audio-pitch-correction', false);
        await _setPropertyDouble('speed', pitch);
        // Divide by [state.pitch] to compensate the speed change caused by pitch shift.
        await _setPropertyString(
          'af',
          'scaletempo:scale=${(state.rate / state.pitch).toStringAsFixed(8)}',
        );
      } else {
        // Pitch shift control is disabled.
        throw ArgumentError('[PlayerConfiguration.pitch] is false');
      }
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Enables or disables shuffle for [Player]. Default is `false`.
  @override
  Future<void> setShuffle(bool shuffle, {bool synchronized = true}) {
    Future<void> function() {
      throwIfDisposed();

      if (shuffle != isShuffleEnabled) {
        isShuffleEnabled = shuffle;
        return command([shuffle ? 'playlist-shuffle' : 'playlist-unshuffle']);
      }
      return Future.value();
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Sets the current [AudioDevice] for audio output.
  ///
  /// * Currently selected [AudioDevice] can be accessed using [getProperty].
  /// * The list of currently available [AudioDevice]s can be obtained accessed using [getAudioDevices].
  @override
  Future<void> setAudioDevice(
    AudioDevice audioDevice, {
    bool synchronized = true,
  }) {
    Future<void> function() {
      throwIfDisposed();

      return _setPropertyString('audio-device', audioDevice.name);
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Sets the current [VideoTrack] for video output.
  ///
  /// * Currently selected [VideoTrack] can be accessed using [state.track.video] or [stream.track.video].
  /// * The list of currently available [VideoTrack]s can be obtained accessed using [state.tracks.video] or [stream.tracks.video].
  @override
  Future<void> setVideoTrack(VideoTrack track, {bool synchronized = true}) {
    Future<void> function() async {
      throwIfDisposed();

      await _setPropertyString('vid', track.id);
      state.track = state.track.copyWith(video: track);
      if (!trackController.isClosed) {
        trackController.add(state.track);
      }
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Sets the current [AudioTrack] for audio output.
  ///
  /// * Currently selected [AudioTrack] can be accessed using [state.track.audio] or [stream.track.audio].
  /// * The list of currently available [AudioTrack]s can be obtained accessed using [state.tracks.audio] or [stream.tracks.audio].
  /// * External audio track can be loaded using [AudioTrack.uri] constructor.
  ///
  /// ```dart
  /// player.setAudioTrack(
  ///   AudioTrack.uri(
  ///     'https://www.iandevlin.com/html5test/webvtt/v/upc-tobymanley.mp4',
  ///     title: 'English',
  ///     language: 'en',
  ///   ),
  /// );
  /// ```
  ///
  @override
  Future<void> setAudioTrack(AudioTrack track, {bool synchronized = true}) {
    Future<void> function() async {
      throwIfDisposed();

      if (track.uri) {
        await command([
          'audio-add',
          track.id,
          'cache',
          track.title ?? 'external',
          track.language ?? 'auto',
        ]);
      } else {
        await _setPropertyString('aid', track.id);
        state.track = state.track.copyWith(audio: track);
        if (!trackController.isClosed) {
          trackController.add(state.track);
        }
      }
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Sets the current [SubtitleTrack] for subtitle output.
  ///
  /// * Currently selected [SubtitleTrack] can be accessed using [state.track.subtitle] or [stream.track.subtitle].
  /// * The list of currently available [SubtitleTrack]s can be obtained accessed using [state.tracks.subtitle] or [stream.tracks.subtitle].
  /// * External subtitle track can be loaded using [SubtitleTrack.uri] or [SubtitleTrack.data] constructor.
  ///
  /// ```dart
  /// player.setSubtitleTrack(
  ///   SubtitleTrack.uri(
  ///     'https://www.iandevlin.com/html5test/webvtt/upc-video-subtitles-en.vtt',
  ///     title: 'English',
  ///     language: 'en',
  ///   ),
  /// );
  /// ```
  ///
  @override
  Future<void> setSubtitleTrack(
    SubtitleTrack track, {
    bool synchronized = true,
  }) {
    Future<void> function() async {
      throwIfDisposed();

      // Reset existing Player.state.subtitle & Player.stream.subtitle.
      state.subtitle = const Subtitle.raw();
      if (!subtitleController.isClosed) {
        subtitleController.add(state.subtitle);
      }

      if (track.uri) {
        await command([
          'sub-add',
          track.id,
          'cached',
          track.title ?? 'external',
          track.language ?? 'auto',
        ]);
      } else {
        await _setPropertyString('sid', track.id);
        state.track = state.track.copyWith(subtitle: track);
        if (!trackController.isClosed) {
          trackController.add(state.track);
        }
      }
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Takes the snapshot of the current video frame & returns encoded image bytes as [Uint8List].
  ///
  /// The [format] parameter specifies the format of the image to be returned. Supported values are:
  /// * `image/jpeg`: Returns a JPEG encoded image.
  /// * `image/png`: Returns a PNG encoded image.
  /// * `null`: Returns BGRA pixel buffer.
  @override
  Future<Uint8List?> screenshot({
    ScreenshotFormat format = ScreenshotFormat.jpeg,
    bool synchronized = true,
  }) {
    Future<Uint8List?> function() {
      throwIfDisposed();

      return compute(
        _screenshot,
        _ScreenshotData(ctx.address, NativeLibrary.path, format),
      );
    }

    if (synchronized) {
      return lock.synchronized(function);
    } else {
      return function();
    }
  }

  /// Internal platform specific identifier for this [Player] instance.
  ///
  /// Since, [int] is a primitive type, it can be used to pass this [Player] instance to native code without directly depending upon this library.
  ///
  @override
  int get handle {
    assert(ctx != nullptr);
    return ctx.address;
  }

  /// Sets property for the internal libmpv instance of this [Player].
  /// Please use this method only if you know what you are doing, existing methods in [Player] implementation are suited for the most use cases.
  ///
  /// See:
  /// * https://mpv.io/manual/master/#options
  /// * https://mpv.io/manual/master/#properties
  ///
  void setProperty(String property, String value) {
    throwIfDisposed();

    final name = property.toNativeUtf8();
    final data = value.toNativeUtf8();
    mpv.mpv_set_property_string(ctx, name, data);
    calloc.free(name);
    calloc.free(data);
  }

  /// Retrieves the value of a property from the internal libmpv instance of this [Player].
  /// Please use this method only if you know what you are doing, existing methods in [Player] implementation are suited for the most use cases.
  ///
  /// See:
  /// * https://mpv.io/manual/master/#options
  /// * https://mpv.io/manual/master/#properties
  ///
  String getProperty(String property) {
    throwIfDisposed();

    final name = property.toNativeUtf8();
    final value = mpv.mpv_get_property_string(ctx, name);
    if (value != nullptr) {
      final result = value.toDartString();
      calloc.free(name);
      mpv.mpv_free(value.cast());

      return result;
    }

    return "";
  }

  Future<void> _handler(Pointer<generated.mpv_event> event) async {
    final eventId = event.ref.event_id;
    switch (eventId) {
      case generated.mpv_event_id.MPV_EVENT_PROPERTY_CHANGE:
        final prop = event.ref.data.cast<generated.mpv_event_property>();
        if (prop.ref.format == generated.mpv_format.MPV_FORMAT_FLAG &&
            prop.ref.name.toDartString() == 'idle-active') {
          await _future;
          if (!completer.isCompleted) completer.complete();
        }
      case generated.mpv_event_id.MPV_EVENT_SET_PROPERTY_REPLY:
      case generated.mpv_event_id.MPV_EVENT_COMMAND_REPLY:
        final data = event.ref.reply_userdata;
        final completer = _requests.remove(data);
        if (completer == null) {
          final text = 'Received MPV_EVENT_REPLY with unregistered ID $data';
          if (!logController.isClosed) {
            logController.add(
              PlayerLog(prefix: 'native', level: 'error', text: text),
            );
          }
          if (!errorController.isClosed) {
            errorController.add(text);
          }
          print('Warning: $text');
        } else {
          completer.complete(event.ref.error);
        }
    }

    if (!completer.isCompleted) {
      // Ignore the events which are fired before the initialization.
      return;
    }

    _error(event.ref.error);

    switch (eventId) {
      case generated.mpv_event_id.MPV_EVENT_START_FILE:
        if (isPlayingStateChangeAllowed) {
          state
            ..playing = true
            ..completed = false;
          if (!playingController.isClosed) {
            playingController.add(true);
          }
          if (!completedController.isClosed) {
            completedController.add(false);
          }
        }
        state.buffering = true;
        if (!bufferingController.isClosed) {
          bufferingController.add(true);
        }
      // NOTE: Now, --keep-open=yes is used. Thus, eof-reached property is used instead of this.
      // case generated.mpv_event_id.MPV_EVENT_END_FILE:
      //   // Check for mpv_end_file_reason.MPV_END_FILE_REASON_EOF before modifying state.completed.
      //   if (event.ref.data.cast<generated.mpv_event_end_file>().ref.reason ==
      //       generated.mpv_end_file_reason.MPV_END_FILE_REASON_EOF) {
      //     if (isPlayingStateChangeAllowed) {
      //       state = state.copyWith(playing: false, completed: true);
      //       if (!playingController.isClosed) {
      //         playingController.add(false);
      //       }
      //       if (!completedController.isClosed) {
      //         completedController.add(true);
      //       }
      //     }
      //   }
      case generated.mpv_event_id.MPV_EVENT_PROPERTY_CHANGE:
        final prop = event.ref.data.cast<generated.mpv_event_property>();
        switch (prop.ref.name.toDartString()) {
          case 'pause':
            if (prop.ref.format == generated.mpv_format.MPV_FORMAT_FLAG) {
              final playing = prop.ref.data.cast<Int8>().value == 0;
              if (isPlayingStateChangeAllowed) {
                state.playing = playing;
                if (!playingController.isClosed) {
                  playingController.add(playing);
                }
              }
            }
          case 'core-idle':
            if (prop.ref.format == generated.mpv_format.MPV_FORMAT_FLAG) {
              // Check for [isBufferingStateChangeAllowed] because `pause` causes `core-idle` to be fired.
              final buffering = prop.ref.data.cast<Int8>().value == 1;
              if (buffering) {
                if (isBufferingStateChangeAllowed) {
                  state.buffering = true;
                  if (!bufferingController.isClosed) {
                    bufferingController.add(true);
                  }
                }
              } else {
                state.buffering = false;
                if (!bufferingController.isClosed) {
                  bufferingController.add(false);
                }
              }
              isBufferingStateChangeAllowed = true;
            }
          case 'paused-for-cache':
            if (prop.ref.format == generated.mpv_format.MPV_FORMAT_FLAG) {
              final buffering = prop.ref.data.cast<Int8>().value == 1;
              state.buffering = buffering;
              if (!bufferingController.isClosed) {
                bufferingController.add(buffering);
              }
            }
          case 'demuxer-cache-time':
            if (prop.ref.format == generated.mpv_format.MPV_FORMAT_DOUBLE) {
              final buffer = Duration(
                microseconds: (prop.ref.data.cast<Double>().value * 1e6)
                    .toInt(),
              );
              state.buffer = buffer;
              if (!bufferController.isClosed) {
                bufferController.add(buffer);
              }
            }
          case 'time-pos':
            if (prop.ref.format == generated.mpv_format.MPV_FORMAT_DOUBLE) {
              final position = Duration(
                microseconds: (prop.ref.data.cast<Double>().value * 1e6)
                    .toInt(),
              );
              state.position = position;
              if (!positionController.isClosed) {
                positionController.add(position);
              }
            }
          case 'duration':
            if (prop.ref.format == generated.mpv_format.MPV_FORMAT_DOUBLE) {
              final duration = Duration(
                microseconds: (prop.ref.data.cast<Double>().value * 1e6)
                    .toInt(),
              );
              state.duration = duration;
              if (!durationController.isClosed) {
                durationController.add(duration);
              }
            }
          case 'playlist':
            if (prop.ref.format == generated.mpv_format.MPV_FORMAT_NODE) {
              final data = prop.ref.data.cast<generated.mpv_node>();
              final list = data.ref.u.list.ref;
              int index = -1;
              int mediaIdx = 0;
              List<Media> playlist = [];
              for (int i = 0; i < list.num; i++) {
                if (list.values[i].format ==
                    generated.mpv_format.MPV_FORMAT_NODE_MAP) {
                  final map = list.values[i].u.list.ref;
                  for (int j = 0; j < map.num; j++) {
                    switch (map.keys[j].toDartString()) {
                      case 'playing':
                        if (map.values[j].format ==
                            generated.mpv_format.MPV_FORMAT_FLAG) {
                          final value = map.values[j].u.flag;
                          if (value == 1) {
                            index = i;
                          }
                        }
                      case 'filename':
                        if (map.values[j].format ==
                            generated.mpv_format.MPV_FORMAT_STRING) {
                          final v = map.values[j].u.string.toDartString();
                          playlist.add(current[mediaIdx++].copyWith(uri: v));
                        }
                    }
                  }
                }
              }

              if (index >= 0) {
                state.playlist = Playlist(playlist, index: index);
                if (!playlistController.isClosed) {
                  playlistController.add(state.playlist);
                }
              }
            }
          case 'audio-params':
            if (prop.ref.format == generated.mpv_format.MPV_FORMAT_NODE) {
              final data = prop.ref.data.cast<generated.mpv_node>();
              final list = data.ref.u.list.ref;

              String? format, channels, hrChannels;
              int? sampleRate, channelCount;

              for (int i = 0; i < list.num; i++) {
                final key = list.keys[i].toDartString();
                switch (key) {
                  case 'format':
                    format = list.values[i].u.string.toDartString();
                  case 'samplerate':
                    sampleRate = list.values[i].u.int64;
                  case 'channels':
                    channels = list.values[i].u.string.toDartString();
                  case 'channel-count':
                    channelCount = list.values[i].u.int64;
                  case 'hr-channels':
                    hrChannels = list.values[i].u.string.toDartString();
                }
              }
              state.audioParams = AudioParams(
                format: format,
                sampleRate: sampleRate,
                channels: channels,
                channelCount: channelCount,
                hrChannels: hrChannels,
              );
              if (!audioParamsController.isClosed) {
                audioParamsController.add(state.audioParams);
              }
            }
          case 'track-list':
            if (prop.ref.format == generated.mpv_format.MPV_FORMAT_NODE) {
              final value = prop.ref.data.cast<generated.mpv_node>();
              if (value.ref.format ==
                  generated.mpv_format.MPV_FORMAT_NODE_ARRAY) {
                final video = [VideoTrack.auto(), VideoTrack.no()];
                final audio = [AudioTrack.auto(), AudioTrack.no()];
                final subtitle = [SubtitleTrack.auto(), SubtitleTrack.no()];

                VideoTrack vt = VideoTrack.no();
                AudioTrack at = AudioTrack.no();
                SubtitleTrack st = SubtitleTrack.no();

                final tracks = value.ref.u.list.ref;

                for (int i = 0; i < tracks.num; i++) {
                  if (tracks.values[i].format ==
                      generated.mpv_format.MPV_FORMAT_NODE_MAP) {
                    final map = tracks.values[i].u.list.ref;
                    String id = '';
                    String type = '';
                    String? title;
                    String? language;
                    bool? image;
                    bool? albumart;
                    String? codec;
                    String? decoder;
                    int? w;
                    int? h;
                    int? channelscount;
                    String? channels;
                    int? samplerate;
                    double? fps;
                    int? bitrate;
                    int? rotate;
                    double? par;
                    int? audiochannels;
                    bool selected = false;
                    String? externalFilename;
                    for (int j = 0; j < map.num; j++) {
                      final property = map.keys[j].toDartString();
                      switch (map.values[j].format) {
                        case generated.mpv_format.MPV_FORMAT_STRING:
                          final value = map.values[j].u.string.toDartString();
                          switch (property) {
                            case 'type':
                              type = value;
                            case 'title':
                              title = value;
                            case 'lang':
                              language = value;
                            case 'codec':
                              codec = value;
                            case 'decoder-desc':
                              decoder = value;
                            case 'demux-channels':
                              channels = value;
                            case 'external-filename':
                              externalFilename = value;
                          }
                        case generated.mpv_format.MPV_FORMAT_FLAG:
                          switch (property) {
                            case 'image':
                              image = map.values[j].u.flag != 0;
                            case 'albumart':
                              albumart = map.values[j].u.flag != 0;
                            case 'selected':
                              selected = map.values[j].u.flag != 0;
                          }
                        case generated.mpv_format.MPV_FORMAT_INT64:
                          switch (property) {
                            case 'id':
                              id = map.values[j].u.int64.toString();
                            case 'demux-w':
                              w = map.values[j].u.int64;
                            case 'demux-h':
                              h = map.values[j].u.int64;
                            case 'demux-channel-count':
                              channelscount = map.values[j].u.int64;
                            case 'demux-samplerate':
                              samplerate = map.values[j].u.int64;
                            case 'demux-bitrate':
                              bitrate = map.values[j].u.int64;
                            case 'demux-rotate':
                              rotate = map.values[j].u.int64;
                            case 'audio-channels':
                              audiochannels = map.values[j].u.int64;
                          }
                        case generated.mpv_format.MPV_FORMAT_DOUBLE:
                          switch (property) {
                            case 'demux-fps':
                              fps = map.values[j].u.double_;
                            case 'demux-par':
                              par = map.values[j].u.double_;
                          }
                      }
                    }
                    switch (type) {
                      case 'video':
                        final track = VideoTrack(
                          id,
                          title,
                          language,
                          image: image,
                          albumart: albumart,
                          codec: codec,
                          decoder: decoder,
                          w: w,
                          h: h,
                          channelscount: channelscount,
                          channels: channels,
                          samplerate: samplerate,
                          fps: fps,
                          bitrate: bitrate,
                          rotate: rotate,
                          par: par,
                          audiochannels: audiochannels,
                          externalFilename: externalFilename,
                          selected: selected,
                        );
                        video.add(track);
                        if (selected) vt = track;
                      case 'audio':
                        final track = AudioTrack(
                          id,
                          title,
                          language,
                          image: image,
                          albumart: albumart,
                          codec: codec,
                          decoder: decoder,
                          w: w,
                          h: h,
                          channelscount: channelscount,
                          channels: channels,
                          samplerate: samplerate,
                          fps: fps,
                          bitrate: bitrate,
                          rotate: rotate,
                          par: par,
                          audiochannels: audiochannels,
                          externalFilename: externalFilename,
                          selected: selected,
                        );
                        audio.add(track);
                        if (selected) at = track;
                      case 'sub':
                        final track = SubtitleTrack(
                          id,
                          title,
                          language,
                          image: image,
                          albumart: albumart,
                          codec: codec,
                          decoder: decoder,
                          w: w,
                          h: h,
                          channelscount: channelscount,
                          channels: channels,
                          samplerate: samplerate,
                          fps: fps,
                          bitrate: bitrate,
                          rotate: rotate,
                          par: par,
                          audiochannels: audiochannels,
                          externalFilename: externalFilename,
                          selected: selected,
                        );
                        subtitle.add(track);
                        if (selected) st = track;
                    }
                  }
                }

                state.track = Track(video: vt, audio: at, subtitle: st);
                if (!trackController.isClosed) {
                  trackController.add(state.track);
                }

                state.tracks = Tracks(
                  video: video,
                  audio: audio,
                  subtitle: subtitle,
                );
                if (!tracksController.isClosed) {
                  tracksController.add(state.tracks);
                }
              }
            }
          case 'sub-text':
            if (prop.ref.format == generated.mpv_format.MPV_FORMAT_NODE) {
              final value = prop.ref.data.cast<generated.mpv_node>();
              if (value.ref.format == generated.mpv_format.MPV_FORMAT_STRING) {
                final text = value.ref.u.string.toDartString();
                state.subtitle = state.subtitle.copyWith(first: text);
                if (!subtitleController.isClosed) {
                  subtitleController.add(state.subtitle);
                }
              }
            }
          case 'secondary-sub-text':
            if (prop.ref.format == generated.mpv_format.MPV_FORMAT_NODE) {
              final value = prop.ref.data.cast<generated.mpv_node>();
              if (value.ref.format == generated.mpv_format.MPV_FORMAT_STRING) {
                final text = value.ref.u.string.toDartString();
                state.subtitle = state.subtitle.copyWith(second: text);
                if (!subtitleController.isClosed) {
                  subtitleController.add(state.subtitle);
                }
              }
            }
          case 'eof-reached':
            if (prop.ref.format == generated.mpv_format.MPV_FORMAT_FLAG) {
              final value = prop.ref.data.cast<Bool>().value;
              if (value) {
                if (isPlayingStateChangeAllowed) {
                  state
                    ..playing = false
                    ..completed = true;
                  if (!playingController.isClosed) {
                    playingController.add(false);
                  }
                  if (!completedController.isClosed) {
                    completedController.add(true);
                  }
                }

                state
                  ..buffering = false
                  ..track = const Track()
                  ..tracks = const Tracks();
                if (!bufferingController.isClosed) {
                  bufferingController.add(false);
                }
                if (!tracksController.isClosed) {
                  tracksController.add(const Tracks());
                }
                if (!trackController.isClosed) {
                  trackController.add(const Track());
                }
              }
            }
          case 'video-out-params':
            if (prop.ref.format == generated.mpv_format.MPV_FORMAT_NODE) {
              final node = prop.ref.data.cast<generated.mpv_node>().ref;
              final data = <String, dynamic>{};
              for (int i = 0; i < node.u.list.ref.num; i++) {
                final key = node.u.list.ref.keys[i].toDartString();
                final value = node.u.list.ref.values[i];
                switch (value.format) {
                  case generated.mpv_format.MPV_FORMAT_INT64:
                    data[key] = value.u.int64;
                  case generated.mpv_format.MPV_FORMAT_DOUBLE:
                    data[key] = value.u.double_;
                  case generated.mpv_format.MPV_FORMAT_STRING:
                    data[key] = value.u.string.toDartString();
                }
              }

              final params = VideoParams(
                pixelformat: data['pixelformat'],
                hwPixelformat: data['hw-pixelformat'],
                w: data['w'],
                h: data['h'],
                dw: data['dw'],
                dh: data['dh'],
                aspect: data['aspect'],
                par: data['par'],
                colormatrix: data['colormatrix'],
                colorlevels: data['colorlevels'],
                primaries: data['primaries'],
                gamma: data['gamma'],
                sigPeak: data['sig-peak'],
                light: data['light'],
                chromaLocation: data['chroma-location'],
                rotate: data['rotate'],
                stereoIn: data['stereo-in'],
                averageBpp: data['average-bpp'],
                alpha: data['alpha'],
              );

              state.videoParams = params;
              if (!videoParamsController.isClosed) {
                videoParamsController.add(params);
              }

              final dw = params.dw;
              final dh = params.dh;
              final rotate = params.rotate ?? 0;
              if (dw != null && dh != null) {
                final int width;
                final int height;
                if (rotate == 0 || rotate == 180) {
                  width = dw;
                  height = dh;
                } else {
                  // width & height are swapped for 90 or 270 degrees rotation.
                  width = dh;
                  height = dw;
                }
                state
                  ..width = width
                  ..height = height;
                if (!sizeController.isClosed) {
                  sizeController.add((width, height));
                }
              }
            }
        }
      case generated.mpv_event_id.MPV_EVENT_LOG_MESSAGE:
        final eventLogMessage = event.ref.data
            .cast<generated.mpv_event_log_message>()
            .ref;
        final prefix = eventLogMessage.prefix.toDartString().trim();
        final level = eventLogMessage.level.toDartString().trim();
        final text = eventLogMessage.text.toDartString().trim();
        if (!logController.isClosed) {
          logController.add(
            PlayerLog(prefix: prefix, level: level, text: text),
          );
          // --------------------------------------------------
          // Emit error(s) based on the log messages.
          if (level == 'error') {
            switch (prefix) {
              // file:// not found.
              case 'file':
              // http:// error of any kind.
              case 'ffmpeg':
              case 'vd':
              case 'ad':
              case 'cplayer':
              case 'stream':
                if (!errorController.isClosed) {
                  errorController.add(text);
                }
            }
          }
          // --------------------------------------------------
        }
      case generated.mpv_event_id.MPV_EVENT_HOOK:
        final prop = event.ref.data.cast<generated.mpv_event_hook>();
        switch (prop.ref.name.toDartString()) {
          case 'on_load':
            // --------------------------------------------------
            for (final hook in onLoadHooks) {
              try {
                await hook();
              } catch (exception, stacktrace) {
                print(exception);
                print(stacktrace);
              }
            }
            // --------------------------------------------------
            // Handle HTTP headers specified in the [Media].
            // try {
            //   final name = 'path'.toNativeUtf8();
            //   final uri = mpv.mpv_get_property_string(ctx, name);
            //   // Get the headers for current [Media] by looking up [uri] in the [HashMap].
            //   final headers = Media(uri.toDartString()).httpHeaders;
            //   if (headers != null) {
            //     setHeader(headers, mpv, ctx);
            //   }
            //   mpv.mpv_free(uri.cast());
            //   calloc.free(name);
            // } catch (exception, stacktrace) {
            //   print(exception);
            //   print(stacktrace);
            // }
            // Handle start & end position specified in the [Media].
            try {
              final name = 'playlist-pos'.toNativeUtf8();
              final value = calloc<Int64>();
              value.value = -1;

              mpv.mpv_get_property(
                ctx,
                name,
                generated.mpv_format.MPV_FORMAT_INT64,
                value.cast(),
              );

              final index = value.value;

              calloc.free(name);
              calloc.free(value);

              if (index >= 0) {
                final start = current[index].start;
                final end = current[index].end;

                if (start != null) {
                  try {
                    final property = 'start'.toNativeUtf8();
                    final value = (start.inMilliseconds / 1000)
                        .toStringAsFixed(3)
                        .toNativeUtf8();
                    mpv.mpv_set_property_string(ctx, property, value);
                    calloc.free(property);
                    calloc.free(value);
                  } catch (exception, stacktrace) {
                    print(exception);
                    print(stacktrace);
                  }
                }

                if (end != null) {
                  try {
                    final property = 'end'.toNativeUtf8();
                    final value = (end.inMilliseconds / 1000)
                        .toStringAsFixed(3)
                        .toNativeUtf8();
                    mpv.mpv_set_property_string(ctx, property, value);
                    calloc.free(property);
                    calloc.free(value);
                  } catch (exception, stacktrace) {
                    print(exception);
                    print(stacktrace);
                  }
                }
              }
            } catch (exception, stacktrace) {
              print(exception);
              print(stacktrace);
            }
            // --------------------------------------------------
            mpv.mpv_hook_continue(ctx, prop.ref.id);

          case 'on_unload':
            // --------------------------------------------------
            for (final hook in onUnloadHooks) {
              try {
                await hook();
              } catch (exception, stacktrace) {
                print(exception);
                print(stacktrace);
              }
            }
            // --------------------------------------------------
            // Set http-header-fields as [generated.mpv_format.MPV_FORMAT_NONE] [generated.mpv_node].
            // try {
            //   final property = 'http-header-fields'.toNativeUtf8();
            //   final value = calloc<generated.mpv_node>();
            //   value.ref.format = generated.mpv_format.MPV_FORMAT_NONE;
            //   mpv.mpv_set_property(
            //     ctx,
            //     property,
            //     generated.mpv_format.MPV_FORMAT_NODE,
            //     value.cast(),
            //   );
            //   calloc.free(property);
            //   calloc.free(value);
            // } catch (exception, stacktrace) {
            //   print(exception);
            //   print(stacktrace);
            // }
            // Set start & end position as [generated.mpv_format.MPV_FORMAT_NONE] [generated.mpv_node].
            try {
              final property = 'start'.toNativeUtf8();
              final value = 'none'.toNativeUtf8();
              mpv.mpv_set_property_string(ctx, property, value);
              calloc.free(property);
              calloc.free(value);
            } catch (exception, stacktrace) {
              print(exception);
              print(stacktrace);
            }
            try {
              final property = 'end'.toNativeUtf8();
              final value = 'none'.toNativeUtf8();
              mpv.mpv_set_property_string(ctx, property, value);
              calloc.free(property);
              calloc.free(value);
            } catch (exception, stacktrace) {
              print(exception);
              print(stacktrace);
            }
            // --------------------------------------------------
            mpv.mpv_hook_continue(ctx, prop.ref.id);
        }
    }
  }

  Future<void> _create() async {
    // The options which must be set before [MPV.mpv_initialize].
    final options = <String, String>{
      // Set --vid=no by default to prevent redundant video decoding.
      // [VideoController] internally sets --vid=auto upon attachment to enable video rendering & decoding.
      if (!test) 'vid': 'no',
      ...?configuration.options,
    };

    ctx = await Initializer.create(mpv, _handler, options: options);

    // ALL:
    //
    // idle = yes
    // pause = yes
    // keep-open = yes
    // audio-display = no
    // network-timeout = 5
    // scale=bilinear
    // dscale=bilinear
    // dither=no
    // correct-downscaling=no
    // linear-downscaling=no
    // sigmoid-upscaling=no
    // hdr-compute-peak=no
    //
    // ANDROID (Physical Device OR API Level > 25):
    //
    // ao = opensles
    //
    // ANDROID (Emulator AND API Level <= 25):
    //
    // ao = null
    //
    final properties = <String, String>{
      'idle': 'yes',
      'pause': 'yes',
      'keep-open': 'yes',
      'audio-display': 'no',
      'network-timeout': '5',
      // https://github.com/mpv-player/mpv/commit/703f1588803eaa428e09c0e5547b26c0fff476a7
      // https://github.com/mpv-android/mpv-android/commit/9e5c3d8a630290fc41edb8b03aeafa3bc4c45955
      'scale': 'bilinear',
      'dscale': 'bilinear',
      'dither': 'no',
      'cache': 'yes',
      'correct-downscaling': 'no',
      'linear-downscaling': 'no',
      'sigmoid-upscaling': 'no',
      'hdr-compute-peak': 'no',
      'subs-fallback': 'yes',
      'subs-with-matching-audio': 'yes',

      // Other properties based on [PlayerConfiguration].
      if (!configuration.osc) ...const {'osc': 'no', 'osd-level': '0'},
      'title': configuration.title,
      'demuxer-max-bytes': configuration.bufferSize.toString(),
      'demuxer-max-back-bytes': configuration.bufferSize.toString(),
      if (configuration.vo != null) 'vo': '${configuration.vo}',
      'demuxer-lavf-o': [
        'seg_max_retry=5',
        'strict=experimental',
        'allowed_extensions=ALL',
        'protocol_whitelist=[${configuration.protocolWhitelist.join(',')}]',
      ].join(','),
      'sub-ass': 'no',
      'sub-visibility': 'no',
      'secondary-sub-visibility': 'no',
    };

    if (test) {
      properties['vo'] = 'null';
      properties['ao'] = 'null';
    }

    await Future.wait(
      properties.entries.map(
        (entry) => _setPropertyString(entry.key, entry.value),
      ),
    );

    // if (configuration.muted) {
    //   await _setPropertyDouble('volume', 0);

    //   state = state.copyWith(volume: 0.0);
    //   if (!volumeController.isClosed) {
    //     volumeController.add(0.0);
    //   }
    // }

    // Observe the properties to update the state & feed event stream.
    for (final i in const [
      ('pause', generated.mpv_format.MPV_FORMAT_FLAG),
      ('time-pos', generated.mpv_format.MPV_FORMAT_DOUBLE),
      ('duration', generated.mpv_format.MPV_FORMAT_DOUBLE),
      ('playlist', generated.mpv_format.MPV_FORMAT_NODE),
      ('core-idle', generated.mpv_format.MPV_FORMAT_FLAG),
      ('paused-for-cache', generated.mpv_format.MPV_FORMAT_FLAG),
      ('demuxer-cache-time', generated.mpv_format.MPV_FORMAT_DOUBLE),
      ('audio-params', generated.mpv_format.MPV_FORMAT_NODE),
      ('video-out-params', generated.mpv_format.MPV_FORMAT_NODE),
      ('track-list', generated.mpv_format.MPV_FORMAT_NODE),
      ('eof-reached', generated.mpv_format.MPV_FORMAT_FLAG),
      ('idle-active', generated.mpv_format.MPV_FORMAT_FLAG),
      ('sub-text', generated.mpv_format.MPV_FORMAT_NODE),
      ('secondary-sub-text', generated.mpv_format.MPV_FORMAT_NODE),
    ]) {
      final name = i.$1.toNativeUtf8();
      mpv.mpv_observe_property(ctx, 0, name, i.$2);
      calloc.free(name);
    }

    // https://github.com/mpv-player/mpv/blob/e1727553f164181265f71a20106fbd5e34fa08b0/libmpv/client.h#L1410-L1419
    final min = configuration.logLevel.name.toNativeUtf8();
    mpv.mpv_request_log_messages(ctx, min);
    calloc.free(min);

    // Add libmpv hooks for supporting custom HTTP headers in [Media].
    final load = 'on_load'.toNativeUtf8();
    final unload = 'on_unload'.toNativeUtf8();
    mpv.mpv_hook_add(ctx, 0, load, 0);
    mpv.mpv_hook_add(ctx, 0, unload, 0);
    calloc.free(load);
    calloc.free(unload);

    configuration.ready?.call();
  }

  /// Adds an error to the [Player.stream.error].
  void _error(int code) {
    if (code < 0 && !errorController.isClosed) {
      final message = mpv.mpv_error_string(code).toDartString();
      errorController.add(message);
    }
  }

  int _asyncRequestNumber = 1;
  final Map<int, Completer<int>> _requests = {};

  /// Asynchronous property setting
  Future<void> _setProperty(String name, int format, Pointer<Void> data) {
    final requestNumber = _asyncRequestNumber++;
    final completer = _requests[requestNumber] = Completer<int>();
    final namePtr = name.toNativeUtf8();
    final immediate = mpv.mpv_set_property_async(
      ctx,
      requestNumber,
      namePtr,
      format,
      data,
    );
    calloc.free(namePtr);
    if (immediate < 0) {
      // Sending failed
      _requests.remove(requestNumber);
      completer.complete(immediate);
    }
    return completer.future.then(_error);
  }

  Future<void> _setPropertyFlag(String name, bool value) async {
    final ptr = calloc<Bool>(1)..value = value;
    await _setProperty(name, generated.mpv_format.MPV_FORMAT_FLAG, ptr.cast());
    calloc.free(ptr);
  }

  Future<void> _setPropertyDouble(String name, double value) async {
    final ptr = calloc<Double>(1)..value = value;
    await _setProperty(
      name,
      generated.mpv_format.MPV_FORMAT_DOUBLE,
      ptr.cast(),
    );
    calloc.free(ptr);
  }

  Future<void> _setPropertyInt64(String name, int value) async {
    final ptr = calloc<Int64>(1)..value = value;
    await _setProperty(name, generated.mpv_format.MPV_FORMAT_INT64, ptr.cast());
    calloc.free(ptr);
  }

  Future<void> _setPropertyString(String name, String value) async {
    final string = value.toNativeUtf8();
    // It wants char**
    final ptr = calloc<Pointer<Void>>(1)..value = string.cast();
    await _setProperty(
      name,
      generated.mpv_format.MPV_FORMAT_STRING,
      ptr.cast(),
    );
    calloc.free(ptr);
    calloc.free(string);
  }

  /// Calls mpv command passed as [args].
  /// Automatically freeds memory after command sending.
  Future<void> command(List<String> args) {
    final pointers = args.map<Pointer<Uint8>>((e) => e.toNativeUtf8()).toList();
    final arr = calloc<Pointer<Uint8>>(pointers.length + 1);
    for (int i = 0; i < args.length; i++) {
      arr[i] = pointers[i];
    }
    final requestNumber = _asyncRequestNumber++;
    final completer = _requests[requestNumber] = Completer<int>();
    final immediate = mpv.mpv_command_async(ctx, requestNumber, arr);
    calloc.free(arr);
    pointers.forEach(calloc.free);
    if (immediate < 0) {
      // Sending failed
      _requests.remove(requestNumber);
      completer.complete(immediate);
    }
    return completer.future.then(_error);
  }

  /// Internal generated libmpv C API bindings.
  static final mpv = generated.MPV(DynamicLibrary.open(NativeLibrary.path));

  // (major << 16) | minor
  static final apiVersion = mpv.mpv_client_api_version();

  /// [Pointer] to [generated.mpv_handle] of this instance.
  Pointer<generated.mpv_handle> ctx = nullptr;

  /// The [Future] to wait for [_create] completion.
  /// This is used to prevent signaling [completer] (from [PlatformPlayer]) before [_create] completes in any hypothetical situation (because `idle-active` may fire before it).
  Future<void>? _future;

  /// Internal flag to avoid emitting events during disposal cleanup
  bool _isDisposing = false;

  /// Whether the [Player] has been disposed. This is used to prevent accessing dangling [ctx] after [dispose].
  bool disposed = false;

  /// A flag to keep track of [setShuffle] calls.
  bool isShuffleEnabled = false;

  /// A flag to prevent changes to [state.playing] due to `loadfile` commands in [open].
  ///
  /// By default, `MPV_EVENT_START_FILE` is fired when a new media source is loaded.
  /// This event modifies the [state.playing] & [stream.playing] to `true`.
  ///
  /// However, the [Player] is in paused state before the media source is loaded.
  /// Thus, [state.playing] should not be changed, unless the user explicitly calls [play] or [playOrPause].
  ///
  /// We set [isPlayingStateChangeAllowed] to `false` at the start of [open] to prevent this unwanted change & set it to `true` at the end of [open].
  /// While [isPlayingStateChangeAllowed] is `false`, any change to [state.playing] & [stream.playing] is ignored.
  bool isPlayingStateChangeAllowed = false;

  /// A flag to prevent changes to [state.buffering] due to `pause` causing `core-idle` to be `true`.
  ///
  /// This is used to prevent [state.buffering] being set to `true` when [pause] or [playOrPause] is called.
  bool isBufferingStateChangeAllowed = true;

  /// Current loaded [Media] queue.
  final List<Media> current = <Media>[];

  /// The methods which must execute synchronously before playback of a source can begin.
  final List<FutureOr<void> Function()> onLoadHooks = [];

  /// The methods which must execute synchronously before playback of a source can end.
  final List<FutureOr<void> Function()> onUnloadHooks = [];

  /// Synchronization & mutual exclusion between methods of this class.
  final Lock lock = Lock();

  /// Whether the [NativePlayer] is initialized for unit-testing.
  @visibleForTesting
  static bool test = false;

  void setMediaHeader({
    String? userAgent,
    String? referer,
    Map<String, String>? headers,
  }) => setHeader(
    mpv,
    ctx,
    headers: headers,
    userAgent: userAgent,
    referer: referer,
  );

  static void setPropertyString(
    generated.MPV mpv,
    Pointer<generated.mpv_handle> ctx,
    String name,
    String value,
  ) {
    final string = value.toNativeUtf8();
    final ptr = calloc<Pointer<Void>>(1)..value = string.cast();
    final namePtr = name.toNativeUtf8();
    mpv.mpv_set_property(
      ctx,
      namePtr,
      generated.mpv_format.MPV_FORMAT_STRING,
      ptr.cast(),
    );
    calloc.free(namePtr);
    calloc.free(ptr);
    calloc.free(string);
  }

  static void setHeader(
    generated.MPV mpv,
    Pointer<generated.mpv_handle> ctx, {
    String? userAgent,
    String? referer,
    Map<String, String>? headers,
  }) {
    if (userAgent != null) setPropertyString(mpv, ctx, 'user-agent', userAgent);
    if (referer != null) setPropertyString(mpv, ctx, 'referrer', referer);
    if (headers != null) {
      assert(
        !(headers.containsKey('user-agent') ||
            headers.containsKey('User-Agent')),
      );
      final property = 'http-header-fields'.toNativeUtf8();
      // Allocate & fill the [mpv_node] with the headers.
      final value = calloc<generated.mpv_node>();
      final valRef = value.ref
        ..format = generated.mpv_format.MPV_FORMAT_NODE_ARRAY;
      valRef.u.list = calloc<generated.mpv_node_list>();
      final valList = valRef.u.list.ref
        ..num = headers.length
        ..values = calloc<generated.mpv_node>(headers.length);

      int i = 0;
      for (var e in headers.entries) {
        valList.values[i++]
          ..format = generated.mpv_format.MPV_FORMAT_STRING
          ..u.string = '${e.key}: ${e.value}'.toNativeUtf8();
      }
      mpv.mpv_set_property(
        ctx,
        property,
        generated.mpv_format.MPV_FORMAT_NODE,
        value.cast(),
      );
      // Free the allocated memory.
      calloc.free(property);
      for (int i = 0; i < valList.num; i++) {
        calloc.free(valList.values[i].u.string);
      }
      calloc
        ..free(valList.values)
        ..free(valRef.u.list)
        ..free(value);
    }
  }

  void setOption(String opt, String value) {
    final name = opt.toNativeUtf8();
    final data = value.toNativeUtf8();
    mpv.mpv_set_option_string(ctx, name, data);
    calloc.free(name);
    calloc.free(data);
  }

  List<AudioDevice> getAudioDevices() {
    final name = 'audio-device-list'.toNativeUtf8();
    final value = calloc<generated.mpv_node>();
    final ret = mpv.mpv_get_property(
      ctx,
      name,
      generated.mpv_format.MPV_FORMAT_NODE,
      value.cast(),
    );
    final audioDevices = <AudioDevice>[];
    if (ret >= 0) {
      if (value.ref.format == generated.mpv_format.MPV_FORMAT_NODE_ARRAY) {
        final list = value.ref.u.list.ref;
        for (int i = 0; i < list.num; i++) {
          if (list.values[i].format ==
              generated.mpv_format.MPV_FORMAT_NODE_MAP) {
            String name = '', description = '';
            final device = list.values[i].u.list.ref;
            for (int j = 0; j < device.num; j++) {
              if (device.values[j].format ==
                  generated.mpv_format.MPV_FORMAT_STRING) {
                final value = device.values[j].u.string.toDartString();
                switch (device.keys[j].toDartString()) {
                  case 'name':
                    name = value;
                  case 'description':
                    description = value;
                }
              }
            }
            audioDevices.add(AudioDevice(name, description));
          }
        }
      }
    } else {
      _error(ret);
    }
    calloc.free(name);
    mpv.mpv_free_node_contents(value.cast());
    calloc.free(value);
    return audioDevices;
  }
}

// --------------------------------------------------
// Performance sensitive methods in [Player] are executed in an [Isolate].
// This avoids blocking the Dart event loop for long periods of time.
//
// TODO: Maybe eventually move all methods to [Isolate]?
// --------------------------------------------------

class _ScreenshotData {
  final int ctx;
  final String lib;
  final ScreenshotFormat format;

  const _ScreenshotData(this.ctx, this.lib, this.format);
}

/// [NativePlayer.screenshot]
Uint8List? _screenshot(_ScreenshotData data) {
  // ---------
  final mpv = generated.MPV(DynamicLibrary.open(data.lib));
  final ctx = Pointer<generated.mpv_handle>.fromAddress(data.ctx);
  // ---------
  final format = data.format;
  // ---------

  // https://mpv.io/manual/stable/#command-interface-screenshot-raw
  const args = ['screenshot-raw', 'video'];

  final result = calloc<generated.mpv_node>();

  final pointers = args.map((e) => e.toNativeUtf8()).toList();
  final arr = calloc<Pointer<Uint8>>(args.length + 1);
  for (int i = 0; i < args.length; i++) {
    arr[i] = pointers[i];
  }
  mpv.mpv_command_ret(ctx, arr, result);

  Uint8List? image;

  if (result.ref.format == generated.mpv_format.MPV_FORMAT_NODE_MAP) {
    int? w, h, stride;
    Uint8List? bytes;

    final map = result.ref.u.list;
    for (int i = 0; i < map.ref.num; i++) {
      final key = map.ref.keys[i].toDartString();
      final value = map.ref.values[i];
      switch (value.format) {
        case generated.mpv_format.MPV_FORMAT_INT64:
          switch (key) {
            case 'w':
              w = value.u.int64;
            case 'h':
              h = value.u.int64;
            case 'stride':
              stride = value.u.int64;
          }
        case generated.mpv_format.MPV_FORMAT_BYTE_ARRAY:
          switch (key) {
            case 'data':
              final data = value.u.ba.ref.data.cast<Uint8>();
              bytes = data.asTypedList(value.u.ba.ref.size);
          }
      }
    }

    if (w != null && h != null && stride != null && bytes != null) {
      switch (format) {
        case ScreenshotFormat.jpeg:
          final pixels = Image(width: w, height: h, numChannels: 3);
          final data = pixels.data!.buffer.asUint8List();
          for (int y = 0; y < h; y++) {
            final srcRowStart = y * stride;
            final dstRowStart = y * w * 3;
            for (int x = 0; x < w; x++) {
              final srcIdx = srcRowStart + (x << 2);
              final dstIdx = dstRowStart + x * 3;
              data[dstIdx] = bytes[srcIdx + 2]; // R
              data[dstIdx + 1] = bytes[srcIdx + 1]; // G
              data[dstIdx + 2] = bytes[srcIdx]; // B
            }
          }
          image = encodeJpg(pixels);
        case ScreenshotFormat.png:
          final pixels = Image(width: w, height: h, numChannels: 3);
          final data = pixels.data!.buffer.asUint8List();
          for (int y = 0; y < h; y++) {
            final srcRowStart = y * stride;
            final dstRowStart = y * w * 3;
            for (int x = 0; x < w; x++) {
              final srcIdx = srcRowStart + (x << 2);
              final dstIdx = dstRowStart + x * 3;
              data[dstIdx] = bytes[srcIdx + 2]; // R
              data[dstIdx + 1] = bytes[srcIdx + 1]; // G
              data[dstIdx + 2] = bytes[srcIdx]; // B
            }
          }
          image = encodePng(pixels);
        case ScreenshotFormat.none:
          image = bytes;
      }
    }
  }

  pointers.forEach(calloc.free);
  mpv.mpv_free_node_contents(result);

  calloc.free(arr);
  calloc.free(result);

  return image;
}

// --------------------------------------------------
