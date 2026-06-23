import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/launcher_settings.dart';

abstract class SettingsRepository {
  Future<LauncherSettings> load();

  Future<void> save(LauncherSettings settings);
}

class SharedPreferencesSettingsRepository implements SettingsRepository {
  static const _favoritesKey = 'favorites';
  static const _desktopPackagesKey = 'desktopPackages';
  static const _dockPackagesKey = 'dockPackages';
  static const _gridColumnsKey = 'gridColumns';
  static const _accentIndexKey = 'accentIndex';
  static const _backgroundGradientIndexKey = 'backgroundGradientIndex';
  static const _iconGradientIndexKey = 'iconGradientIndex';
  static const _accentColorKey = 'accentColorValue';
  static const _backgroundStartColorKey = 'backgroundStartColorValue';
  static const _backgroundEndColorKey = 'backgroundEndColorValue';
  static const _iconStartColorKey = 'iconStartColorValue';
  static const _iconEndColorKey = 'iconEndColorValue';
  static const _appFrameColorKey = 'appFrameColorValue';
  static const _drawerBackgroundColorKey = 'drawerBackgroundColorValue';
  static const _showDesktopGridKey = 'showDesktopGrid';
  static const _swipeUpKey = 'swipeUpOpensDrawer';
  static const _swipeDownKey = 'swipeDownOpensSearch';
  static const _performanceModeKey = 'performanceMode';
  static const _qualityProfileKey = 'qualityProfile';
  static const _transitionStyleKey = 'transitionStyle';
  static const _wallpaperTypeKey = 'wallpaperType';
  static const _wallpaperPathKey = 'wallpaperPath';
  static const _wallpaperFitKey = 'wallpaperFit';
  static const _iconScaleKey = 'iconScale';
  static const _widgetScaleKey = 'widgetScale';
  static const _enabledWidgetsKey = 'enabledWidgets';
  static const _widgetOrderKey = 'widgetOrder';
  static const _desktopAppPositionsKey = 'desktopAppPositions';
  static const _widgetPositionsKey = 'widgetPositions';
  static const _customIconPathsKey = 'customIconPaths';
  static const _savedThemesKey = 'savedThemes';

  @override
  Future<LauncherSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = (prefs.getStringList(_favoritesKey) ?? const <String>[])
        .toSet();
    return LauncherSettings(
      favoritePackages: favorites,
      desktopPackages:
          (prefs.getStringList(_desktopPackagesKey) ?? favorites.toList())
              .toSet(),
      dockPackages: (prefs.getStringList(_dockPackagesKey) ?? const <String>[])
          .toSet(),
      gridColumns: prefs.getInt(_gridColumnsKey) ?? 4,
      accentIndex: prefs.getInt(_accentIndexKey) ?? 0,
      backgroundGradientIndex: prefs.getInt(_backgroundGradientIndexKey) ?? 0,
      iconGradientIndex: prefs.getInt(_iconGradientIndexKey) ?? 0,
      accentColorValue:
          prefs.getInt(_accentColorKey) ?? defaultAccentColorValue,
      backgroundStartColorValue:
          prefs.getInt(_backgroundStartColorKey) ??
          defaultBackgroundStartColorValue,
      backgroundEndColorValue:
          prefs.getInt(_backgroundEndColorKey) ??
          defaultBackgroundEndColorValue,
      iconStartColorValue:
          prefs.getInt(_iconStartColorKey) ?? defaultIconStartColorValue,
      iconEndColorValue:
          prefs.getInt(_iconEndColorKey) ?? defaultIconEndColorValue,
      appFrameColorValue:
          prefs.getInt(_appFrameColorKey) ?? defaultAppFrameColorValue,
      drawerBackgroundColorValue:
          prefs.getInt(_drawerBackgroundColorKey) ??
          defaultDrawerBackgroundColorValue,
      showDesktopGrid: prefs.getBool(_showDesktopGridKey) ?? true,
      swipeUpOpensDrawer: prefs.getBool(_swipeUpKey) ?? true,
      swipeDownOpensSearch: prefs.getBool(_swipeDownKey) ?? true,
      performanceMode: prefs.getBool(_performanceModeKey) ?? false,
      qualityProfile: LauncherQualityProfile.fromName(
        prefs.getString(_qualityProfileKey),
      ),
      transitionStyle: LauncherTransitionStyle.fromName(
        prefs.getString(_transitionStyleKey),
      ),
      wallpaperType: WallpaperType.fromName(prefs.getString(_wallpaperTypeKey)),
      wallpaperPath: prefs.getString(_wallpaperPathKey),
      wallpaperFit: prefs.getString(_wallpaperFitKey) ?? 'cover',
      iconScale: _clampScale(prefs.getDouble(_iconScaleKey) ?? 1.0),
      widgetScale: _clampScale(prefs.getDouble(_widgetScaleKey) ?? 1.0),
      enabledWidgets: _loadEnabledWidgets(prefs),
      widgetOrder: _loadWidgetOrder(prefs),
      desktopAppPositions: _loadDesktopAppPositions(prefs),
      widgetPositions: _loadWidgetPositions(prefs),
      customIconPaths: _loadCustomIconPaths(prefs),
      savedThemes: _loadSavedThemes(prefs),
    );
  }

  @override
  Future<void> save(LauncherSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _favoritesKey,
      settings.favoritePackages.toList()..sort(),
    );
    await prefs.setStringList(
      _desktopPackagesKey,
      settings.desktopPackages.toList()..sort(),
    );
    await prefs.setStringList(
      _dockPackagesKey,
      settings.dockPackages.toList()..sort(),
    );
    await prefs.setInt(_gridColumnsKey, settings.gridColumns);
    await prefs.setInt(_accentIndexKey, settings.accentIndex);
    await prefs.setInt(
      _backgroundGradientIndexKey,
      settings.backgroundGradientIndex,
    );
    await prefs.setInt(_iconGradientIndexKey, settings.iconGradientIndex);
    await prefs.setInt(_accentColorKey, settings.accentColorValue);
    await prefs.setInt(
      _backgroundStartColorKey,
      settings.backgroundStartColorValue,
    );
    await prefs.setInt(
      _backgroundEndColorKey,
      settings.backgroundEndColorValue,
    );
    await prefs.setInt(_iconStartColorKey, settings.iconStartColorValue);
    await prefs.setInt(_iconEndColorKey, settings.iconEndColorValue);
    await prefs.setInt(_appFrameColorKey, settings.appFrameColorValue);
    await prefs.setInt(
      _drawerBackgroundColorKey,
      settings.drawerBackgroundColorValue,
    );
    await prefs.setBool(_showDesktopGridKey, settings.showDesktopGrid);
    await prefs.setBool(_swipeUpKey, settings.swipeUpOpensDrawer);
    await prefs.setBool(_swipeDownKey, settings.swipeDownOpensSearch);
    await prefs.setBool(_performanceModeKey, settings.performanceMode);
    await prefs.setString(_qualityProfileKey, settings.qualityProfile.name);
    await prefs.setString(_transitionStyleKey, settings.transitionStyle.name);
    await prefs.setString(_wallpaperTypeKey, settings.wallpaperType.name);
    await prefs.setString(_wallpaperFitKey, settings.wallpaperFit);
    await prefs.setDouble(_iconScaleKey, _clampScale(settings.iconScale));
    await prefs.setDouble(_widgetScaleKey, _clampScale(settings.widgetScale));
    await prefs.setStringList(
      _enabledWidgetsKey,
      settings.enabledWidgets.map((type) => type.name).toList()..sort(),
    );
    await prefs.setStringList(
      _widgetOrderKey,
      settings.widgetOrder.map((type) => type.name).toList(),
    );
    await prefs.setString(
      _desktopAppPositionsKey,
      jsonEncode(
        settings.desktopAppPositions.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      ),
    );
    await prefs.setString(
      _widgetPositionsKey,
      jsonEncode(
        settings.widgetPositions.map(
          (key, value) => MapEntry(key.name, value.toJson()),
        ),
      ),
    );
    await prefs.setString(
      _customIconPathsKey,
      jsonEncode(settings.customIconPaths),
    );
    await prefs.setStringList(
      _savedThemesKey,
      settings.savedThemes.map((theme) => jsonEncode(theme.toJson())).toList(),
    );
    final wallpaperPath = settings.wallpaperPath;
    if (wallpaperPath == null || wallpaperPath.isEmpty) {
      await prefs.remove(_wallpaperPathKey);
    } else {
      await prefs.setString(_wallpaperPathKey, wallpaperPath);
    }
  }

  Set<LauncherWidgetType> _loadEnabledWidgets(SharedPreferences prefs) {
    final names = prefs.getStringList(_enabledWidgetsKey);
    if (names == null) {
      return const {
        LauncherWidgetType.clock,
        LauncherWidgetType.weather,
        LauncherWidgetType.music,
        LauncherWidgetType.calendar,
        LauncherWidgetType.battery,
        LauncherWidgetType.quickActions,
        LauncherWidgetType.notes,
      };
    }
    return names
        .map(LauncherWidgetType.tryFromName)
        .whereType<LauncherWidgetType>()
        .toSet();
  }

  List<LauncherWidgetType> _loadWidgetOrder(SharedPreferences prefs) {
    final names = prefs.getStringList(_widgetOrderKey);
    if (names == null) {
      return defaultWidgetOrder;
    }
    final seen = <LauncherWidgetType>{};
    final order = <LauncherWidgetType>[];
    for (final name in names) {
      final type = LauncherWidgetType.tryFromName(name);
      if (type != null && seen.add(type)) {
        order.add(type);
      }
    }
    for (final type in LauncherWidgetType.values) {
      if (seen.add(type)) {
        order.add(type);
      }
    }
    return order;
  }

  Map<String, DesktopItemPosition> _loadDesktopAppPositions(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(_desktopAppPositionsKey);
    if (raw == null || raw.isEmpty) {
      return const <String, DesktopItemPosition>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const <String, DesktopItemPosition>{};
      }
      final next = <String, DesktopItemPosition>{};
      for (final entry in decoded.entries) {
        final position = DesktopItemPosition.fromJson(entry.value);
        if (entry.key.isNotEmpty && position != null) {
          next[entry.key] = position;
        }
      }
      return next;
    } catch (_) {
      return const <String, DesktopItemPosition>{};
    }
  }

  Map<LauncherWidgetType, DesktopItemPosition> _loadWidgetPositions(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(_widgetPositionsKey);
    if (raw == null || raw.isEmpty) {
      return defaultWidgetPositions;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return defaultWidgetPositions;
      }
      final next = <LauncherWidgetType, DesktopItemPosition>{};
      for (final entry in decoded.entries) {
        final type = LauncherWidgetType.tryFromName(entry.key);
        final position = DesktopItemPosition.fromJson(entry.value);
        if (type != null && position != null) {
          next[type] = position;
        }
      }
      return {...defaultWidgetPositions, ...next};
    } catch (_) {
      return defaultWidgetPositions;
    }
  }

  Map<String, String> _loadCustomIconPaths(SharedPreferences prefs) {
    final raw = prefs.getString(_customIconPathsKey);
    if (raw == null || raw.isEmpty) {
      return const <String, String>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const <String, String>{};
      }
      return decoded.map(
        (key, value) => MapEntry(key, value is String ? value : ''),
      )..removeWhere((_, value) => value.isEmpty);
    } catch (_) {
      return const <String, String>{};
    }
  }

  List<SavedLauncherTheme> _loadSavedThemes(SharedPreferences prefs) {
    final rawThemes = prefs.getStringList(_savedThemesKey);
    if (rawThemes == null || rawThemes.isEmpty) {
      return const <SavedLauncherTheme>[];
    }
    return rawThemes
        .map((raw) {
          try {
            return SavedLauncherTheme.fromJson(jsonDecode(raw));
          } catch (_) {
            return null;
          }
        })
        .whereType<SavedLauncherTheme>()
        .toList(growable: false);
  }

  double _clampScale(double value) => value.clamp(0.75, 1.35).toDouble();
}
