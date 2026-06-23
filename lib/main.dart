import 'package:flutter/material.dart';

import 'services/installed_apps_service.dart';
import 'services/launcher_system_service.dart';
import 'services/settings_repository.dart';
import 'services/wallpaper_service.dart';
import 'services/weather_service.dart';
import 'ui/launcher_home.dart';

void main() {
  runApp(
    GrishaLauncherApp(
      appsService: MethodChannelInstalledAppsService(),
      launcherSystemService: MethodChannelLauncherSystemService(),
      settingsRepository: SharedPreferencesSettingsRepository(),
      wallpaperService: MethodChannelWallpaperService(),
      weatherService: OpenMeteoWeatherService(),
    ),
  );
}

class GrishaLauncherApp extends StatelessWidget {
  const GrishaLauncherApp({
    required this.appsService,
    required this.launcherSystemService,
    required this.settingsRepository,
    required this.wallpaperService,
    required this.weatherService,
    super.key,
  });

  final InstalledAppsService appsService;
  final LauncherSystemService launcherSystemService;
  final SettingsRepository settingsRepository;
  final WallpaperService wallpaperService;
  final WeatherService weatherService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Grisha Launcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: const Color(0xFF11D9C5),
        ),
        scaffoldBackgroundColor: const Color(0xFF090B10),
        useMaterial3: true,
      ),
      home: LauncherHome(
        appsService: appsService,
        launcherSystemService: launcherSystemService,
        settingsRepository: settingsRepository,
        wallpaperService: wallpaperService,
        weatherService: weatherService,
      ),
    );
  }
}
