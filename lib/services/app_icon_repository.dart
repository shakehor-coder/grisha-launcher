import 'dart:collection';

import 'installed_apps_service.dart';

class AppIconRepository {
  AppIconRepository(this._appsService);

  static const _maxMemoryEntries = 512;

  final InstalledAppsService _appsService;
  final LinkedHashMap<String, String?> _cache = LinkedHashMap();
  final Map<String, Future<String?>> _inFlight = {};

  String? cachedIconPath(String packageName, {int sizePx = 96}) {
    final key = _cacheKey(packageName, sizePx);
    if (!_cache.containsKey(key)) {
      return null;
    }
    final value = _cache.remove(key);
    _cache[key] = value;
    return value;
  }

  bool hasResolved(String packageName, {int sizePx = 96}) {
    return _cache.containsKey(_cacheKey(packageName, sizePx));
  }

  Future<String?> loadIconPath(String packageName, {int sizePx = 96}) async {
    final result = await loadIconPaths([packageName], sizePx: sizePx);
    return result[packageName];
  }

  Future<Map<String, String?>> loadIconPaths(
    List<String> packageNames, {
    int sizePx = 96,
  }) async {
    final uniquePackages = packageNames
        .where((packageName) => packageName.isNotEmpty)
        .toSet()
        .toList();
    final result = <String, String?>{};
    final missingPackages = <String>[];
    final pendingFutures = <Future<void>>[];

    for (final packageName in uniquePackages) {
      final key = _cacheKey(packageName, sizePx);
      if (_cache.containsKey(key)) {
        final path = _cache.remove(key);
        _cache[key] = path;
        result[packageName] = path;
        continue;
      }

      final pending = _inFlight[key];
      if (pending != null) {
        pendingFutures.add(
          pending.then((path) {
            result[packageName] = path;
          }),
        );
        continue;
      }

      missingPackages.add(packageName);
    }

    if (missingPackages.isNotEmpty) {
      final batchFuture = _appsService.loadIconPaths(
        missingPackages,
        sizePx: sizePx,
      );
      for (final packageName in missingPackages) {
        final key = _cacheKey(packageName, sizePx);
        _inFlight[key] = batchFuture.then((batch) => batch[packageName]);
      }

      try {
        final batch = await batchFuture;
        for (final packageName in missingPackages) {
          final key = _cacheKey(packageName, sizePx);
          final path = batch[packageName];
          _cache[key] = path;
          _trimCache();
          result[packageName] = path;
        }
      } finally {
        for (final packageName in missingPackages) {
          _inFlight.remove(_cacheKey(packageName, sizePx));
        }
      }
    }

    if (pendingFutures.isNotEmpty) {
      await Future.wait(pendingFutures);
    }

    return result;
  }

  void clearMemory() {
    _cache.clear();
    _inFlight.clear();
  }

  void _trimCache() {
    while (_cache.length > _maxMemoryEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  String _cacheKey(String packageName, int sizePx) => '$packageName@$sizePx';
}
