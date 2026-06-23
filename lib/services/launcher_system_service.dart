import 'package:flutter/services.dart';

abstract class LauncherSystemService {
  Future<bool> isDefaultLauncher();

  Future<void> requestDefaultLauncher();
}

class MethodChannelLauncherSystemService implements LauncherSystemService {
  MethodChannelLauncherSystemService([
    this._channel = const MethodChannel('com.grisha.launcher/apps'),
  ]);

  final MethodChannel _channel;

  @override
  Future<bool> isDefaultLauncher() async {
    return await _channel.invokeMethod<bool>('isDefaultLauncher') ?? false;
  }

  @override
  Future<void> requestDefaultLauncher() async {
    await _channel.invokeMethod<bool>('requestDefaultLauncher');
  }
}
