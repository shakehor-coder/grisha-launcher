import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grisha_launcher/main.dart';
import 'package:grisha_launcher/models/installed_app.dart';
import 'package:grisha_launcher/models/launcher_settings.dart';
import 'package:grisha_launcher/models/weather_snapshot.dart';
import 'package:grisha_launcher/services/installed_apps_service.dart';
import 'package:grisha_launcher/services/settings_repository.dart';
import 'package:grisha_launcher/services/weather_service.dart';

void main() {
  testWidgets('показывает список приложений и фильтрует поиск', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('Главная'), findsOneWidget);
    expect(find.text('Приложения'), findsOneWidget);
    expect(find.text('Настройки'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pumpAndSettle();

    expect(find.text('Calculator'), findsOneWidget);
    expect(find.text('Chrome'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('app-search')), 'calc');
    await tester.pumpAndSettle();

    expect(find.text('Calculator'), findsOneWidget);
    expect(find.text('Chrome'), findsNothing);
  });

  testWidgets('долгое нажатие открывает русское меню действий', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pumpAndSettle();

    final calculatorTile = find.ancestor(
      of: find.text('Calculator'),
      matching: find.byType(InkWell),
    );
    await tester.longPress(calculatorTile.first);
    await tester.pumpAndSettle();

    expect(find.text('Запустить'), findsOneWidget);
    expect(find.text('В избранное'), findsOneWidget);
    expect(find.text('О приложении'), findsOneWidget);
  });

  testWidgets('длинные названия приложений не вызывают overflow', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(apps: _longNameApps));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

GrishaLauncherApp _testApp({List<InstalledApp>? apps}) {
  return GrishaLauncherApp(
    appsService: _FakeAppsService(apps ?? _defaultApps),
    settingsRepository: _FakeSettingsRepository(),
    weatherService: _FakeWeatherService(),
  );
}

class _FakeAppsService implements InstalledAppsService {
  _FakeAppsService(this.apps);

  final List<InstalledApp> apps;

  @override
  Future<List<InstalledApp>> loadApps() async => apps;

  @override
  Future<Uint8List?> loadIcon(String packageName, {int sizePx = 96}) async {
    return null;
  }

  @override
  Future<void> launch(String packageName) async {}

  @override
  Future<void> openAppInfo(String packageName) async {}
}

const _defaultApps = [
  InstalledApp(
    label: 'Calculator',
    packageName: 'com.android.calculator2',
    iconBytes: null,
    isSystem: true,
    category: 'Работа',
  ),
  InstalledApp(
    label: 'Chrome',
    packageName: 'com.android.chrome',
    iconBytes: null,
    isSystem: false,
    category: 'Приложения',
  ),
];

const _longNameApps = [
  InstalledApp(
    label: 'Очень длинное название приложения для проверки плитки',
    packageName: 'com.example.longname',
    iconBytes: null,
    isSystem: false,
    category: 'Приложения',
  ),
];

class _FakeSettingsRepository implements SettingsRepository {
  LauncherSettings settings = const LauncherSettings();

  @override
  Future<LauncherSettings> load() async => settings;

  @override
  Future<void> save(LauncherSettings settings) async {
    this.settings = settings;
  }
}

class _FakeWeatherService implements WeatherService {
  @override
  Future<WeatherSnapshot> loadCurrentWeatherByLocation() async {
    return WeatherSnapshot(
      temperatureCelsius: 21,
      conditionCode: 0,
      updatedAt: DateTime(2026, 6, 14, 12),
      placeLabel: '55.75, 37.62',
    );
  }
}
