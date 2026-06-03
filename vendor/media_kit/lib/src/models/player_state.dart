/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'package:media_kit/src/models/playable.dart';
import 'package:media_kit/src/models/subtitle.dart';
import 'package:media_kit/src/models/track.dart';
import 'package:media_kit/src/models/audio_params.dart';
import 'package:media_kit/src/models/video_params.dart';
import 'package:media_kit/src/models/playlist_mode.dart';

/// {@template player_state}
///
/// PlayerState
/// -----------
///
/// Instantaneous state of the [Player].
///
/// {@endtemplate}
class PlayerState {
  /// Currently opened [Media]s.
  Playlist playlist;

  /// Whether playing or not.
  bool playing;

  /// Whether end of currently playing [Media] has been reached.
  bool completed;

  /// Current playback position.
  Duration position;

  /// Current playback duration.
  Duration duration;

  /// Current volume.
  double volume;

  /// Current playback rate.
  double rate;

  /// Current pitch.
  double pitch;

  /// Whether buffering or not.
  bool buffering;

  /// Current buffer position.
  /// This indicates how much of the stream has been decoded & cached by the demuxer.
  Duration buffer;

  /// Current playlist mode.
  PlaylistMode playlistMode;

  /// Audio parameters of the currently playing [Media].
  /// e.g. sample rate, channels, etc.
  AudioParams audioParams;

  /// Video parameters of the currently playing [Media].
  /// e.g. width, height, rotation, etc.
  VideoParams videoParams;

  /// Currently selected video, audio & subtitle track.
  Track track;

  /// Currently available video, audio & subtitle tracks.
  Tracks tracks;

  /// Currently playing video's width.
  int width;

  /// Currently playing video's height.
  int height;

  /// Currently displayed subtitle.
  Subtitle subtitle;

  /// {@macro player_state}
  PlayerState({
    this.playlist = const Playlist([]),
    this.playing = false,
    this.completed = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 100.0,
    this.rate = 1.0,
    this.pitch = 1.0,
    this.buffering = false,
    this.buffer = Duration.zero,
    this.playlistMode = PlaylistMode.none,
    this.audioParams = const AudioParams(),
    this.videoParams = const VideoParams(),
    this.track = const Track(),
    this.tracks = const Tracks(),
    this.width = 0,
    this.height = 0,
    this.subtitle = const Subtitle.raw(),
  });

  // PlayerState copyWith({
  //   Playlist? playlist,
  //   bool? playing,
  //   bool? completed,
  //   Duration? position,
  //   Duration? duration,
  //   double? volume,
  //   double? rate,
  //   double? pitch,
  //   bool? buffering,
  //   Duration? buffer,
  //   PlaylistMode? playlistMode,
  //   AudioParams? audioParams,
  //   VideoParams? videoParams,
  //   double? audioBitrate,
  //   AudioDevice? audioDevice,
  //   List<AudioDevice>? audioDevices,
  //   Track? track,
  //   Tracks? tracks,
  //   int? width,
  //   int? height,
  //   Subtitle? subtitle,
  // }) {
  //   return PlayerState(
  //     playlist: playlist ?? this.playlist,
  //     playing: playing ?? this.playing,
  //     completed: completed ?? this.completed,
  //     position: position ?? this.position,
  //     duration: duration ?? this.duration,
  //     volume: volume ?? this.volume,
  //     rate: rate ?? this.rate,
  //     pitch: pitch ?? this.pitch,
  //     buffering: buffering ?? this.buffering,
  //     buffer: buffer ?? this.buffer,
  //     playlistMode: playlistMode ?? this.playlistMode,
  //     audioParams: audioParams ?? this.audioParams,
  //     videoParams: videoParams ?? this.videoParams,
  //     audioBitrate: audioBitrate ?? this.audioBitrate,
  //     audioDevice: audioDevice ?? this.audioDevice,
  //     audioDevices: audioDevices ?? this.audioDevices,
  //     track: track ?? this.track,
  //     tracks: tracks ?? this.tracks,
  //     width: width ?? this.width,
  //     height: height ?? this.height,
  //     subtitle: subtitle ?? this.subtitle,
  //   );
  // }

  @override
  String toString() => 'Player('
      'playlist: $playlist, '
      'playing: $playing, '
      'completed: $completed, '
      'position: $position, '
      'duration: $duration, '
      'volume: $volume, '
      'rate: $rate, '
      'pitch: $pitch, '
      'buffering: $buffering, '
      'buffer: $buffer, '
      'playlistMode: $playlistMode, '
      'audioParams: $audioParams, '
      'videoParams: $videoParams, '
      'track: $track, '
      'tracks: $tracks, '
      'width: $width, '
      'height: $height, '
      'subtitle: $subtitle'
      ')';
}
