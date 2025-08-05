import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:in_app_picture_in_picture/in_app_picture_in_picture.dart';
import 'package:in_app_picture_in_picture/src/animated_play_pause.dart';
import 'package:in_app_picture_in_picture/src/center_play_button.dart';
import 'package:in_app_picture_in_picture/src/cupertino/cupertino_progress_bar.dart';
import 'package:in_app_picture_in_picture/src/helpers/utils.dart';
import 'package:in_app_picture_in_picture/src/notifiers/index.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

class CupertinoControls extends StatefulWidget {
  const CupertinoControls({
    required this.backgroundColor,
    required this.iconColor,
    this.showPlayButton = true,
    this.onClose,
    super.key,
  });

  final Color backgroundColor;
  final Color iconColor;
  final bool showPlayButton;
  final VoidCallback? onClose;

  @override
  State<StatefulWidget> createState() {
    return _CupertinoControlsState();
  }
}

class _CupertinoControlsState extends State<CupertinoControls>
    with SingleTickerProviderStateMixin {
  late PlayerNotifier notifier;
  late VideoPlayerValue _latestValue;
  Timer? _hideTimer;
  final marginSize = 5.0;
  Timer? _expandCollapseTimer;
  Timer? _initTimer;
  bool dragging = false;
  Timer? _bufferingDisplayTimer;
  bool _displayBufferingIndicator = false;
  double selectedSpeed = 1.0;
  late VideoPlayerController controller;

  // Custom blue color
  static const Color customBlue = Color(0xFF0B6FE4);

  // We know that _chewieController is set in didChangeDependencies
  ChewieController get chewieController => _chewieController!;
  ChewieController? _chewieController;

  @override
  void initState() {
    super.initState();
    notifier = Provider.of<PlayerNotifier>(context, listen: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_latestValue.hasError) {
      return chewieController.errorBuilder != null
          ? chewieController.errorBuilder!(
            context,
            chewieController.videoPlayerController.value.errorDescription!,
          )
          : const Center(
            child: Icon(
              CupertinoIcons.exclamationmark_circle,
              color: Colors.white,
              size: 42,
            ),
          );
    }

    final backgroundColor = widget.backgroundColor;
    final iconColor = widget.iconColor;
    final orientation = MediaQuery.of(context).orientation;
    final barHeight = orientation == Orientation.portrait ? 30.0 : 47.0;
    final buttonPadding = orientation == Orientation.portrait ? 16.0 : 24.0;

    return MouseRegion(
      onHover: (_) => _cancelAndRestartTimer(),
      child: GestureDetector(
        onTap: () => _cancelAndRestartTimer(),
        child: AbsorbPointer(
          absorbing: notifier.hideStuff,
          child: Stack(
            children: [
              if (_displayBufferingIndicator)
                _chewieController?.bufferingBuilder?.call(context) ??
                    const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation(customBlue),
                      ),
                    )
              else
                _buildHitArea(),

              SafeArea(
                child: Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildTopBar(
                    backgroundColor,
                    iconColor,
                    barHeight,
                    buttonPadding,
                  ),
                ),
              ),

              if (!chewieController.isFirstPlay)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _buildBottomBar(backgroundColor, iconColor, barHeight),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  void _dispose() {
    controller.removeListener(_updateState);
    _hideTimer?.cancel();
    _expandCollapseTimer?.cancel();
    _initTimer?.cancel();
  }

  @override
  void didChangeDependencies() {
    final oldController = _chewieController;
    _chewieController = ChewieController.of(context);
    controller = chewieController.videoPlayerController;

    if (oldController != chewieController) {
      _dispose();
      _initialize();
    }

    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(covariant CupertinoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  GestureDetector _buildCloseButton(
    VideoPlayerController controller,
    Color backgroundColor,
    Color iconColor,
    double barHeight,
    double buttonPadding,
  ) {
    final bool isFinished = _latestValue.position >= _latestValue.duration;
    return GestureDetector(
      onTap: widget.onClose,
      child: AnimatedOpacity(
        opacity:
            isFinished
                ? 1.0
                : notifier.hideStuff
                ? 0.0
                : 1.0,
        duration: const Duration(milliseconds: 300),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10.0),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10.0),
            child: Container(
              color: backgroundColor,
              child: Container(
                height: barHeight,
                padding: EdgeInsets.only(
                  left: buttonPadding,
                  right: buttonPadding,
                ),
                child: Icon(Icons.close, color: iconColor, size: 16),
              ),
            ),
          ),
        ),
      ),
    );
  }

  GestureDetector _buildExpandButton(
    Color backgroundColor,
    Color iconColor,
    double barHeight,
    double buttonPadding,
  ) {
    return GestureDetector(
      onTap: _onExpandCollapse,
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10.0),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10.0),
            child: Container(
              height: barHeight,
              padding: EdgeInsets.only(
                left: buttonPadding,
                right: buttonPadding,
              ),
              color: backgroundColor,
              child: Center(
                child: Icon(
                  chewieController.isFullScreen
                      ? CupertinoIcons.arrow_down_right_arrow_up_left
                      : CupertinoIcons.arrow_up_left_arrow_down_right,
                  color: iconColor,
                  size: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    Color backgroundColor,
    Color iconColor,
    double barHeight,
  ) {
    return AnimatedOpacity(
      opacity: notifier.hideStuff ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        color: Colors.transparent,
        alignment: Alignment.bottomCenter,
        margin: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 8.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10.0),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: Container(
              height: barHeight,
              color: backgroundColor,
              child:
                  chewieController.isLive
                      ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          _buildPlayPause(controller, iconColor, barHeight),
                          _buildLive(iconColor),
                        ],
                      )
                      : Row(
                        children: <Widget>[
                          _buildPlayPause(controller, iconColor, barHeight),
                          _buildProgressBar(),
                        ],
                      ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLive(Color iconColor) {
    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: Text('LIVE', style: TextStyle(color: iconColor, fontSize: 12.0)),
    );
  }

  Widget _buildHitArea() {
    final bool isFinished =
        (_latestValue.position >= _latestValue.duration) &&
        _latestValue.duration.inSeconds > 0;

    final bool showPlayButton =
        widget.showPlayButton && !_latestValue.isPlaying && !dragging;

    return AbsorbPointer(
      absorbing: chewieController.isFirstPlay && _latestValue.isPlaying,
      child: GestureDetector(
        onTap:
            _latestValue.isPlaying
                ? _chewieController?.pauseOnBackgroundTap ?? false
                    ? () {
                      _playPause();

                      setState(() {
                        notifier.hideStuff = true;
                      });
                    }
                    : _cancelAndRestartTimer
                : () {
                  _hideTimer?.cancel();

                  setState(() {
                    notifier.hideStuff = false;
                  });
                },
        child: Container(
          alignment: Alignment.center,
          color: Colors.transparent,
          child: CenterPlayButton(
            backgroundColor: widget.backgroundColor,
            iconColor: widget.iconColor,
            isFinished: isFinished,
            isPlaying: controller.value.isPlaying,
            show: showPlayButton,
            onPressed: _playPause,
          ),
        ),
      ),
    );
  }

  GestureDetector _buildPlayPause(
    VideoPlayerController controller,
    Color iconColor,
    double barHeight,
  ) {
    return GestureDetector(
      onTap: _playPause,
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.only(left: 6.0, right: 6.0),
        child: AnimatedPlayPause(
          color: widget.iconColor,
          playing: controller.value.isPlaying,
        ),
      ),
    );
  }

  Widget _buildTopBar(
    Color backgroundColor,
    Color iconColor,
    double barHeight,
    double buttonPadding,
  ) {
    return Container(
      // Consistent 8px margin regardless of fullscreen mode
      margin: const EdgeInsets.only(top: 8.0, left: 8.0, right: 8.0),
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: SizedBox(
          height: barHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              if (widget.onClose != null && !chewieController.isFirstPlay)
                _buildCloseButton(
                  controller,
                  backgroundColor,
                  iconColor,
                  barHeight,
                  buttonPadding,
                )
              else
                SizedBox(width: barHeight),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (chewieController.allowFullScreen &&
                      (!chewieController.fullScreenByDefault ||
                          (chewieController.fullScreenByDefault &&
                              !chewieController.isFirstPlay)))
                    _buildExpandButton(
                      backgroundColor,
                      iconColor,
                      barHeight,
                      buttonPadding,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _cancelAndRestartTimer() {
    _hideTimer?.cancel();

    setState(() {
      notifier.hideStuff = false;

      _startHideTimer();
    });
  }

  Future<void> _initialize() async {
    controller.addListener(_updateState);

    _updateState();

    if (controller.value.isPlaying || chewieController.autoPlay) {
      _startHideTimer();
    }

    if (chewieController.showControlsOnInitialize) {
      _initTimer = Timer(const Duration(milliseconds: 200), () {
        setState(() {
          notifier.hideStuff = false;
        });
      });
    }
  }

  void _onExpandCollapse() {
    setState(() {
      notifier.hideStuff = true;

      chewieController.toggleFullScreen();
      _expandCollapseTimer = Timer(const Duration(milliseconds: 300), () {
        setState(() {
          _cancelAndRestartTimer();
        });
      });
    });
  }

  Widget _buildProgressBar() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 12.0),
        child: CupertinoVideoProgressBar(
          controller,
          onDragStart: () {
            setState(() {
              dragging = true;
            });
            _hideTimer?.cancel();
          },
          onDragUpdate: () {
            _hideTimer?.cancel();
          },
          onDragEnd: () {
            setState(() {
              dragging = false;
            });
            _startHideTimer();
          },
          colors: ChewieProgressColors(
            playedColor: customBlue,
            handleColor: customBlue,
            bufferedColor: customBlue.withValues(alpha: 0.3),
            backgroundColor: Colors.white.withValues(alpha: 0.3),
          ),
          draggableProgressBar: false,
        ),
      ),
    );
  }

  void _playPause() {
    final isFinished =
        _latestValue.position >= _latestValue.duration &&
        _latestValue.duration.inSeconds > 0;

    setState(() {
      if (controller.value.isPlaying) {
        notifier.hideStuff = false;
        _hideTimer?.cancel();
        controller.pause();
      } else {
        _cancelAndRestartTimer();

        if (!controller.value.isInitialized) {
          controller.initialize().then((_) {
            controller.play();
          });
        } else {
          if (isFinished) {
            controller.seekTo(Duration.zero);
          }
          controller.play();
        }
      }
    });
  }

  void _startHideTimer() {
    final hideControlsTimer =
        chewieController.hideControlsTimer.isNegative
            ? ChewieController.defaultHideControlsTimer
            : chewieController.hideControlsTimer;
    _hideTimer = Timer(hideControlsTimer, () {
      setState(() {
        notifier.hideStuff = true;
      });
    });
  }

  void _bufferingTimerTimeout() {
    _displayBufferingIndicator = true;
    if (mounted) {
      setState(() {});
    }
  }

  void _updateState() {
    if (!mounted) return;

    final bool buffering = getIsBuffering(controller);

    if (chewieController.progressIndicatorDelay != null) {
      if (buffering) {
        _bufferingDisplayTimer ??= Timer(
          chewieController.progressIndicatorDelay!,
          _bufferingTimerTimeout,
        );
      } else {
        _bufferingDisplayTimer?.cancel();
        _bufferingDisplayTimer = null;
        _displayBufferingIndicator = false;
      }
    } else {
      _displayBufferingIndicator = buffering;
    }

    setState(() {
      _latestValue = controller.value;

      final isFinished = _latestValue.position >= _latestValue.duration;

      if (isFinished) {
        if (chewieController.isFirstPlay) {
          chewieController.isFirstPlay = false;
          if (chewieController.fullScreenByDefault &&
              chewieController.isFullScreen) {
            chewieController.exitFullScreen();
          }
        }
        notifier.hideStuffNoState(false);
      }
    });
  }
}
