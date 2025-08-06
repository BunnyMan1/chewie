import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_picture_in_picture/in_app_picture_in_picture.dart';
import 'package:in_app_picture_in_picture/src/center_play_button.dart';
import 'package:in_app_picture_in_picture/src/helpers/utils.dart';
import 'package:in_app_picture_in_picture/src/notifiers/index.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

class MaterialControls extends StatefulWidget {
  const MaterialControls({this.showPlayButton = true, this.onClose, super.key});

  final bool showPlayButton;
  final VoidCallback? onClose;

  @override
  State<StatefulWidget> createState() {
    return _MaterialControlsState();
  }
}

class _MaterialControlsState extends State<MaterialControls>
    with SingleTickerProviderStateMixin {
  late PlayerNotifier notifier;
  late VideoPlayerValue _latestValue;
  Timer? _hideTimer;
  Timer? _initTimer;
  late var _subtitlesPosition = const Duration();
  bool _subtitleOn = false;
  Timer? _showAfterExpandCollapseTimer;
  bool _dragging = false;
  bool _displayTapped = false;
  Timer? _bufferingDisplayTimer;
  bool _displayBufferingIndicator = false;

  final barHeight = 48.0 * 1.5;
  final marginSize = 5.0;

  // Custom blue color
  static const Color customBlue = Color(0xFF0B6FE4);

  late VideoPlayerController controller;
  ChewieController? _chewieController;

  // We know that _chewieController is set in didChangeDependencies
  ChewieController get chewieController => _chewieController!;

  @override
  void initState() {
    super.initState();
    notifier = Provider.of<PlayerNotifier>(context, listen: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_latestValue.hasError) {
      return chewieController.errorBuilder?.call(
            context,
            chewieController.videoPlayerController.value.errorDescription!,
          ) ??
          const Center(child: Icon(Icons.error, color: Colors.white, size: 42));
    }

    return MouseRegion(
      onHover: (_) {
        _cancelAndRestartTimer();
      },
      child: GestureDetector(
        onTap: () => _cancelAndRestartTimer(),
        child: AbsorbPointer(
          absorbing: notifier.hideStuff,
          child: Stack(
            children: [
              if (_displayBufferingIndicator || _latestValue.isBuffering)
                Center(
                  child: _buildIconbutton(
                    onTap: () {},
                    icon: null,
                    alwayShow: true,
                    iconWidget: const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(customBlue),
                    ),
                  ),
                )
              else
                _buildHitArea(),
              Column(
                children: [
                  _buildTopBar(),
                  const Spacer(),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      // if (_subtitleOn)
                      //   Transform.translate(
                      //     offset: Offset(0.0, notifier.hideStuff ? barHeight * 0.8 : 0.0),
                      //     child: _buildSubtitles(context, chewieController.subtitle!),
                      //   ),
                      _buildBottomBar(context),
                    ],
                  ),
                ],
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
    _initTimer?.cancel();
    _showAfterExpandCollapseTimer?.cancel();
    _bufferingDisplayTimer?.cancel();
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

  // Ensure UI updates when fullscreen state changes
  @override
  void didUpdateWidget(covariant MaterialControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Ensure UI updates when fullscreen state changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Widget _buildTopBar() {
    final isFinished = _latestValue.position >= _latestValue.duration;
    final showFullscreen =
        chewieController.allowFullScreen &&
        (!chewieController.fullScreenByDefault ||
            (chewieController.fullScreenByDefault &&
                !chewieController.isFirstPlay)) &&
        !isFinished;
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, left: 8.0, right: 8.0),
      child: Row(
        children: [
          if (widget.onClose != null && !chewieController.isFirstPlay)
            _buildIconbutton(
              onTap: closePlayer,
              showWhenFinshedPlayingVideo: true,
              icon: Icons.close,
              padding: const EdgeInsets.all(3),
              constraints: const BoxConstraints(maxHeight: 30, maxWidth: 30),
              iconSize: 20,
            ),
          if (showFullscreen) const Spacer(),
          if (showFullscreen)
            _buildIconbutton(
              padding: const EdgeInsets.all(3),
              constraints: const BoxConstraints(maxHeight: 30, maxWidth: 30),
              iconSize: 20,
              icon:
                  chewieController.isFullScreen
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
              onTap: () {
                chewieController.isFullScreen
                    ? chewieController.exitFullScreen()
                    : chewieController.enterFullScreen();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildIconbutton({
    required VoidCallback onTap,
    required IconData? icon,
    bool showWhenFinshedPlayingVideo = false,
    double iconSize = 32.0,
    EdgeInsetsGeometry padding = const EdgeInsets.all(8.0),
    bool alwayShow = false,
    Widget? iconWidget,
    BoxConstraints? constraints,
  }) {
    final isFinished = _latestValue.position >= _latestValue.duration;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: AnimatedOpacity(
            opacity:
                alwayShow
                    ? 1
                    : showWhenFinshedPlayingVideo && isFinished
                    ? 1.0
                    : !_dragging && !notifier.hideStuff
                    ? 1.0
                    : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: padding,
                // Always set the iconSize on the IconButton, not on the Icon itself:
                // https://github.com/flutter/flutter/issues/52980
                child:
                    iconWidget ??
                    IconButton(
                      constraints: constraints,
                      iconSize: iconSize,
                      padding: EdgeInsets.zero,
                      icon: Icon(icon, color: Colors.white),
                      onPressed: onTap,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  AnimatedOpacity _buildBottomBar(BuildContext context) {
    final isFinished = _latestValue.position >= _latestValue.duration;

    return AnimatedOpacity(
      opacity: notifier.hideStuff ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        height: barHeight + (chewieController.isFullScreen ? 10.0 : 0),
        padding: EdgeInsets.only(
          left: 20,
          bottom: !chewieController.isFullScreen ? 10.0 : 0,
        ),
        child: SafeArea(
          bottom: chewieController.isFullScreen,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!isFinished)
                SizedBox(height: chewieController.isFullScreen ? 15.0 : 8),
              if (!chewieController.isLive && !chewieController.isFirstPlay)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.only(right: 12),
                    child: Row(children: [_buildProgressBar()]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHitArea() {
    final bool isFinished = _latestValue.position >= _latestValue.duration;

    return Padding(
      padding: const EdgeInsets.only(top: 12.0, bottom: 60),
      child: Column(
        children: [
          if (!chewieController.isFirstPlay || isFinished)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_latestValue.isPlaying) {
                    if (_displayTapped) {
                      notifier.hideStuff = true;
                    } else {
                      _cancelAndRestartTimer();
                    }
                  } else {
                    _playPause();
                    notifier.hideStuff = true;
                  }
                },
                child: CenterPlayButton(
                  backgroundColor: Colors.black54,
                  iconColor: Colors.white,
                  isFinished: isFinished,
                  isPlaying: controller.value.isPlaying,
                  show: !_dragging && !notifier.hideStuff,
                  onPressed: _playPause,
                ),
              ),
            )
          else
            const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSubtitles(BuildContext context, Subtitles subtitles) {
    if (!_subtitleOn) {
      return Container();
    }
    final currentSubtitle = subtitles.getByPosition(_subtitlesPosition);
    if (currentSubtitle.isEmpty) {
      return Container();
    }

    if (chewieController.subtitleBuilder != null) {
      return chewieController.subtitleBuilder!(
        context,
        currentSubtitle.first!.text,
      );
    }

    return Padding(
      padding: EdgeInsets.all(marginSize),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: const Color(0x96000000),
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Text(
          currentSubtitle.first!.text as String,
          style: const TextStyle(fontSize: 18),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  void closePlayer() {
    widget.onClose!();
  }

  void _cancelAndRestartTimer() {
    _hideTimer?.cancel();
    _startHideTimer();

    setState(() {
      notifier.hideStuff = false;
      _displayTapped = true;
    });
  }

  Future<void> _initialize() async {
    _subtitleOn = chewieController.subtitle?.isNotEmpty ?? false;
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

  void _playPause() {
    final isFinished = _latestValue.position >= _latestValue.duration;

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
            controller.seekTo(const Duration());
          }
          controller.play();
        }
      }
    });
  }

  void _startHideTimer() {
    _hideTimer = Timer(const Duration(seconds: 3), () {
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

    // display the progress bar indicator only after the buffering delay if it has been set
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

  Widget _buildProgressBar() {
    final bool isFinished = _latestValue.position >= _latestValue.duration;
    if (isFinished) {
      return Container();
    } else {
      return Expanded(
        child: MaterialVideoProgressBar(
          controller,
          onDragStart: () {
            setState(() {
              _dragging = true;
            });

            _hideTimer?.cancel();
          },
          onDragEnd: () {
            setState(() {
              _dragging = false;
            });

            _startHideTimer();
          },
          colors:
              chewieController.materialProgressColors ??
              ChewieProgressColors(
                playedColor: customBlue,
                handleColor: customBlue,
                bufferedColor: customBlue.withValues(alpha: 0.3),
                backgroundColor: Colors.white.withValues(alpha: 0.3),
              ),
        ),
      );
    }
  }
}
