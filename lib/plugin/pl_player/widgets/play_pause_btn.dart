import 'dart:async';

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:flutter/material.dart';

class PlayOrPauseButton extends StatefulWidget {
  final PlPlayerController plPlayerController;

  const PlayOrPauseButton({
    super.key,
    required this.plPlayerController,
  });

  @override
  PlayOrPauseButtonState createState() => PlayOrPauseButtonState();
}

class PlayOrPauseButtonState extends State<PlayOrPauseButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  late final StreamSubscription<PlayerStatus> subscription;

  PlPlayerController get _ctr => widget.plPlayerController;

  @override
  void initState() {
    super.initState();
    // Drive the icon from the controller's playerStatus so it works for both
    // the media_kit and the OHOS native backend.
    controller = AnimationController(
      vsync: this,
      value: _ctr.playerStatus.isPlaying ? 1 : 0,
      duration: const Duration(milliseconds: 200),
    );
    subscription = _ctr.playerStatus.listen((status) {
      if (status == PlayerStatus.playing) {
        controller.forward();
      } else {
        controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    subscription.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 34,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _ctr.onDoubleTapCenter,
        child: Center(
          child: AnimatedIcon(
            semanticLabel: _ctr.playerStatus.isPlaying ? '暂停' : '播放',
            progress: controller,
            icon: AnimatedIcons.play_pause,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
