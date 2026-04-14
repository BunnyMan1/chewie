import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../src/chewie_progress_colors.dart';
import '../src/models/subtitle_model.dart';
import '../src/notifiers/player_notifier.dart';
import '../src/player_with_controls.dart';
import '../src/models/option_item.dart';
import '../src/models/options_translation.dart';

typedef ChewieRoutePageBuilder =
    Widget Function(
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      ChewieControllerProvider controllerProvider,
    );

/// A Video Player with Material and Cupertino skins.
class Chewie extends StatefulWidget {
  const Chewie({
    super.key,
    required this.controller,
    required this.onToggleFullscreen,
  });

  /// The [ChewieController]
  final ChewieController controller;

  final void Function(bool newState) onToggleFullscreen;

  @override
  ChewieState createState() {
    return ChewieState();
  }
}

class ChewieState extends State<Chewie> {
  bool _isFullScreen = false;
  bool _wasPlayingBeforeFullScreen = false;
  bool _resumeAppliedInFullScreen = false;

  bool get isControllerFullScreen => widget.controller.isFullScreen;
  late PlayerNotifier notifier;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(listener);
    notifier = PlayerNotifier.init();
  }

  @override
  void dispose() {
    widget.controller.removeListener(listener);
    notifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(Chewie oldWidget) {
    if (oldWidget.controller != widget.controller) {
      widget.controller.addListener(listener);
    }
    super.didUpdateWidget(oldWidget);
    if (_isFullScreen != isControllerFullScreen) {
      widget.controller._isFullScreen = _isFullScreen;
    }
  }

  Future<void> listener() async {
    if (widget.controller.isFullScreen && !_isFullScreen) {
      _isFullScreen = true;
      _wasPlayingBeforeFullScreen =
          widget.controller.videoPlayerController.value.isPlaying;
      _resumeAppliedInFullScreen = false;
      await _pushFullScreenWidget(context);
    } else if (_isFullScreen && !widget.controller.isFullScreen) {
      Navigator.of(
        context,
        rootNavigator: widget.controller.useRootNavigator,
      ).pop();
      _isFullScreen = false;
    }
    widget.onToggleFullscreen(_isFullScreen);
  }

  @override
  Widget build(BuildContext context) {
    return ChewieControllerProvider(
      controller: widget.controller,
      child: ChangeNotifierProvider<PlayerNotifier>.value(
        value: notifier,
        builder: (context, w) => const PlayerWithControls(),
      ),
    );
  }

  Widget _buildFullScreenVideo(
    BuildContext context,
    Animation<double> animation,
    ChewieControllerProvider controllerProvider,
  ) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        alignment: Alignment.center,
        color: Colors.black,
        child: controllerProvider,
      ),
    );
  }

  AnimatedWidget _defaultRoutePageBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    ChewieControllerProvider controllerProvider,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        return _buildFullScreenVideo(context, animation, controllerProvider);
      },
    );
  }

  Widget _fullScreenRoutePageBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final controllerProvider = ChewieControllerProvider(
      controller: widget.controller,
      child: ChangeNotifierProvider<PlayerNotifier>.value(
        value: notifier,
        builder: (context, w) => const PlayerWithControls(),
      ),
    );

    if (kIsWeb && !_resumeAppliedInFullScreen) {
      _resumeAppliedInFullScreen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final vpc = widget.controller.videoPlayerController;
        await vpc.pause();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (_wasPlayingBeforeFullScreen) {
          await vpc.play();
        } else {
          await vpc.play();
          await vpc.pause();
        }
      });
    }

    if (widget.controller.routePageBuilder == null) {
      return _defaultRoutePageBuilder(
        context,
        animation,
        secondaryAnimation,
        controllerProvider,
      );
    }
    return widget.controller.routePageBuilder!(
      context,
      animation,
      secondaryAnimation,
      controllerProvider,
    );
  }

  Future<dynamic> _pushFullScreenWidget(BuildContext context) async {
    final TransitionRoute<void> route = PageRouteBuilder<void>(
      pageBuilder: _fullScreenRoutePageBuilder,
    );

    onEnterFullScreen();

    if (!widget.controller.allowedScreenSleep) {
      WakelockPlus.enable();
    }

    await Navigator.of(
      context,
      rootNavigator: widget.controller.useRootNavigator,
    ).push(route);

    final wasPlaying = widget.controller.videoPlayerController.value.isPlaying;

    if (kIsWeb) {
      await _reInitializeControllers(wasPlaying);
    }

    _isFullScreen = false;
    widget.controller.exitFullScreen();

    if (!widget.controller.allowedScreenSleep) {
      WakelockPlus.disable();
    }

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: widget.controller.systemOverlaysAfterFullScreen,
    );
    SystemChrome.setPreferredOrientations(
      widget.controller.deviceOrientationsAfterFullScreen,
    );
  }

  void onEnterFullScreen() {
    final videoWidth = widget.controller.videoPlayerController.value.size.width;
    final videoHeight =
        widget.controller.videoPlayerController.value.size.height;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);

    // if (widget.controller.systemOverlaysOnEnterFullScreen != null) {
    //   /// Optional user preferred settings
    //   SystemChrome.setEnabledSystemUIMode(
    //     SystemUiMode.manual,
    //     overlays: widget.controller.systemOverlaysOnEnterFullScreen,
    //   );
    // } else {
    //   /// Default behavior
    //   SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    // }

    if (widget.controller.deviceOrientationsOnEnterFullScreen != null) {
      /// Optional user preferred settings
      SystemChrome.setPreferredOrientations(
        widget.controller.deviceOrientationsOnEnterFullScreen!,
      );
    } else {
      final isLandscapeVideo = videoWidth > videoHeight;
      final isPortraitVideo = videoWidth < videoHeight;

      /// Default behavior
      /// Video w > h means we force landscape
      if (isLandscapeVideo) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
      /// Video h > w means we force portrait
      else if (isPortraitVideo) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
      /// Otherwise if h == w (square video)
      else {
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      }
    }
  }

  Future<void> _reInitializeControllers(bool wasPlaying) async {
    final prevPosition = widget.controller.videoPlayerController.value.position;

    await widget.controller.videoPlayerController.initialize();
    widget.controller._initialize();
    await widget.controller.videoPlayerController.seekTo(prevPosition);

    if (wasPlaying) {
      await widget.controller.videoPlayerController.play();
    } else {
      await widget.controller.videoPlayerController.play();
      await widget.controller.videoPlayerController.pause();
    }
  }
}

class ChewieController extends ChangeNotifier {
  ChewieController({
    required this.videoPlayerController,
    this.optionsTranslation,
    this.aspectRatio,
    this.isFirstPlay = false,
    this.onCloseCallback,
    this.onInitialPlayCompletedCallBack,
    this.autoInitialize = false,
    this.autoPlay = false,
    this.draggableProgressBar = true,
    this.startAt,
    this.looping = false,
    this.fullScreenByDefault = false,
    this.cupertinoProgressColors,
    this.materialProgressColors,
    this.materialSeekButtonFadeDuration = const Duration(milliseconds: 300),
    this.materialSeekButtonSize = 26,
    this.placeholder,
    this.overlay,
    this.showControlsOnInitialize = true,
    this.showOptions = true,
    this.optionsBuilder,
    this.additionalOptions,
    this.showControls = true,
    this.transformationController,
    this.zoomAndPan = false,
    this.maxScale = 2.5,
    this.subtitle,
    this.showSubtitles = false,
    this.subtitleBuilder,
    this.customControls,
    this.errorBuilder,
    this.bufferingBuilder,
    this.allowedScreenSleep = true,
    this.isLive = false,
    this.allowFullScreen = true,
    this.allowMuting = true,
    this.allowPlaybackSpeedChanging = true,
    this.useRootNavigator = true,
    this.playbackSpeeds = const [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2],
    this.systemOverlaysOnEnterFullScreen,
    this.deviceOrientationsOnEnterFullScreen,
    this.systemOverlaysAfterFullScreen = SystemUiOverlay.values,
    this.deviceOrientationsAfterFullScreen = DeviceOrientation.values,
    this.routePageBuilder,
    this.progressIndicatorDelay,
    this.hideControlsTimer = defaultHideControlsTimer,
    this.controlsSafeAreaMinimum = EdgeInsets.zero,
    this.pauseOnBackgroundTap = false,
  }) : assert(
         playbackSpeeds.every((speed) => speed > 0),
         'The playbackSpeeds values must all be greater than 0',
       ) {
    _initialize();
  }

  ChewieController copyWith({
    VideoPlayerController? videoPlayerController,
    OptionsTranslation? optionsTranslation,
    double? aspectRatio,
    bool? isFirstPlay,
    bool? autoInitialize,
    bool? autoPlay,
    bool? draggableProgressBar,
    Duration? startAt,
    bool? looping,
    bool? fullScreenByDefault,
    ChewieProgressColors? cupertinoProgressColors,
    ChewieProgressColors? materialProgressColors,
    Duration? materialSeekButtonFadeDuration,
    double? materialSeekButtonSize,
    Widget? placeholder,
    Widget? overlay,
    bool? showControlsOnInitialize,
    bool? showOptions,
    Future<void> Function(BuildContext, List<OptionItem>)? optionsBuilder,
    List<OptionItem> Function(BuildContext)? additionalOptions,
    bool? showControls,
    TransformationController? transformationController,
    bool? zoomAndPan,
    double? maxScale,
    Subtitles? subtitle,
    bool? showSubtitles,
    Widget Function(BuildContext, dynamic)? subtitleBuilder,
    Widget? customControls,
    WidgetBuilder? bufferingBuilder,
    Widget Function(BuildContext, String)? errorBuilder,
    bool? allowedScreenSleep,
    bool? isLive,
    bool? allowFullScreen,
    bool? allowMuting,
    bool? allowPlaybackSpeedChanging,
    bool? useRootNavigator,
    Duration? hideControlsTimer,
    EdgeInsets? controlsSafeAreaMinimum,
    List<double>? playbackSpeeds,
    List<SystemUiOverlay>? systemOverlaysOnEnterFullScreen,
    List<DeviceOrientation>? deviceOrientationsOnEnterFullScreen,
    List<SystemUiOverlay>? systemOverlaysAfterFullScreen,
    List<DeviceOrientation>? deviceOrientationsAfterFullScreen,
    Duration? progressIndicatorDelay,
    ChewieRoutePageBuilder? routePageBuilder,
    bool? pauseOnBackgroundTap,
  }) {
    return ChewieController(
      videoPlayerController:
          videoPlayerController ?? this.videoPlayerController,
      optionsTranslation: optionsTranslation ?? this.optionsTranslation,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      isFirstPlay: isFirstPlay ?? this.isFirstPlay,
      autoInitialize: autoInitialize ?? this.autoInitialize,
      autoPlay: autoPlay ?? this.autoPlay,
      draggableProgressBar: draggableProgressBar ?? this.draggableProgressBar,
      startAt: startAt ?? this.startAt,
      looping: looping ?? this.looping,
      fullScreenByDefault: fullScreenByDefault ?? this.fullScreenByDefault,
      cupertinoProgressColors:
          cupertinoProgressColors ?? this.cupertinoProgressColors,
      materialProgressColors:
          materialProgressColors ?? this.materialProgressColors,
      placeholder: placeholder ?? this.placeholder,
      overlay: overlay ?? this.overlay,
      showControlsOnInitialize:
          showControlsOnInitialize ?? this.showControlsOnInitialize,
      showOptions: showOptions ?? this.showOptions,
      optionsBuilder: optionsBuilder ?? this.optionsBuilder,
      additionalOptions: additionalOptions ?? this.additionalOptions,
      showControls: showControls ?? this.showControls,
      transformationController:
          transformationController ?? this.transformationController,
      zoomAndPan: zoomAndPan ?? this.zoomAndPan,
      maxScale: maxScale ?? this.maxScale,
      showSubtitles: showSubtitles ?? this.showSubtitles,
      subtitle: subtitle ?? this.subtitle,
      subtitleBuilder: subtitleBuilder ?? this.subtitleBuilder,
      customControls: customControls ?? this.customControls,
      errorBuilder: errorBuilder ?? this.errorBuilder,
      bufferingBuilder: bufferingBuilder ?? this.bufferingBuilder,
      allowedScreenSleep: allowedScreenSleep ?? this.allowedScreenSleep,
      isLive: isLive ?? this.isLive,
      allowFullScreen: allowFullScreen ?? this.allowFullScreen,
      allowMuting: allowMuting ?? this.allowMuting,
      allowPlaybackSpeedChanging:
          allowPlaybackSpeedChanging ?? this.allowPlaybackSpeedChanging,
      useRootNavigator: useRootNavigator ?? this.useRootNavigator,
      playbackSpeeds: playbackSpeeds ?? this.playbackSpeeds,
      systemOverlaysOnEnterFullScreen:
          systemOverlaysOnEnterFullScreen ??
          this.systemOverlaysOnEnterFullScreen,
      deviceOrientationsOnEnterFullScreen:
          deviceOrientationsOnEnterFullScreen ??
          this.deviceOrientationsOnEnterFullScreen,
      systemOverlaysAfterFullScreen:
          systemOverlaysAfterFullScreen ?? this.systemOverlaysAfterFullScreen,
      deviceOrientationsAfterFullScreen:
          deviceOrientationsAfterFullScreen ??
          this.deviceOrientationsAfterFullScreen,
      routePageBuilder: routePageBuilder ?? this.routePageBuilder,
      hideControlsTimer: hideControlsTimer ?? this.hideControlsTimer,
      progressIndicatorDelay:
          progressIndicatorDelay ?? this.progressIndicatorDelay,
      controlsSafeAreaMinimum:
          controlsSafeAreaMinimum ?? this.controlsSafeAreaMinimum,
      pauseOnBackgroundTap: pauseOnBackgroundTap ?? this.pauseOnBackgroundTap,
    );
  }

  static const defaultHideControlsTimer = Duration(seconds: 3);
  final bool showOptions;
  final OptionsTranslation? optionsTranslation;
  bool isFirstPlay;
  final VoidCallback? onCloseCallback;
  final VoidCallback? onInitialPlayCompletedCallBack;
  final Future<void> Function(
    BuildContext context,
    List<OptionItem> chewieOptions,
  )?
  optionsBuilder;
  final List<OptionItem> Function(BuildContext context)? additionalOptions;
  final Widget Function(BuildContext context, dynamic subtitle)?
  subtitleBuilder;
  Subtitles? subtitle;
  bool showSubtitles;
  final VideoPlayerController videoPlayerController;
  final bool autoInitialize;
  final bool autoPlay;
  final bool draggableProgressBar;
  final Duration? startAt;
  final bool looping;
  final bool showControlsOnInitialize;
  final bool showControls;
  final TransformationController? transformationController;
  final bool zoomAndPan;
  final double maxScale;
  final Widget? customControls;
  final Widget Function(BuildContext context, String errorMessage)?
  errorBuilder;
  final WidgetBuilder? bufferingBuilder;
  final double? aspectRatio;
  final ChewieProgressColors? cupertinoProgressColors;
  final ChewieProgressColors? materialProgressColors;
  final Duration materialSeekButtonFadeDuration;
  final double materialSeekButtonSize;
  final Widget? placeholder;
  final Widget? overlay;
  final bool fullScreenByDefault;
  final bool allowedScreenSleep;
  final bool isLive;
  final bool allowFullScreen;
  final bool allowMuting;
  final bool allowPlaybackSpeedChanging;
  final bool useRootNavigator;
  final Duration hideControlsTimer;
  final List<double> playbackSpeeds;
  final List<SystemUiOverlay>? systemOverlaysOnEnterFullScreen;
  final List<DeviceOrientation>? deviceOrientationsOnEnterFullScreen;
  final List<SystemUiOverlay> systemOverlaysAfterFullScreen;
  final List<DeviceOrientation> deviceOrientationsAfterFullScreen;
  final ChewieRoutePageBuilder? routePageBuilder;
  final Duration? progressIndicatorDelay;
  final EdgeInsets controlsSafeAreaMinimum;
  final bool pauseOnBackgroundTap;

  static ChewieController of(BuildContext context) {
    final chewieControllerProvider = context
        .dependOnInheritedWidgetOfExactType<ChewieControllerProvider>()!;
    return chewieControllerProvider.controller;
  }

  bool _isFullScreen = false;
  bool get isFullScreen => _isFullScreen;
  bool get isPlaying => videoPlayerController.value.isPlaying;

  Future<dynamic> _initialize() async {
    await videoPlayerController.setLooping(looping);

    if ((autoInitialize || autoPlay) &&
        !videoPlayerController.value.isInitialized) {
      await videoPlayerController.initialize();
    }

    if (autoPlay) {
      if (fullScreenByDefault) {
        // enterFullScreen();
      }
      await videoPlayerController.play();
    }

    if (startAt != null) {
      await videoPlayerController.seekTo(startAt!);
    }

    if (fullScreenByDefault) {
      videoPlayerController.addListener(_fullScreenListener);
    }
    if (onInitialPlayCompletedCallBack != null) {
      videoPlayerController.addListener(_onInitialPlayCompleted);
    }

    videoPlayerController.addListener(_playBackIncrement);
  }

  Future<void> _fullScreenListener() async {
    if (videoPlayerController.value.isPlaying && !_isFullScreen) {
      enterFullScreen();
      videoPlayerController.removeListener(_fullScreenListener);
    }
  }

  void _playBackIncrement() {
    if (isFinished) {
      _noOfTimesPlayed++;
    }
  }

  int _noOfTimesPlayed = 0;

  Future<void> _onInitialPlayCompleted() async {
    if (onInitialPlayCompletedCallBack != null &&
        _noOfTimesPlayed <= 1 &&
        isFinished) {
      onInitialPlayCompletedCallBack!();
      videoPlayerController.removeListener(_onInitialPlayCompleted);
    }
  }

  bool get isFinished =>
      videoPlayerController.value.position >=
      videoPlayerController.value.duration;

  void enterFullScreen({bool notify = true}) {
    _isFullScreen = true;
    if (notify) notifyListeners();
  }

  void exitFullScreen() {
    _isFullScreen = false;
    notifyListeners();
  }

  void toggleFullScreen() {
    _isFullScreen = !_isFullScreen;
    notifyListeners();
  }

  void togglePause() {
    isPlaying ? pause() : play();
  }

  Future<void> play() async {
    await videoPlayerController.play();
  }

  Future<void> setLooping(bool looping) async {
    await videoPlayerController.setLooping(looping);
  }

  Future<void> pause() async {
    await videoPlayerController.pause();
  }

  Future<void> seekTo(Duration moment) async {
    await videoPlayerController.seekTo(moment);
  }

  Future<void> setVolume(double volume) async {
    await videoPlayerController.setVolume(volume);
  }

  void setSubtitle(List<Subtitle> newSubtitle) {
    subtitle = Subtitles(newSubtitle);
  }
}

class ChewieControllerProvider extends InheritedWidget {
  const ChewieControllerProvider({
    Key? key,
    required this.controller,
    required Widget child,
  }) : super(key: key, child: child);

  final ChewieController controller;

  @override
  bool updateShouldNotify(ChewieControllerProvider oldWidget) =>
      controller != oldWidget.controller;
}
