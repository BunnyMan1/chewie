import 'package:flutter/material.dart';
import 'package:in_app_picture_in_picture/in_app_picture_in_picture.dart';
import 'package:in_app_picture_in_picture/src/helpers/adaptive_controls.dart';
import 'package:in_app_picture_in_picture/src/notifiers/index.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

class PlayerWithControls extends StatelessWidget {
  const PlayerWithControls({super.key});

  @override
  Widget build(BuildContext context) {
    final ChewieController chewieController = ChewieController.of(context);

    double calculateAspectRatio(BuildContext context) {
      final size = MediaQuery.of(context).size;
      final width = size.width;
      final height = size.height;

      return width > height ? width / height : height / width;
    }

    Widget buildControls(
      BuildContext context,
      ChewieController chewieController,
    ) {
      return chewieController.showControls
          ? chewieController.customControls ??
              AdaptiveControls(onClose: chewieController.onCloseCallback)
          : const SizedBox();
    }

    Widget buildPlayerWithControls(
      ChewieController chewieController,
      BuildContext context,
    ) {
      final playerNotifier = context.read<PlayerNotifier>();
      final child = Stack(
        children: [
          if (chewieController.placeholder != null)
            chewieController.placeholder!,
          Center(
            child: AspectRatio(
              aspectRatio:
                  chewieController.aspectRatio ??
                  chewieController.videoPlayerController.value.aspectRatio,
              child: VideoPlayer(chewieController.videoPlayerController),
            ),
          ),
          if (chewieController.overlay != null) chewieController.overlay!,
          if (Theme.of(context).platform != TargetPlatform.iOS)
            Consumer<PlayerNotifier>(
              builder:
                  (
                    BuildContext context,
                    PlayerNotifier notifier,
                    Widget? widget,
                  ) => AnimatedOpacity(
                      opacity: notifier.hideStuff ? 0.0 : 0.8,
                      duration: const Duration(milliseconds: 250),
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.black54),
                        child: Container(),
                      ),
                    ),
            ),
          if (!chewieController.isFullScreen)
            buildControls(context, chewieController)
          else
            SafeArea(
              bottom: false,
              top: false,
              child: buildControls(context, chewieController),
            ),
        ],
      );

      if (chewieController.zoomAndPan ||
          chewieController.transformationController != null) {
        return InteractiveViewer(
          transformationController: chewieController.transformationController,
          maxScale: chewieController.maxScale,
          panEnabled: chewieController.zoomAndPan,
          onInteractionEnd:
              chewieController.zoomAndPan
                  ? (_) => playerNotifier.hideStuff = false
                  : null,
          child: child,
        );
      }

      return child;
    }

    return Center(
      child: SizedBox(
        height: MediaQuery.of(context).size.height,
        width: MediaQuery.of(context).size.width,
        child: AspectRatio(
          aspectRatio: calculateAspectRatio(context),
          child: buildPlayerWithControls(chewieController, context),
        ),
      ),
    );
  }
}