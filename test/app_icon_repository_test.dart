import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:grisha_launcher/models/installed_app.dart';
import 'package:grisha_launcher/services/app_icon_repository.dart';
import 'package:grisha_launcher/services/installed_apps_service.dart';

void main() {
  test('batch prefetch сохраняет пути в memory cache', () async {
    final service = _CountingAppsService({
      'com.a': '/icons/com.a_96.png',
      'com.b': '/icons/com.b_96.png',
    });
    final repository = AppIconRepository(service);

    final result = await repository.loadIconPaths(['com.a', 'com.b']);

    expect(result['com.a'], '/icons/com.a_96.png');
    expect(repository.cachedIconPath('com.b'), '/icons/com.b_96.png');
    expect(service.batchCalls, 1);

    await repository.loadIconPaths(['com.a']);
    expect(service.batchCalls, 1);
  });

  test('AppIconRepository de-duplicates in-flight requests', () async {
    final service = _DeferredAppsService();
    final repository = AppIconRepository(service);

    final first = repository.loadIconPaths(['com.a']);
    final second = repository.loadIconPaths(['com.a']);
    service.complete({'com.a': '/icons/com.a_96.png'});

    expect((await first)['com.a'], '/icons/com.a_96.png');
    expect((await second)['com.a'], '/icons/com.a_96.png');
    expect(service.batchCalls, 1);
  });

  test('missing icon path is cached as null', () async {
    final service = _CountingAppsService({'com.missing': null});
    final repository = AppIconRepository(service);

    final result = await repository.loadIconPaths(['com.missing']);

    expect(result['com.missing'], isNull);
    expect(repository.hasResolved('com.missing'), isTrue);
  });
}

class _CountingAppsService implements InstalledAppsService {
  _CountingAppsService(this.paths);

  final Map<String, String?> paths;
  int batchCalls = 0;

  @override
  Future<List<InstalledApp>> loadApps() async => const [];

  @override
  Future<String?> loadIconPath(String packageName, {int sizePx = 96}) async {
    return paths[packageName];
  }

  @override
  Future<Map<String, String?>> loadIconPaths(
    List<String> packageNames, {
    int sizePx = 96,
  }) async {
    batchCalls++;
    return {
      for (final packageName in packageNames) packageName: paths[packageName],
    };
  }

  @override
  Future<void> launch(String packageName) async {}

  @override
  Future<void> openAppInfo(String packageName) async {}
}

class _DeferredAppsService extends _CountingAppsService {
  _DeferredAppsService() : super({});

  final Completer<Map<String, String?>> _completer = Completer();

  @override
  Future<Map<String, String?>> loadIconPaths(
    List<String> packageNames, {
    int sizePx = 96,
  }) {
    batchCalls++;
    return _completer.future;
  }

  void complete(Map<String, String?> value) {
    _completer.complete(value);
  }
}
