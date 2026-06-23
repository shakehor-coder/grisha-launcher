import 'package:flutter/services.dart';

class WallpaperSelection {
  const WallpaperSelection({required this.type, required this.path});

  final String type;
  final String path;

  factory WallpaperSelection.fromMap(Map<Object?, Object?> map) {
    return WallpaperSelection(
      type: map['type'] as String? ?? 'image',
      path: map['path'] as String? ?? '',
    );
  }
}

abstract class WallpaperService {
  Future<WallpaperSelection?> pickImageWallpaper();

  Future<WallpaperSelection?> pickVideoWallpaper();

  Future<WallpaperSelection?> pickCustomIcon();
}

class MethodChannelWallpaperService implements WallpaperService {
  MethodChannelWallpaperService([
    this._channel = const MethodChannel('com.grisha.launcher/wallpaper'),
  ]);

  final MethodChannel _channel;

  @override
  Future<WallpaperSelection?> pickImageWallpaper() async {
    return _pick('pickImageWallpaper');
  }

  @override
  Future<WallpaperSelection?> pickVideoWallpaper() async {
    return _pick('pickVideoWallpaper');
  }

  @override
  Future<WallpaperSelection?> pickCustomIcon() async {
    return _pick('pickCustomIcon');
  }

  Future<WallpaperSelection?> _pick(String method) async {
    final response = await _channel.invokeMapMethod<Object?, Object?>(method);
    if (response == null) {
      return null;
    }
    final selection = WallpaperSelection.fromMap(response);
    return selection.path.isEmpty ? null : selection;
  }
}
