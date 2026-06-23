import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grisha_launcher/main.dart';
import 'package:grisha_launcher/models/installed_app.dart';
import 'package:grisha_launcher/models/launcher_settings.dart';
import 'package:grisha_launcher/models/weather_snapshot.dart';
import 'package:grisha_launcher/services/installed_apps_service.dart';
import 'package:grisha_launcher/services/launcher_system_service.dart';
import 'package:grisha_launcher/services/settings_repository.dart';
import 'package:grisha_launcher/services/wallpaper_service.dart';
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

  testWidgets('главная показывает рабочий стол без каталога', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('Рабочий стол'), findsOneWidget);
    expect(find.text('Каталог'), findsNothing);
    expect(find.text('Поиск'), findsNothing);
    expect(find.text('Все'), findsNothing);
    expect(find.text('Вид'), findsNothing);
    expect(find.text('Обновить'), findsNothing);
  });

  testWidgets('переключатель категорий фильтрует список приложений', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Работа'));
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
    expect(find.text('Добавить на рабочий стол'), findsOneWidget);
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

  testWidgets('плотность сетки 5 не вызывает overflow', (tester) async {
    await tester.pumpWidget(
      _testApp(
        apps: _longNameApps,
        settings: const LauncherSettings(gridColumns: 5),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('при готовом iconPath приложение рендерит file image', (
    tester,
  ) async {
    final iconFile = File('${Directory.systemTemp.path}/grisha_app_icon.png');
    iconFile.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
      ),
    );

    await tester.pumpWidget(
      _testApp(iconPaths: {'com.android.calculator2': iconFile.path}),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.grid_view));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('file-app-icon')), findsWidgets);
  });

  testWidgets('в настройках есть действия для обоев', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();

    expect(find.text('Обои'), findsOneWidget);
    expect(find.text('Фото из галереи'), findsOneWidget);
    expect(find.text('Видео-обои'), findsOneWidget);
    expect(find.text('Сбросить фон'), findsOneWidget);
  });

  testWidgets('в настройках есть цвета, сетка и темы', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();

    expect(find.text('Цвета'), findsOneWidget);
    expect(find.text('Акцент'), findsOneWidget);
    expect(find.text('Иконки'), findsOneWidget);

    await tester.tap(find.text('Стол').first);
    await tester.pumpAndSettle();
    expect(find.text('Показывать сетку рабочего стола'), findsOneWidget);

    await tester.tap(find.text('Темы').first);
    await tester.pumpAndSettle();
    expect(find.text('Сохранить'), findsOneWidget);
  });

  testWidgets('в настройках есть кнопка системного лаунчера', (tester) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Система'));
    await tester.pumpAndSettle();

    expect(find.text('Системный лаунчер'), findsOneWidget);
    expect(find.text('Сделать лаунчером по умолчанию'), findsOneWidget);
    expect(find.text('Не выбран как лаунчер'), findsOneWidget);
    expect(find.textContaining('Xiaomi/HyperOS'), findsOneWidget);
    expect(find.textContaining('Рабочий стол'), findsOneWidget);
  });

  testWidgets('показывает статус выбранного системного лаунчера', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(isDefaultLauncher: true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Система'));
    await tester.pumpAndSettle();

    expect(find.text('Уже выбран как лаунчер'), findsOneWidget);
  });

  testWidgets('кнопка системного лаунчера вызывает Android bridge', (
    tester,
  ) async {
    final launcherSystemService = _FakeLauncherSystemService(false);
    await tester.pumpWidget(
      _testApp(launcherSystemService: launcherSystemService),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Система'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сделать лаунчером по умолчанию'));
    await tester.pumpAndSettle();

    expect(launcherSystemService.requestCount, 1);
  });

  testWidgets('без выбранных обоев используется gradient fallback', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('gradient-wallpaper-background')),
      findsWidgets,
    );
  });
}

GrishaLauncherApp _testApp({
  List<InstalledApp>? apps,
  Map<String, String?> iconPaths = const {},
  LauncherSettings settings = const LauncherSettings(),
  bool isDefaultLauncher = false,
  LauncherSystemService? launcherSystemService,
}) {
  final appsService = _FakeAppsService(apps ?? _defaultApps);
  appsService.iconPaths.addAll(iconPaths);
  return GrishaLauncherApp(
    appsService: appsService,
    launcherSystemService:
        launcherSystemService ?? _FakeLauncherSystemService(isDefaultLauncher),
    settingsRepository: _FakeSettingsRepository(settings),
    wallpaperService: _FakeWallpaperService(),
    weatherService: _FakeWeatherService(),
  );
}

class _FakeAppsService implements InstalledAppsService {
  _FakeAppsService(this.apps);

  final List<InstalledApp> apps;
  final Map<String, String?> iconPaths = {};

  @override
  Future<List<InstalledApp>> loadApps() async => apps;

  @override
  Future<String?> loadIconPath(String packageName, {int sizePx = 96}) async {
    return iconPaths[packageName];
  }

  @override
  Future<Map<String, String?>> loadIconPaths(
    List<String> packageNames, {
    int sizePx = 96,
  }) async {
    return {
      for (final packageName in packageNames)
        packageName: iconPaths[packageName],
    };
  }

  @override
  Future<void> launch(String packageName) async {}

  @override
  Future<void> openAppInfo(String packageName) async {}
}

class _FakeLauncherSystemService implements LauncherSystemService {
  _FakeLauncherSystemService(this.defaultLauncher);

  bool defaultLauncher;
  int requestCount = 0;

  @override
  Future<bool> isDefaultLauncher() async => defaultLauncher;

  @override
  Future<void> requestDefaultLauncher() async {
    requestCount++;
  }
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
  _FakeSettingsRepository(this.settings);

  LauncherSettings settings;

  @override
  Future<LauncherSettings> load() async => settings;

  @override
  Future<void> save(LauncherSettings settings) async {
    this.settings = settings;
  }
}

class _FakeWallpaperService implements WallpaperService {
  @override
  Future<WallpaperSelection?> pickCustomIcon() async => null;

  @override
  Future<WallpaperSelection?> pickImageWallpaper() async => null;

  @override
  Future<WallpaperSelection?> pickVideoWallpaper() async => null;
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
