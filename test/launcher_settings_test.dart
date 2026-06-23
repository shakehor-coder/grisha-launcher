import 'package:flutter_test/flutter_test.dart';
import 'package:grisha_launcher/models/launcher_settings.dart';

void main() {
  test('настройки обоев сохраняют тип, путь и режим заполнения', () {
    final settings = const LauncherSettings().copyWith(
      wallpaperType: WallpaperType.image,
      wallpaperPath: '/tmp/wallpaper.jpg',
      wallpaperFit: 'cover',
    );

    expect(settings.wallpaperType, WallpaperType.image);
    expect(settings.wallpaperPath, '/tmp/wallpaper.jpg');
    expect(settings.wallpaperFit, 'cover');
  });

  test('clearWallpaper возвращает состояние без обоев', () {
    final settings = const LauncherSettings(
      wallpaperType: WallpaperType.video,
      wallpaperPath: '/tmp/wallpaper.mp4',
    ).clearWallpaper();

    expect(settings.wallpaperType, WallpaperType.none);
    expect(settings.wallpaperPath, isNull);
    expect(settings.wallpaperFit, 'cover');
  });

  test(
    'WallpaperType.fromName безопасно обрабатывает неизвестные значения',
    () {
      expect(WallpaperType.fromName('image'), WallpaperType.image);
      expect(WallpaperType.fromName('video'), WallpaperType.video);
      expect(WallpaperType.fromName('wat'), WallpaperType.none);
      expect(WallpaperType.fromName(null), WallpaperType.none);
    },
  );

  test('настройки кастомизации сохраняют виджеты и размеры', () {
    final settings = const LauncherSettings().copyWith(
      iconScale: 1.25,
      widgetScale: 0.9,
      enabledWidgets: {LauncherWidgetType.clock, LauncherWidgetType.music},
    );

    expect(settings.iconScale, 1.25);
    expect(settings.widgetScale, 0.9);
    expect(settings.enabledWidgets, {
      LauncherWidgetType.clock,
      LauncherWidgetType.music,
    });
  });

  test('кастомная иконка добавляется и сбрасывается по packageName', () {
    final customized = const LauncherSettings().setCustomIcon(
      'com.test.app',
      '/tmp/icon.png',
    );

    expect(customized.customIconPaths['com.test.app'], '/tmp/icon.png');
    expect(
      customized.clearCustomIcon('com.test.app').customIconPaths,
      isNot(contains('com.test.app')),
    );
  });

  test('рабочий стол добавляет и убирает packageName', () {
    final added = const LauncherSettings().toggleDesktopApp('com.test.app');

    expect(added.desktopPackages, contains('com.test.app'));
    expect(added.favoritePackages, contains('com.test.app'));
    expect(
      added.toggleDesktopApp('com.test.app').desktopPackages,
      isNot(contains('com.test.app')),
    );
  });

  test('тема экспортируется и применяется', () {
    final settings = const LauncherSettings(
      gridColumns: 5,
      accentIndex: 2,
      backgroundGradientIndex: 1,
      iconGradientIndex: 3,
      appFrameColorValue: 0xFFABCDEF,
      showDesktopGrid: false,
      performanceMode: true,
      transitionStyle: LauncherTransitionStyle.zoom,
      qualityProfile: LauncherQualityProfile.beautiful,
      iconScale: 1.25,
      widgetScale: 0.85,
      desktopPackages: {'com.test.app'},
      dockPackages: {'com.test.app'},
      enabledWidgets: {LauncherWidgetType.music},
    );

    final applied = const LauncherSettings().applyThemePayload(
      settings.exportTheme(),
    );

    expect(applied.gridColumns, 5);
    expect(applied.accentIndex, 2);
    expect(applied.backgroundGradientIndex, 1);
    expect(applied.iconGradientIndex, 3);
    expect(applied.appFrameColorValue, 0xFFABCDEF);
    expect(applied.showDesktopGrid, isFalse);
    expect(applied.performanceMode, isTrue);
    expect(applied.transitionStyle, LauncherTransitionStyle.zoom);
    expect(applied.qualityProfile, LauncherQualityProfile.beautiful);
    expect(applied.iconScale, 1.25);
    expect(applied.widgetScale, 0.85);
    expect(applied.desktopPackages, {'com.test.app'});
    expect(applied.dockPackages, {'com.test.app'});
    expect(applied.enabledWidgets, {LauncherWidgetType.music});
  });

  test('dock app toggles independently from desktop apps', () {
    final settings = const LauncherSettings().toggleDockApp('com.test.app');

    expect(settings.dockPackages, {'com.test.app'});
    expect(settings.desktopPackages, isEmpty);
    expect(settings.toggleDockApp('com.test.app').dockPackages, isEmpty);
  });

  test('desktop positions are saved in settings and theme payload', () {
    final settings = const LauncherSettings()
        .toggleDesktopApp('com.test.app')
        .moveDesktopApp(
          'com.test.app',
          const DesktopItemPosition(x: 0.42, y: 0.64),
        )
        .moveWidget(
          LauncherWidgetType.calendar,
          const DesktopItemPosition(x: 0.8, y: 0.2),
        );

    final applied = const LauncherSettings().applyThemePayload(
      settings.exportTheme(),
    );

    expect(settings.desktopAppPositions['com.test.app']?.x, 0.42);
    expect(settings.desktopAppPositions['com.test.app']?.y, 0.64);
    expect(settings.widgetPositions[LauncherWidgetType.calendar]?.x, 0.8);
    expect(applied.desktopAppPositions['com.test.app']?.x, 0.42);
    expect(applied.widgetPositions[LauncherWidgetType.calendar]?.y, 0.2);
  });
}
