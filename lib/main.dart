import 'package:flutter/material.dart';

import 'services/installed_apps_service.dart';
import 'services/settings_repository.dart';
import 'services/weather_service.dart';
import 'ui/launcher_home.dart';

void main() {
  runApp(
    GrishaLauncherApp(
      appsService: MethodChannelInstalledAppsService(),
      settingsRepository: SharedPreferencesSettingsRepository(),
      weatherService: OpenMeteoWeatherService(),
    ),
  );
}

class GrishaLauncherApp extends StatelessWidget {
  const GrishaLauncherApp({
    required this.appsService,
    required this.settingsRepository,
    required this.weatherService,
    super.key,
  });

  final InstalledAppsService appsService;
  final SettingsRepository settingsRepository;
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
        settingsRepository: settingsRepository,
        weatherService: weatherService,
      ),
    );
  }
}
