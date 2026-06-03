/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';
import 'package:media_kit/src/models/subtitle.dart';
import 'package:meta/meta.dart';

import 'package:media_kit/src/models/track.dart';
import 'package:media_kit/src/models/playable.dart';
import 'package:media_kit/src/models/player_log.dart';
import 'package:media_kit/src/models/audio_device.dart';
import 'package:media_kit/src/models/audio_params.dart';
import 'package:media_kit/src/models/video_params.dart';
import 'package:media_kit/src/models/player_state.dart';
import 'package:media_kit/src/models/playlist_mode.dart';
import 'package:media_kit/src/models/player_stream.dart';

/// {@template platform_player}
/// PlatformPlayer
/// --------------
///
/// This class provides the interface for platform specific [Player] implementations.
/// The platform specific implementations are expected to implement the methods accordingly.
///
/// The subclasses are then used in composition with the [Player] class, based on the platform the application is running on.
///
/// {@endtemplate}
abstract class PlatformPlayer {
  /// {@macro platform_player}
  PlatformPlayer({required this.configuration});

  /// User defined configuration for [Player].
  final PlayerConfiguration configuration;

  /// Current state of the player.
  final PlayerState state = PlayerState();

  /// Current state of the player available as listenable [Stream]s.
  /// TODO: ValueNotifier instead
  late final PlayerStream stream = PlayerStream(
    playlistController.stream.distinct(),
    playingController.stream.distinct(),
    completedController.stream.distinct(),
    positionController.stream.distinct(),
    durationController.stream.distinct(),
    bufferingController.stream.distinct(),
    bufferController.stream.distinct(),
    /* AUDIO-PARAMS STREAM SHOULD NOT BE DISTINCT */
    audioParamsController.stream,
    /* VIDEO-PARAMS STREAM SHOULD NOT BE DISTINCT */
    videoParamsController.stream,
    trackController.stream.distinct(),
    tracksController.stream.distinct(),
    sizeController.stream.distinct(),
    subtitleController.stream.distinct(),
    logController.stream.distinct(),
    /* ERROR STREAM SHOULD NOT BE DISTINCT */
    errorController.stream,
  );

  @mustCallSuper
  Future<void> dispose() {
    return Future.wait([
      playlistController.close(),
      playingController.close(),
      completedController.close(),
      positionController.close(),
      durationController.close(),
      bufferingController.close(),
      bufferController.close(),
      audioParamsController.close(),
      videoParamsController.close(),
      trackController.close(),
      tracksController.close(),
      sizeController.close(),
      subtitleController.close(),
      logController.close(),
      errorController.close(),
      ...release.map((i) => i()),
    ]);
  }

  Future<void> open(Playable playable, {bool play = true}) {
    throw UnimplementedError('[PlatformPlayer.open] is not implemented');
  }

  Future<void> stop() {
    throw UnimplementedError('[PlatformPlayer.stop] is not implemented');
  }

  Future<void> play() {
    throw UnimplementedError('[PlatformPlayer.play] is not implemented');
  }

  Future<void> pause() {
    throw UnimplementedError('[PlatformPlayer.pause] is not implemented');
  }

  Future<void> playOrPause() {
    throw UnimplementedError('[PlatformPlayer.playOrPause] is not implemented');
  }

  Future<void> add(Media media) {
    throw UnimplementedError('[PlatformPlayer.add] is not implemented');
  }

  Future<void> remove(int index) {
    throw UnimplementedError('[PlatformPlayer.remove] is not implemented');
  }

  Future<void> next() {
    throw UnimplementedError('[PlatformPlayer.next] is not implemented');
  }

  Future<void> previous() {
    throw UnimplementedError('[PlatformPlayer.previous] is not implemented');
  }

  Future<void> jump(int index) {
    throw UnimplementedError('[PlatformPlayer.jump] is not implemented');
  }

  Future<void> move(int from, int to) {
    throw UnimplementedError('[PlatformPlayer.move] is not implemented');
  }

  Future<void> seek(Duration duration) {
    throw UnimplementedError('[PlatformPlayer.seek] is not implemented');
  }

  Future<void> setPlaylistMode(PlaylistMode playlistMode) {
    throw UnimplementedError(
      '[PlatformPlayer.setPlaylistMode] is not implemented',
    );
  }

  Future<void> setVolume(double volume) {
    throw UnimplementedError('[PlatformPlayer.volume] is not implemented');
  }

  Future<void> setRate(double rate) {
    throw UnimplementedError('[PlatformPlayer.rate] is not implemented');
  }

  Future<void> setPitch(double pitch) {
    throw UnimplementedError('[PlatformPlayer.pitch] is not implemented');
  }

  Future<void> setShuffle(bool shuffle) {
    throw UnimplementedError('[PlatformPlayer.shuffle] is not implemented');
  }

  Future<void> setAudioDevice(AudioDevice audioDevice) {
    throw UnimplementedError(
      '[PlatformPlayer.setAudioDevice] is not implemented',
    );
  }

  Future<void> setVideoTrack(VideoTrack track) {
    throw UnimplementedError(
      '[PlatformPlayer.setVideoTrack] is not implemented',
    );
  }

  Future<void> setAudioTrack(AudioTrack track) {
    throw UnimplementedError(
      '[PlatformPlayer.setAudioTrack] is not implemented',
    );
  }

  Future<void> setSubtitleTrack(SubtitleTrack track) {
    throw UnimplementedError(
      '[PlatformPlayer.setSubtitleTrack] is not implemented',
    );
  }

  Future<Uint8List?> screenshot({
    ScreenshotFormat format = ScreenshotFormat.jpeg,
  }) async {
    throw UnimplementedError('[PlatformPlayer.screenshot] is not implemented');
  }

  int get handle {
    throw UnimplementedError('[PlatformPlayer.handle] is not implemented');
  }

  @protected
  final StreamController<Playlist> playlistController =
      StreamController<Playlist>.broadcast();

  @protected
  final StreamController<bool> playingController =
      StreamController<bool>.broadcast();

  @protected
  final StreamController<bool> completedController =
      StreamController<bool>.broadcast();

  @protected
  final StreamController<Duration> positionController =
      StreamController<Duration>.broadcast();

  @protected
  final StreamController<Duration> durationController =
      StreamController.broadcast();

  @protected
  final StreamController<bool> bufferingController =
      StreamController<bool>.broadcast();

  @protected
  final StreamController<Duration> bufferController =
      StreamController<Duration>.broadcast();

  @protected
  final StreamController<PlayerLog> logController =
      StreamController<PlayerLog>.broadcast();

  @protected
  final StreamController<String> errorController =
      StreamController<String>.broadcast();

  @protected
  final StreamController<AudioParams> audioParamsController =
      StreamController<AudioParams>.broadcast();

  @protected
  final StreamController<VideoParams> videoParamsController =
      StreamController<VideoParams>.broadcast();

  @protected
  final StreamController<Track> trackController =
      StreamController<Track>.broadcast();

  @protected
  final StreamController<Tracks> tracksController =
      StreamController<Tracks>.broadcast();

  @protected
  final StreamController<(int, int)> sizeController =
      StreamController<(int, int)>.broadcast();

  @protected
  final StreamController<Subtitle> subtitleController =
      StreamController<Subtitle>.broadcast();

  // --------------------------------------------------

  /// [Completer] to wait for initialization of this instance.
  final Completer<void> completer = Completer<void>();

  /// [Future<void>] to wait for initialization of this instance.
  Future<void> get waitForPlayerInitialization => completer.future;

  // --------------------------------------------------

  /// Publicly defined clean-up [Function]s which must be called before [dispose].
  final List<Future<void> Function()> release = [];
}

/// {@template player_configuration}
///
/// PlayerConfiguration
/// --------------------
/// Configurable options for customizing the [Player] behavior.
///
/// {@endtemplate}
class PlayerConfiguration {
  /// Sets the video output driver for native backend.
  ///
  /// Default: `null`.
  final String? vo;

  /// Enables on-screen controls for native backend.
  ///
  /// Default: `false`.
  final bool osc;

  /// Enables or disables pitch shift control for native backend.
  ///
  /// Enabling this option may result in de-syncing of audio & video.
  /// Thus, usage in audio only applications is recommended.
  /// This uses `scaletempo` under the hood & disables `audio-pitch-correction`.
  ///
  /// See: https://github.com/media-kit/media-kit/issues/45
  ///
  /// Default: `false`.
  final bool pitch;

  /// Sets the name of the underlying window & process for native backend.
  /// This is visible inside the Windows' volume mixer.
  ///
  /// Default: `null`.
  final String title;

  /// Optional callback invoked when the internals of the [Player] are initialized & ready for playback.
  ///
  /// Default: `null`.
  final void Function()? ready;

  /// Sets the log level on native backend.
  /// Default: `none`.
  final MPVLogLevel logLevel;

  /// Sets the demuxer cache size (in bytes) for native backend.
  ///
  /// Default: `32` MB or `32 * 1024 * 1024` bytes.
  final int bufferSize;

  /// Sets the list of allowed protocols for native backend.
  ///
  /// Default: `['file', 'tcp', 'tls', 'http', 'https', 'crypto', 'data']`.
  ///
  /// Learn more: https://ffmpeg.org/ffmpeg-protocols.html#Protocol-Options
  final List<String> protocolWhitelist;

  final Map<String, String>? options;

  /// {@macro player_configuration}
  const PlayerConfiguration({
    this.vo = 'null',
    this.osc = false,
    this.pitch = false,
    this.title = 'package:media_kit',
    this.ready,
    this.logLevel = MPVLogLevel.error,
    this.bufferSize = 32 * 1024 * 1024,
    this.protocolWhitelist = const [
      'udp',
      'rtp',
      'tcp',
      'tls',
      'data',
      'file',
      'http',
      'https',
      'crypto',
    ],
    this.options,
  });
}

/// {@template mpv_log_level}
///
/// MPVLogLevel
/// --------------------
/// Options to customise the [Player] native backend log level.
///
/// {@endtemplate}
enum MPVLogLevel {
  /// Disable absolutely all messages.
  /* none, */

  /// Critical/aborting errors.
  /* fatal, */

  // package:media_kit internally consumes logs of level error.

  /// Simple errors.
  error,

  /// Possible problems.
  warn,

  /// Informational message.
  info,

  /// Noisy informational message.
  v,

  /// Very noisy technical information.
  debug,

  /// Extremely noisy.
  trace,
}

enum ScreenshotFormat { none, jpeg, png }
