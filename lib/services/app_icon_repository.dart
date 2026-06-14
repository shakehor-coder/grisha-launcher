import 'dart:typed_data';

import 'installed_apps_service.dart';

class AppIconRepository {
  AppIconRepository(this._appsService);

  final InstalledAppsService _appsService;
  final Map<String, Uint8List?> _cache = {};
  final Map<String, Future<Uint8List?>> _inFlight = {};

  Future<Uint8List?> loadIcon(String packageName, {int sizePx = 96}) {
    final cacheKey = '$packageName@$sizePx';
    if (_cache.containsKey(cacheKey)) {
      return Future.value(_cache[cacheKey]);
    }

    final existing = _inFlight[cacheKey];
    if (existing != null) {
      return existing;
    }

    final future = _appsService
        .loadIcon(packageName, sizePx: sizePx)
        .then((icon) {
          _cache[cacheKey] = icon;
          return icon;
        })
        .whenComplete(() => _inFlight.remove(cacheKey));
    _inFlight[cacheKey] = future;
    return future;
  }

  void clear() {
    _cache.clear();
    _inFlight.clear();
  }
}
