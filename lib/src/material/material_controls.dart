import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../src/center_play_button.dart';
import '../../src/chewie_player.dart';
import '../../src/chewie_progress_colors.dart';
import '../../src/material/material_progress_bar.dart';
import '../../src/notifiers/index.dart';

class MaterialControls extends StatefulWidget {
  const MaterialControls({super.key, this.onClose, this.showPlayButton = true});

  final VoidCallback? onClose;
  final bool showPlayButton;

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
  Timer? _showAfterExpandCollapseTimer;
  bool _dragging = false;
  bool _displayTapped = false;
  bool _fullscreenIconState = false;

  // final originalBarHeight = 48.0 * 1.25;
  final barHeight = 48.0 * 1.5;
  final marginSize = 5.0;

  late VideoPlayerController controller;
  ChewieController? _chewieController;
  // We know that _chewieController is set in didChangeDependencies
  ChewieController get chewieController => _chewieController!;

  @override
  void initState() {
    super.initState();
    // print("Init stateeeeee");
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

    return GestureDetector(
      onTap: () => _cancelAndRestartTimer(),
      child: AbsorbPointer(
        absorbing: notifier.hideStuff,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Buffering spinner or play/pause hit area — always centered
            if (_latestValue.isBuffering)
              Center(
                child: _buildIconbutton(
                  onTap: () {},
                  icon: null,
                  alwayShow: true,
                  iconWidget: const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
              )
            else
              _buildHitArea(),
            // Bottom progress bar
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomBar(context),
            ),
            // Top-right: fullscreen button
            _buildTopRightButtons(),
            // Top-left: close button
            _buildTopLeftButtons(),
          ],
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

  /// Close button — top-left, animated
  Widget _buildTopLeftButtons() {
    if (widget.onClose == null || chewieController.isFirstPlay) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: 8,
      left: 8,
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: _buildRawIconButton(
          onTap: closePlayer,
          icon: Icons.close,
          iconSize: 24,
          padding: const EdgeInsets.all(4),
        ),
      ),
    );
  }

  /// Fullscreen toggle button — top-right, animated
  Widget _buildTopRightButtons() {
    final isFinished =
        _latestValue.duration > Duration.zero &&
        _latestValue.position >= _latestValue.duration;
    final showFullscreen =
        chewieController.allowFullScreen &&
        (!chewieController.fullScreenByDefault ||
            (chewieController.fullScreenByDefault &&
                !chewieController.isFirstPlay)) &&
        !isFinished;

    if (!showFullscreen) return const SizedBox.shrink();

    return Positioned(
      top: 8,
      right: 8,
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: _buildRawIconButton(
          onTap: _onFullScreenToggle,
          icon: _fullscreenIconState
              ? Icons.fullscreen_exit_rounded
              : Icons.fullscreen_rounded,
          iconSize: 24,
          padding: const EdgeInsets.all(4),
        ),
      ),
    );
  }

  /// Handles fullscreen toggle: uses the app-provided callback if available
  /// (prevents chewie from pushing its own route which conflicts with the
  /// app's custom animation-based fullscreen system).
  void _onFullScreenToggle() {
    final externalToggle = chewieController.onExternalFullScreenToggle;
    if (externalToggle != null) {
      final entering = !chewieController.isFullScreen;
      if (entering) {
        chewieController.enterFullScreen(notify: false);
      } else {
        chewieController.exitFullScreen(notify: false);
      }
      externalToggle(entering);
      _fullscreenIconState = entering;
      if (mounted) setState(() {});
    } else {
      chewieController.isFullScreen
          ? chewieController.exitFullScreen()
          : chewieController.enterFullScreen();
      _fullscreenIconState = chewieController.isFullScreen;
      if (mounted) setState(() {});
    }
  }

  Widget _buildRawIconButton({
    required VoidCallback onTap,
    required IconData icon,
    double iconSize = 32.0,
    EdgeInsetsGeometry padding = const EdgeInsets.all(8.0),
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: padding,
        child: IconButton(
          iconSize: iconSize,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(icon, color: Colors.white),
          onPressed: onTap,
        ),
      ),
    );
  }

  // Widget _buildOptionsButton() {
  //   final options = <OptionItem>[
  //     OptionItem(
  //       onTap: () async {
  //         Navigator.pop(context);
  //         _onSpeedButtonTap();
  //       },
  //       iconData: Icons.speed,
  //       title: chewieController.optionsTranslation?.playbackSpeedButtonText ?? 'Playback speed',
  //     )
  //   ];

  //   if (chewieController.subtitle != null && chewieController.subtitle!.isNotEmpty) {
  //     options.add(
  //       OptionItem(
  //         onTap: () {
  //           _onSubtitleTap();
  //           Navigator.pop(context);
  //         },
  //         iconData: _subtitleOn ? Icons.closed_caption : Icons.closed_caption_off_outlined,
  //         title: chewieController.optionsTranslation?.subtitlesButtonText ?? 'Subtitles',
  //       ),
  //     );
  //   }

  //   if (chewieController.additionalOptions != null &&
  //       chewieController.additionalOptions!(context).isNotEmpty) {
  //     options.addAll(chewieController.additionalOptions!(context));
  //   }

  //   return AnimatedOpacity(
  //     opacity: notifier.hideStuff ? 0.0 : 1.0,
  //     duration: const Duration(milliseconds: 250),
  //     child: IconButton(
  //       onPressed: () async {
  //         _hideTimer?.cancel();

  //         if (chewieController.optionsBuilder != null) {
  //           await chewieController.optionsBuilder!(context, options);
  //         } else {
  //           await showModalBottomSheet<OptionItem>(
  //             context: context,
  //             isScrollControlled: true,
  //             useRootNavigator: true,
  //             builder: (context) => OptionsDialog(
  //               options: options,
  //               cancelButtonText: chewieController.optionsTranslation?.cancelButtonText,
  //             ),
  //           );
  //         }

  //         if (_latestValue.isPlaying) {
  //           _startHideTimer();
  //         }
  //       },
  //       icon: const Icon(
  //         Icons.more_vert,
  //         color: Colors.white,
  //       ),
  //     ),
  //   );
  // }

  AnimatedOpacity _buildBottomBar(BuildContext context) {
    final bool isFinished =
        _latestValue.duration > Duration.zero &&
        _latestValue.position >= _latestValue.duration;

    return AnimatedOpacity(
      opacity: notifier.hideStuff ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        height: barHeight + (chewieController.isFullScreen ? 10.0 : 0),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: !chewieController.isFullScreen ? 10.0 : 0,
        ),
        child: SafeArea(
          top: false,
          bottom: chewieController.isFullScreen,
          minimum: chewieController.controlsSafeAreaMinimum,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Flexible(
              //   child: Row(
              //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
              //     children: <Widget>[
              //       if (chewieController.isLive) const Expanded(child: Text('LIVE'))
              //       // else
              //       // const Spacer(),
              //       // _buildPosition(iconColor),
              //       // _buildExpandButton(),
              //     ],
              //   ),
              // ),
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
    final isFinished =
        _latestValue.duration > Duration.zero &&
        _latestValue.position >= _latestValue.duration;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: AnimatedOpacity(
            opacity: alwayShow
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
                      icon: Icon(
                        icon,
                        // size: iconSize,
                        color: Colors.white,
                      ),
                      onPressed: onTap,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHitArea() {
    final bool isFinished =
        _latestValue.duration > Duration.zero &&
        _latestValue.position >= _latestValue.duration;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_latestValue.isPlaying) {
          if (_displayTapped) {
            // setState(() {
            notifier.hideStuff = true;
            // });
          } else {
            _cancelAndRestartTimer();
          }
        } else {
          _playPause();
          // setState(() {
          notifier.hideStuff = true;
          // });
        }
      },
      child: Center(
        child: CenterPlayButton(
          backgroundColor: Colors.black54,
          iconColor: Colors.white,
          isFinished: isFinished,
          isPlaying: controller.value.isPlaying,
          show: !_dragging && !notifier.hideStuff,
          onPressed: _playPause,
        ),
      ),
    );
  }

  // Widget _buildPosition(Color? iconColor) {
  //   final position = _latestValue.position;
  //   final duration = _latestValue.duration;

  //   return RichText(
  //     text: TextSpan(
  //       text: '${formatDuration(position)} ',
  //       children: <InlineSpan>[
  //         TextSpan(
  //           text: '/ ${formatDuration(duration)}',
  //           style: TextStyle(
  //             fontSize: 14.0,
  //             color: Colors.white.withOpacity(.75),
  //             fontWeight: FontWeight.normal,
  //           ),
  //         )
  //       ],
  //       style: const TextStyle(
  //         fontSize: 14.0,
  //         color: Colors.white,
  //         fontWeight: FontWeight.bold,
  //       ),
  //     ),
  //   );
  // }

  void closePlayer() {
    widget.onClose!();
  }

  // void _onSubtitleTap() {
  //   setState(() {
  //     _subtitleOn = !_subtitleOn;
  //   });
  // }

  void _cancelAndRestartTimer() {
    _hideTimer?.cancel();
    _startHideTimer();

    setState(() {
      notifier.hideStuff = false;
      _displayTapped = true;
    });
  }

  Future<void> _initialize() async {
    _fullscreenIconState = chewieController.isFullScreen;
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
    final bool isFinished =
        (_latestValue.position >= _latestValue.duration) &&
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
    _hideTimer = Timer(const Duration(seconds: 3), () {
      setState(() {
        notifier.hideStuff = true;
      });
    });
  }

  void _updateState() {
    if (!mounted) return;
    setState(() {
      _fullscreenIconState = chewieController.isFullScreen;
      _latestValue = controller.value;
      final isFinished =
          _latestValue.duration > Duration.zero &&
          _latestValue.position >= _latestValue.duration;

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
    final bool isFinished =
        _latestValue.duration > Duration.zero &&
        _latestValue.position >= _latestValue.duration;
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
          onDragUpdate: () {
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
                playedColor: Theme.of(context).colorScheme.secondary,
                handleColor: Theme.of(context).colorScheme.secondary,
                bufferedColor: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.5),
                backgroundColor: Theme.of(
                  context,
                ).disabledColor.withValues(alpha: .5),
              ),
          draggableProgressBar: chewieController.draggableProgressBar,
        ),
      );
    }
  }
}
