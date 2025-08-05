import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:in_app_picture_in_picture/in_app_picture_in_picture.dart';
import 'package:in_app_picture_in_picture/src/animated_play_pause.dart';
import 'package:in_app_picture_in_picture/src/center_play_button.dart';
import 'package:in_app_picture_in_picture/src/cupertino/cupertino_progress_bar.dart';
import 'package:in_app_picture_in_picture/src/cupertino/widgets/cupertino_options_dialog.dart';
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
    this.onToggleFullscreen,
    this.isVideoSkippable = true,
    this.isForceFullscreen = false,
    super.key,
  });

  final Color backgroundColor;
  final Color iconColor;
  final bool showPlayButton;
  final VoidCallback? onClose;
  final void Function(bool isFullscreen)? onToggleFullscreen;
  final bool isVideoSkippable;
  final bool isForceFullscreen;

  @override
  State<StatefulWidget> createState() {
    return _CupertinoControlsState();
  }
}

class _CupertinoControlsState extends State<CupertinoControls>
    with SingleTickerProviderStateMixin {
  bool _isCustomFullScreen = false;
  late PlayerNotifier notifier;
  late VideoPlayerValue _latestValue;
  double? _latestVolume;
  Timer? _hideTimer;
  final marginSize = 5.0;
  Timer? _expandCollapseTimer;
  Timer? _initTimer;
  bool dragging = false;
  Duration? _subtitlesPosition;
  bool _subtitleOn = false;
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

  bool _shouldShowCloseButton() {
    if (widget.onClose == null) return false;
    return widget.isVideoSkippable || !chewieController.isFirstPlay;
  }

  bool _shouldShowFullscreenButton() {
    if (!chewieController.allowFullScreen) return false;
    return !widget.isForceFullscreen || !chewieController.isFirstPlay;
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

              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  const Spacer(),
                  if (_subtitleOn)
                    Transform.translate(
                      offset: Offset(
                        0.0,
                        notifier.hideStuff ? barHeight * 0.8 : 0.0,
                      ),
                      child: _buildSubtitles(chewieController.subtitle!),
                    ),
                  _buildBottomBar(backgroundColor, iconColor, barHeight),
                ],
              ),
              _buildTopBar(
                backgroundColor,
                iconColor,
                barHeight,
                buttonPadding,
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
    _chewieController?.removeListener(_onControllerChange);
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

  void _onControllerChange() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
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

  Widget _buildCloseButton(
    Color backgroundColor,
    Color iconColor,
    double barHeight,
    double buttonPadding,
  ) {
    if (widget.onClose == null) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8.0),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10.0),
        child: Container(
          color: backgroundColor.withOpacity(0.8),
          child: Container(
            height:
                barHeight * 0.8,
            padding: EdgeInsets.symmetric(horizontal: buttonPadding * 0.7),
            child: GestureDetector(
              onTap: widget.onClose,
              child: Icon(Icons.close, color: iconColor, size: 18),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandButton(
    Color backgroundColor,
    Color iconColor,
    double barHeight,
    double buttonPadding,
  ) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8.0),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10.0),
        child: Container(
          color: backgroundColor.withOpacity(0.8),
          child: Container(
            height:
                barHeight * 0.8,
            padding: EdgeInsets.symmetric(horizontal: buttonPadding * 0.7),
            child: GestureDetector(
              onTap: () {
                _onExpandCollapse();
              },
              child: Icon(
                _isCustomFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: iconColor,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }

  GestureDetector _buildOptionsButton(Color iconColor, double barHeight) {
    final options = <OptionItem>[];

    if (chewieController.additionalOptions != null &&
        chewieController.additionalOptions!(context).isNotEmpty) {
      options.addAll(chewieController.additionalOptions!(context));
    }

    return GestureDetector(
      onTap: () async {
        _hideTimer?.cancel();

        if (chewieController.optionsBuilder != null) {
          await chewieController.optionsBuilder!(context, options);
        } else {
          await showCupertinoModalPopup<OptionItem>(
            context: context,
            semanticsDismissible: true,
            useRootNavigator: chewieController.useRootNavigator,
            builder:
                (context) => CupertinoOptionsDialog(
                  options: options,
                  cancelButtonText:
                      chewieController.optionsTranslation?.cancelButtonText,
                ),
          );
          if (_latestValue.isPlaying) {
            _startHideTimer();
          }
        }
      },
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.only(left: 4.0, right: 8.0),
        margin: const EdgeInsets.only(right: 6.0),
        child: Icon(Icons.more_vert, color: iconColor, size: 18),
      ),
    );
  }

  Widget _buildSubtitles(Subtitles subtitles) {
    if (!_subtitleOn) {
      return const SizedBox();
    }
    if (_subtitlesPosition == null) {
      return const SizedBox();
    }
    final currentSubtitle = subtitles.getByPosition(_subtitlesPosition!);
    if (currentSubtitle.isEmpty) {
      return const SizedBox();
    }

    if (chewieController.subtitleBuilder != null) {
      return chewieController.subtitleBuilder!(
        context,
        currentSubtitle.first!.text,
      );
    }

    return Padding(
      padding: EdgeInsets.only(left: marginSize, right: marginSize),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: const Color(0x96000000),
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Text(
          currentSubtitle.first!.text.toString(),
          style: const TextStyle(fontSize: 18),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    Color backgroundColor,
    Color iconColor,
    double barHeight,
  ) {
    final bool isFinished = _latestValue.position >= _latestValue.duration;
    final bool shouldShowTimerAndBar =
        !chewieController.isLive && !chewieController.isFirstPlay;

    return SafeArea(
      bottom: chewieController.isFullScreen,
      minimum: chewieController.controlsSafeAreaMinimum,
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          color: Colors.transparent,
          alignment: Alignment.bottomCenter,
          margin: EdgeInsets.all(marginSize),
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
                            if (!chewieController.isFirstPlay || isFinished)
                              _buildPlayPause(controller, iconColor, barHeight),
                            _buildLive(iconColor),
                          ],
                        )
                        : shouldShowTimerAndBar || isFinished
                        ? Row(
                          children: <Widget>[
                            _buildPlayPause(controller, iconColor, barHeight),
                            _buildPosition(iconColor),
                            _buildProgressBar(),
                            _buildRemaining(iconColor),
                            if (chewieController.allowPlaybackSpeedChanging)
                              _buildSpeedButton(
                                controller,
                                iconColor,
                                barHeight,
                              ),
                            if (chewieController.additionalOptions != null &&
                                chewieController
                                    .additionalOptions!(context)
                                    .isNotEmpty)
                              _buildOptionsButton(iconColor, barHeight),
                          ],
                        )
                        : Container(),
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

    return GestureDetector(
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
    );
  }

  GestureDetector _buildMuteButton(
    VideoPlayerController controller,
    Color backgroundColor,
    Color iconColor,
    double barHeight,
    double buttonPadding,
  ) {
    return GestureDetector(
      onTap: () {
        _cancelAndRestartTimer();

        if (_latestValue.volume == 0) {
          controller.setVolume(_latestVolume ?? 0.5);
        } else {
          _latestVolume = controller.value.volume;
          controller.setVolume(0.0);
        }
      },
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10.0),
            child: ColoredBox(
              color: backgroundColor.withOpacity(0.8),
              child: Container(
                height: barHeight * 0.8, 
                padding: EdgeInsets.symmetric(horizontal: buttonPadding * 0.7),
                child: Icon(
                  _latestValue.volume > 0 ? Icons.volume_up : Icons.volume_off,
                  color: iconColor,
                  size: 18,
                ),
              ),
            ),
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

  Widget _buildPosition(Color iconColor) {
    final position = _latestValue.position;

    return Padding(
      padding: const EdgeInsets.only(right: 12.0),
      child: Text(
        formatDuration(position),
        style: TextStyle(color: iconColor, fontSize: 12.0),
      ),
    );
  }

  Widget _buildRemaining(Color iconColor) {
    final position = _latestValue.duration - _latestValue.position;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Text(
        '-${formatDuration(position)}',
        style: TextStyle(color: iconColor, fontSize: 12.0),
      ),
    );
  }

  // Widget _buildSubtitleToggle(Color iconColor, double barHeight) {
  //   //if don't have subtitle hiden button
  //   if (chewieController.subtitle?.isEmpty ?? true) {
  //     return const SizedBox();
  //   }
  //   return GestureDetector(
  //     onTap: _subtitleToggle,
  //     child: Container(
  //       height: barHeight,
  //       color: Colors.transparent,
  //       margin: const EdgeInsets.only(right: 10.0),
  //       padding: const EdgeInsets.only(left: 6.0, right: 6.0),
  //       child: Icon(
  //         Icons.subtitles,
  //         color: _subtitleOn ? iconColor : Colors.grey[700],
  //         size: 16.0,
  //       ),
  //     ),
  //   );
  // }

  // void _subtitleToggle() {
  //   setState(() {
  //     _subtitleOn = !_subtitleOn;
  //   });
  // }

  // GestureDetector _buildSkipBack(Color iconColor, double barHeight) {
  //   return GestureDetector(
  //     onTap: _skipBack,
  //     child: Container(
  //       height: barHeight,
  //       color: Colors.transparent,
  //       margin: const EdgeInsets.only(left: 10.0),
  //       padding: const EdgeInsets.only(left: 6.0, right: 6.0),
  //       child: Icon(CupertinoIcons.gobackward_15, color: iconColor, size: 18.0),
  //     ),
  //   );
  // }

  // GestureDetector _buildSkipForward(Color iconColor, double barHeight) {
  //   return GestureDetector(
  //     onTap: _skipForward,
  //     child: Container(
  //       height: barHeight,
  //       color: Colors.transparent,
  //       padding: const EdgeInsets.only(left: 6.0, right: 8.0),
  //       margin: const EdgeInsets.only(right: 8.0),
  //       child: Icon(CupertinoIcons.goforward_15, color: iconColor, size: 18.0),
  //     ),
  //   );
  // }

  GestureDetector _buildSpeedButton(
    VideoPlayerController controller,
    Color iconColor,
    double barHeight,
  ) {
    return GestureDetector(
      onTap: () async {
        _hideTimer?.cancel();

        final chosenSpeed = await showCupertinoModalPopup<double>(
          context: context,
          semanticsDismissible: true,
          useRootNavigator: chewieController.useRootNavigator,
          builder:
              (context) => _PlaybackSpeedDialog(
                speeds: chewieController.playbackSpeeds,
                selected: _latestValue.playbackSpeed,
              ),
        );

        if (chosenSpeed != null) {
          controller.setPlaybackSpeed(chosenSpeed);

          selectedSpeed = chosenSpeed;
        }

        if (_latestValue.isPlaying) {
          _startHideTimer();
        }
      },
      child: Container(
        height: barHeight,
        color: Colors.transparent,
        padding: const EdgeInsets.only(left: 6.0, right: 8.0),
        margin: const EdgeInsets.only(right: 8.0),
        child: Transform(
          alignment: Alignment.center,
          transform:
              Matrix4.skewY(0.0)
                ..rotateX(math.pi)
                ..rotateZ(math.pi * 0.8),
          child: Icon(Icons.speed, color: iconColor, size: 18.0),
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
    return Positioned(
      top: MediaQuery.of(context).padding.top,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          height: barHeight,
          margin: EdgeInsets.only(
            left: marginSize,
            right: marginSize,
            top: 4.0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              // Left side - Close button
              if (_shouldShowCloseButton())
                _buildCloseButton(
                  backgroundColor,
                  iconColor,
                  barHeight,
                  buttonPadding,
                )
              else
                SizedBox(width: barHeight),
              // Right side - Fullscreen and Mute buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_shouldShowFullscreenButton())
                    _buildExpandButton(
                      backgroundColor,
                      iconColor,
                      barHeight,
                      buttonPadding,
                    ),
                  const SizedBox(width: 8),
                  if (chewieController.allowMuting)
                    _buildMuteButton(
                      controller,
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
    _subtitleOn =
        chewieController.showSubtitles &&
        (chewieController.subtitle?.isNotEmpty ?? false);
    controller.addListener(_updateState);
    chewieController.addListener(_onControllerChange);

    chewieController.addListener(() {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
    });

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
    final newState = !_isCustomFullScreen;

    setState(() {
      notifier.hideStuff = true;
      _isCustomFullScreen = newState;
    });

    if (widget.onToggleFullscreen != null) {
      widget.onToggleFullscreen!(newState);
    } else {
      chewieController.toggleFullScreen();
    }

    _expandCollapseTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _cancelAndRestartTimer();
        });
      }
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
      _subtitlesPosition = controller.value.position;
    });
  }
}

class _PlaybackSpeedDialog extends StatelessWidget {
  const _PlaybackSpeedDialog({
    required List<double> speeds,
    required double selected,
  }) : _speeds = speeds,
       _selected = selected;

  final List<double> _speeds;
  final double _selected;

  @override
  Widget build(BuildContext context) {
    final selectedColor = CupertinoTheme.of(context).primaryColor;

    return CupertinoActionSheet(
      actions:
          _speeds
              .map(
                (e) => CupertinoActionSheetAction(
                  onPressed: () {
                    Navigator.of(context).pop(e);
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (e == _selected)
                        Icon(Icons.check, size: 20.0, color: selectedColor),
                      Text(e.toString()),
                    ],
                  ),
                ),
              )
              .toList(),
    );
  }
}
