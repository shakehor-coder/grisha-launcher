import 'package:flutter_test/flutter_test.dart';
import 'package:grisha_launcher/models/launcher_settings.dart';
import 'package:grisha_launcher/services/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('репозиторий сохраняет и читает настройки обоев', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = SharedPreferencesSettingsRepository();

    await repository.save(
      const LauncherSettings(
        wallpaperType: WallpaperType.video,
        wallpaperPath: '/tmp/wallpaper.mp4',
        wallpaperFit: 'cover',
      ),
    );

    final loaded = await repository.load();

    expect(loaded.wallpaperType, WallpaperType.video);
    expect(loaded.wallpaperPath, '/tmp/wallpaper.mp4');
    expect(loaded.wallpaperFit, 'cover');
  });

  test('репозиторий удаляет путь при сбросе обоев', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = SharedPreferencesSettingsRepository();

    await repository.save(
      const LauncherSettings(
        wallpaperType: WallpaperType.image,
        wallpaperPath: '/tmp/wallpaper.jpg',
      ),
    );
    await repository.save(const LauncherSettings().clearWallpaper());

    final loaded = await repository.load();

    expect(loaded.wallpaperType, WallpaperType.none);
    expect(loaded.wallpaperPath, isNull);
  });

  test('репозиторий сохраняет настройки интерфейса', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = SharedPreferencesSettingsRepository();

    await repository.save(
      const LauncherSettings(
        iconScale: 1.2,
        widgetScale: 0.85,
        backgroundGradientIndex: 2,
        iconGradientIndex: 1,
        appFrameColorValue: 0xFF336699,
        showDesktopGrid: false,
        performanceMode: true,
        transitionStyle: LauncherTransitionStyle.scale,
        qualityProfile: LauncherQualityProfile.smooth,
        desktopPackages: {'com.test.app'},
        dockPackages: {'com.test.app'},
        enabledWidgets: {LauncherWidgetType.clock, LauncherWidgetType.music},
        customIconPaths: {'com.test.app': '/tmp/icon.png'},
        savedThemes: [
          SavedLauncherTheme(name: 'Test', payload: '{"schema":1}'),
        ],
      ),
    );

    final loaded = await repository.load();

    expect(loaded.iconScale, 1.2);
    expect(loaded.widgetScale, 0.85);
    expect(loaded.backgroundGradientIndex, 2);
    expect(loaded.iconGradientIndex, 1);
    expect(loaded.appFrameColorValue, 0xFF336699);
    expect(loaded.showDesktopGrid, isFalse);
    expect(loaded.performanceMode, isTrue);
    expect(loaded.transitionStyle, LauncherTransitionStyle.scale);
    expect(loaded.qualityProfile, LauncherQualityProfile.smooth);
    expect(loaded.desktopPackages, {'com.test.app'});
    expect(loaded.dockPackages, {'com.test.app'});
    expect(loaded.enabledWidgets, {
      LauncherWidgetType.clock,
      LauncherWidgetType.music,
    });
    expect(loaded.customIconPaths['com.test.app'], '/tmp/icon.png');
    expect(loaded.savedThemes.single.name, 'Test');
  });

  test('repository persists desktop item positions', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = SharedPreferencesSettingsRepository();

    await repository.save(
      const LauncherSettings(
        desktopPackages: {'com.test.app'},
        desktopAppPositions: {
          'com.test.app': DesktopItemPosition(x: 0.25, y: 0.75),
        },
        widgetPositions: {
          LauncherWidgetType.notes: DesktopItemPosition(x: 0.6, y: 0.35),
        },
      ),
    );

    final loaded = await repository.load();

    expect(loaded.desktopAppPositions['com.test.app']?.x, 0.25);
    expect(loaded.desktopAppPositions['com.test.app']?.y, 0.75);
    expect(loaded.widgetPositions[LauncherWidgetType.notes]?.x, 0.6);
    expect(loaded.widgetPositions[LauncherWidgetType.notes]?.y, 0.35);
  });
}
