import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/launcher_settings.dart';

class WallpaperBackground extends StatelessWidget {
  const WallpaperBackground({
    required this.settings,
    required this.overlayOpacity,
    required this.child,
    this.playVideo = true,
    super.key,
  });

  final LauncherSettings settings;
  final double overlayOpacity;
  final bool playVideo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = [
      Color(settings.backgroundStartColorValue),
      Color(settings.backgroundEndColorValue),
    ];
    return Stack(
      fit: StackFit.expand,
      children: [
        _WallpaperLayer(settings: settings, playVideo: playVideo),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors
                  .map((color) => color.withValues(alpha: overlayOpacity))
                  .toList(growable: false),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _WallpaperLayer extends StatelessWidget {
  const _WallpaperLayer({required this.settings, required this.playVideo});

  final LauncherSettings settings;
  final bool playVideo;

  @override
  Widget build(BuildContext context) {
    final path = settings.wallpaperPath;
    if (path == null || path.isEmpty) {
      return _GradientFallback(settings: settings);
    }

    return switch (settings.wallpaperType) {
      WallpaperType.image => Image.file(
        File(path),
        key: const Key('image-wallpaper-background'),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => _GradientFallback(settings: settings),
      ),
      WallpaperType.video => _VideoWallpaperBackground(
        settings: settings,
        path: path,
        playing: playVideo,
      ),
      WallpaperType.none => _GradientFallback(settings: settings),
    };
  }
}

class _GradientFallback extends StatelessWidget {
  const _GradientFallback({required this.settings});

  final LauncherSettings settings;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const Key('gradient-wallpaper-background'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(settings.backgroundStartColorValue),
            Color(settings.backgroundEndColorValue),
          ],
        ),
      ),
    );
  }
}

class _VideoWallpaperBackground extends StatefulWidget {
  const _VideoWallpaperBackground({
    required this.settings,
    required this.path,
    required this.playing,
  });

  final LauncherSettings settings;
  final String path;
  final bool playing;

  @override
  State<_VideoWallpaperBackground> createState() =>
      _VideoWallpaperBackgroundState();
}

class _VideoWallpaperBackgroundState extends State<_VideoWallpaperBackground> {
  VideoPlayerController? _controller;
  bool _ready = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load(widget.path);
  }

  @override
  void didUpdateWidget(covariant _VideoWallpaperBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _load(widget.path);
    } else if (oldWidget.playing != widget.playing) {
      unawaited(_syncPlayback());
    }
  }

  Future<void> _load(String path) async {
    final generation = ++_loadGeneration;
    final previous = _controller;
    _controller = null;
    _ready = false;
    await previous?.dispose();

    final controller = VideoPlayerController.file(File(path))
      ..setLooping(true)
      ..setVolume(0);

    try {
      await controller.initialize();
      if (!mounted || generation != _loadGeneration) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      setState(() => _ready = true);
      unawaited(_syncPlayback());
    } catch (_) {
      await controller.dispose();
      if (mounted && generation == _loadGeneration) {
        setState(() => _ready = false);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null) {
      return _GradientFallback(settings: widget.settings);
    }

    return FittedBox(
      key: const Key('video-wallpaper-background'),
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  Future<void> _syncPlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (widget.playing) {
      await controller.play();
    } else {
      await controller.pause();
    }
  }
}
