import 'package:shared_preferences/shared_preferences.dart';

import '../models/launcher_settings.dart';

abstract class SettingsRepository {
  Future<LauncherSettings> load();

  Future<void> save(LauncherSettings settings);
}

class SharedPreferencesSettingsRepository implements SettingsRepository {
  static const _favoritesKey = 'favorites';
  static const _gridColumnsKey = 'gridColumns';
  static const _accentIndexKey = 'accentIndex';
  static const _swipeUpKey = 'swipeUpOpensDrawer';
  static const _swipeDownKey = 'swipeDownOpensSearch';

  @override
  Future<LauncherSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return LauncherSettings(
      favoritePackages: (prefs.getStringList(_favoritesKey) ?? const <String>[])
          .toSet(),
      gridColumns: prefs.getInt(_gridColumnsKey) ?? 4,
      accentIndex: prefs.getInt(_accentIndexKey) ?? 0,
      swipeUpOpensDrawer: prefs.getBool(_swipeUpKey) ?? true,
      swipeDownOpensSearch: prefs.getBool(_swipeDownKey) ?? true,
    );
  }

  @override
  Future<void> save(LauncherSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _favoritesKey,
      settings.favoritePackages.toList()..sort(),
    );
    await prefs.setInt(_gridColumnsKey, settings.gridColumns);
    await prefs.setInt(_accentIndexKey, settings.accentIndex);
    await prefs.setBool(_swipeUpKey, settings.swipeUpOpensDrawer);
    await prefs.setBool(_swipeDownKey, settings.swipeDownOpensSearch);
  }
}
