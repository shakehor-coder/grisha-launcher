import 'package:flutter/services.dart';

import '../models/installed_app.dart';

abstract class InstalledAppsService {
  Future<List<InstalledApp>> loadApps();

  Future<String?> loadIconPath(String packageName, {int sizePx = 96});

  Future<Map<String, String?>> loadIconPaths(
    List<String> packageNames, {
    int sizePx = 96,
  });

  Future<void> launch(String packageName);

  Future<void> openAppInfo(String packageName);
}

class MethodChannelInstalledAppsService implements InstalledAppsService {
  MethodChannelInstalledAppsService([
    this._channel = const MethodChannel('com.grisha.launcher/apps'),
  ]);

  final MethodChannel _channel;

  @override
  Future<List<InstalledApp>> loadApps() async {
    final response = await _channel.invokeListMethod<Object?>(
      'getInstalledApps',
    );
    if (response == null) {
      return const <InstalledApp>[];
    }

    return response
        .whereType<Map<Object?, Object?>>()
        .map(InstalledApp.fromMap)
        .where((app) => app.packageName.isNotEmpty)
        .toList();
  }

  @override
  Future<String?> loadIconPath(String packageName, {int sizePx = 96}) async {
    return _channel.invokeMethod<String>('getAppIcon', {
      'packageName': packageName,
      'sizePx': sizePx,
    });
  }

  @override
  Future<Map<String, String?>> loadIconPaths(
    List<String> packageNames, {
    int sizePx = 96,
  }) async {
    final response = await _channel.invokeMapMethod<String, Object?>(
      'getAppIcons',
      {'packageNames': packageNames, 'sizePx': sizePx},
    );
    if (response == null) {
      return <String, String?>{};
    }
    return response.map((key, value) => MapEntry(key, value as String?));
  }

  @override
  Future<void> launch(String packageName) async {
    await _channel.invokeMethod<bool>('launchApp', {
      'packageName': packageName,
    });
  }

  @override
  Future<void> openAppInfo(String packageName) async {
    await _channel.invokeMethod<bool>('openAppInfo', {
      'packageName': packageName,
    });
  }
}
