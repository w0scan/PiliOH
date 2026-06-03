/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'package:media_kit/src/models/playable.dart';
import 'package:media_kit/src/models/subtitle.dart';
import 'package:media_kit/src/models/track.dart';
import 'package:media_kit/src/models/player_log.dart';
import 'package:media_kit/src/models/audio_params.dart';
import 'package:media_kit/src/models/video_params.dart';

/// {@template player_stream}
///
/// PlayerStream
/// ------------
///
/// Event [Stream]s for subscribing to [Player] events.
///
/// {@endtemplate}
class PlayerStream {
  /// Currently opened [Media]s.
  final Stream<Playlist> playlist;

  /// Whether playing or not.
  final Stream<bool> playing;

  /// Whether end of currently playing [Media] has been reached.
  final Stream<bool> completed;

  /// Current playback position.
  final Stream<Duration> position;

  /// Current playback duration.
  final Stream<Duration> duration;

  /// Whether buffering or not.
  final Stream<bool> buffering;

  /// Current buffer position.
  /// This indicates how much of the stream has been decoded & cached by the demuxer.
  final Stream<Duration> buffer;

  /// Audio parameters of the currently playing [Media].
  /// e.g. sample rate, channels, etc.
  final Stream<AudioParams> audioParams;

  /// Video parameters of the currently playing [Media].
  /// e.g. width, height, rotation etc.
  final Stream<VideoParams> videoParams;

  /// Currently selected video, audio and subtitle track.
  final Stream<Track> track;

  /// Currently available video, audio and subtitle tracks.
  final Stream<Tracks> tracks;

  /// Currently playing video's size.
  final Stream<(int, int)> size;

  /// Currently displayed subtitle.
  final Stream<Subtitle> subtitle;

  /// [Stream] emitting internal logs.
  final Stream<PlayerLog> log;

  /// [Stream] emitting error messages. This may be used to handle & display errors to the user.
  final Stream<String> error;

  /// {@macro player_stream}
  const PlayerStream(
    this.playlist,
    this.playing,
    this.completed,
    this.position,
    this.duration,
    this.buffering,
    this.buffer,
    this.audioParams,
    this.videoParams,
    this.track,
    this.tracks,
    this.size,
    this.subtitle,
    this.log,
    this.error,
  );
}
