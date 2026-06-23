import 'dart:convert';

enum WallpaperType {
  none,
  image,
  video;

  static WallpaperType fromName(String? name) {
    return WallpaperType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => WallpaperType.none,
    );
  }
}

enum LauncherTransitionStyle {
  smooth,
  slide,
  zoom,
  scale,
  fade,
  none;

  static LauncherTransitionStyle fromName(String? name) {
    return LauncherTransitionStyle.values.firstWhere(
      (style) => style.name == name,
      orElse: () => LauncherTransitionStyle.smooth,
    );
  }
}

enum LauncherQualityProfile {
  smooth,
  balanced,
  beautiful,
  saver;

  static LauncherQualityProfile fromName(String? name) {
    return LauncherQualityProfile.values.firstWhere(
      (profile) => profile.name == name,
      orElse: () => LauncherQualityProfile.balanced,
    );
  }
}

enum LauncherWidgetType {
  clock,
  weather,
  music,
  calendar,
  battery,
  quickActions,
  notes;

  static LauncherWidgetType? tryFromName(String name) {
    for (final type in LauncherWidgetType.values) {
      if (type.name == name) {
        return type;
      }
    }
    return null;
  }
}

const defaultAccentColorValue = 0xFF19E6D2;
const defaultBackgroundStartColorValue = 0xFF101116;
const defaultBackgroundEndColorValue = 0xFF0A0B0F;
const defaultIconStartColorValue = 0xFFE72E45;
const defaultIconEndColorValue = 0xFF8B1020;
const defaultAppFrameColorValue = defaultIconStartColorValue;
const defaultDrawerBackgroundColorValue = 0xFF101216;
const defaultWidgetOrder = [
  LauncherWidgetType.clock,
  LauncherWidgetType.weather,
  LauncherWidgetType.music,
  LauncherWidgetType.calendar,
  LauncherWidgetType.battery,
  LauncherWidgetType.quickActions,
  LauncherWidgetType.notes,
];

class SavedLauncherTheme {
  const SavedLauncherTheme({required this.name, required this.payload});

  final String name;
  final String payload;

  Map<String, Object?> toJson() => {'name': name, 'payload': payload};

  static SavedLauncherTheme? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final name = value['name'];
    final payload = value['payload'];
    if (name is! String ||
        name.isEmpty ||
        payload is! String ||
        payload.isEmpty) {
      return null;
    }
    return SavedLauncherTheme(name: name, payload: payload);
  }
}

class DesktopItemPosition {
  const DesktopItemPosition({required this.x, required this.y});

  final double x;
  final double y;

  DesktopItemPosition normalized() {
    return DesktopItemPosition(
      x: x.clamp(0.0, 1.0).toDouble(),
      y: y.clamp(0.0, 1.0).toDouble(),
    );
  }

  Map<String, Object?> toJson() => {'x': x, 'y': y};

  static DesktopItemPosition? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final x = value['x'];
    final y = value['y'];
    if (x is! num || y is! num) {
      return null;
    }
    return DesktopItemPosition(x: x.toDouble(), y: y.toDouble()).normalized();
  }
}

const defaultWidgetPositions = {
  LauncherWidgetType.clock: DesktopItemPosition(x: 0.02, y: 0.02),
  LauncherWidgetType.weather: DesktopItemPosition(x: 0.02, y: 0.26),
  LauncherWidgetType.music: DesktopItemPosition(x: 0.46, y: 0.02),
  LauncherWidgetType.calendar: DesktopItemPosition(x: 0.54, y: 0.26),
  LauncherWidgetType.battery: DesktopItemPosition(x: 0.02, y: 0.48),
  LauncherWidgetType.quickActions: DesktopItemPosition(x: 0.43, y: 0.48),
  LauncherWidgetType.notes: DesktopItemPosition(x: 0.02, y: 0.70),
};

class LauncherSettings {
  const LauncherSettings({
    this.favoritePackages = const <String>{},
    this.desktopPackages = const <String>{},
    this.dockPackages = const <String>{},
    this.gridColumns = 4,
    this.accentIndex = 0,
    this.backgroundGradientIndex = 0,
    this.iconGradientIndex = 0,
    this.accentColorValue = defaultAccentColorValue,
    this.backgroundStartColorValue = defaultBackgroundStartColorValue,
    this.backgroundEndColorValue = defaultBackgroundEndColorValue,
    this.iconStartColorValue = defaultIconStartColorValue,
    this.iconEndColorValue = defaultIconEndColorValue,
    this.appFrameColorValue = defaultAppFrameColorValue,
    this.drawerBackgroundColorValue = defaultDrawerBackgroundColorValue,
    this.showDesktopGrid = true,
    this.swipeUpOpensDrawer = true,
    this.swipeDownOpensSearch = true,
    this.performanceMode = false,
    this.qualityProfile = LauncherQualityProfile.balanced,
    this.transitionStyle = LauncherTransitionStyle.smooth,
    this.wallpaperType = WallpaperType.none,
    this.wallpaperPath,
    this.wallpaperFit = 'cover',
    this.iconScale = 1.0,
    this.widgetScale = 1.0,
    this.enabledWidgets = const {
      LauncherWidgetType.clock,
      LauncherWidgetType.weather,
      LauncherWidgetType.music,
      LauncherWidgetType.calendar,
      LauncherWidgetType.battery,
      LauncherWidgetType.quickActions,
      LauncherWidgetType.notes,
    },
    this.widgetOrder = defaultWidgetOrder,
    this.desktopAppPositions = const <String, DesktopItemPosition>{},
    this.widgetPositions = defaultWidgetPositions,
    this.customIconPaths = const <String, String>{},
    this.savedThemes = const <SavedLauncherTheme>[],
  });

  final Set<String> favoritePackages;
  final Set<String> desktopPackages;
  final Set<String> dockPackages;
  final int gridColumns;
  final int accentIndex;
  final int backgroundGradientIndex;
  final int iconGradientIndex;
  final int accentColorValue;
  final int backgroundStartColorValue;
  final int backgroundEndColorValue;
  final int iconStartColorValue;
  final int iconEndColorValue;
  final int appFrameColorValue;
  final int drawerBackgroundColorValue;
  final bool showDesktopGrid;
  final bool swipeUpOpensDrawer;
  final bool swipeDownOpensSearch;
  final bool performanceMode;
  final LauncherQualityProfile qualityProfile;
  final LauncherTransitionStyle transitionStyle;
  final WallpaperType wallpaperType;
  final String? wallpaperPath;
  final String wallpaperFit;
  final double iconScale;
  final double widgetScale;
  final Set<LauncherWidgetType> enabledWidgets;
  final List<LauncherWidgetType> widgetOrder;
  final Map<String, DesktopItemPosition> desktopAppPositions;
  final Map<LauncherWidgetType, DesktopItemPosition> widgetPositions;
  final Map<String, String> customIconPaths;
  final List<SavedLauncherTheme> savedThemes;

  LauncherSettings copyWith({
    Set<String>? favoritePackages,
    Set<String>? desktopPackages,
    Set<String>? dockPackages,
    int? gridColumns,
    int? accentIndex,
    int? backgroundGradientIndex,
    int? iconGradientIndex,
    int? accentColorValue,
    int? backgroundStartColorValue,
    int? backgroundEndColorValue,
    int? iconStartColorValue,
    int? iconEndColorValue,
    int? appFrameColorValue,
    int? drawerBackgroundColorValue,
    bool? showDesktopGrid,
    bool? swipeUpOpensDrawer,
    bool? swipeDownOpensSearch,
    bool? performanceMode,
    LauncherQualityProfile? qualityProfile,
    LauncherTransitionStyle? transitionStyle,
    WallpaperType? wallpaperType,
    Object? wallpaperPath = _unchanged,
    String? wallpaperFit,
    double? iconScale,
    double? widgetScale,
    Set<LauncherWidgetType>? enabledWidgets,
    List<LauncherWidgetType>? widgetOrder,
    Map<String, DesktopItemPosition>? desktopAppPositions,
    Map<LauncherWidgetType, DesktopItemPosition>? widgetPositions,
    Map<String, String>? customIconPaths,
    List<SavedLauncherTheme>? savedThemes,
  }) {
    return LauncherSettings(
      favoritePackages: favoritePackages ?? this.favoritePackages,
      desktopPackages: desktopPackages ?? this.desktopPackages,
      dockPackages: dockPackages ?? this.dockPackages,
      gridColumns: gridColumns ?? this.gridColumns,
      accentIndex: accentIndex ?? this.accentIndex,
      backgroundGradientIndex:
          backgroundGradientIndex ?? this.backgroundGradientIndex,
      iconGradientIndex: iconGradientIndex ?? this.iconGradientIndex,
      accentColorValue: accentColorValue ?? this.accentColorValue,
      backgroundStartColorValue:
          backgroundStartColorValue ?? this.backgroundStartColorValue,
      backgroundEndColorValue:
          backgroundEndColorValue ?? this.backgroundEndColorValue,
      iconStartColorValue: iconStartColorValue ?? this.iconStartColorValue,
      iconEndColorValue: iconEndColorValue ?? this.iconEndColorValue,
      appFrameColorValue: appFrameColorValue ?? this.appFrameColorValue,
      drawerBackgroundColorValue:
          drawerBackgroundColorValue ?? this.drawerBackgroundColorValue,
      showDesktopGrid: showDesktopGrid ?? this.showDesktopGrid,
      swipeUpOpensDrawer: swipeUpOpensDrawer ?? this.swipeUpOpensDrawer,
      swipeDownOpensSearch: swipeDownOpensSearch ?? this.swipeDownOpensSearch,
      performanceMode: performanceMode ?? this.performanceMode,
      qualityProfile: qualityProfile ?? this.qualityProfile,
      transitionStyle: transitionStyle ?? this.transitionStyle,
      wallpaperType: wallpaperType ?? this.wallpaperType,
      wallpaperPath: wallpaperPath == _unchanged
          ? this.wallpaperPath
          : wallpaperPath as String?,
      wallpaperFit: wallpaperFit ?? this.wallpaperFit,
      iconScale: iconScale ?? this.iconScale,
      widgetScale: widgetScale ?? this.widgetScale,
      enabledWidgets: enabledWidgets ?? this.enabledWidgets,
      widgetOrder: widgetOrder ?? this.widgetOrder,
      desktopAppPositions: desktopAppPositions ?? this.desktopAppPositions,
      widgetPositions: widgetPositions ?? this.widgetPositions,
      customIconPaths: customIconPaths ?? this.customIconPaths,
      savedThemes: savedThemes ?? this.savedThemes,
    );
  }

  LauncherSettings clearWallpaper() {
    return copyWith(
      wallpaperType: WallpaperType.none,
      wallpaperPath: null,
      wallpaperFit: 'cover',
    );
  }

  LauncherSettings setCustomIcon(String packageName, String path) {
    return copyWith(customIconPaths: {...customIconPaths, packageName: path});
  }

  LauncherSettings clearCustomIcon(String packageName) {
    final next = {...customIconPaths}..remove(packageName);
    return copyWith(customIconPaths: next);
  }

  LauncherSettings toggleDesktopApp(String packageName) {
    final next = {...desktopPackages};
    final favorites = {...favoritePackages};
    final positions = {...desktopAppPositions};
    final dock = {...dockPackages};
    if (!next.add(packageName)) {
      next.remove(packageName);
      favorites.remove(packageName);
      positions.remove(packageName);
      dock.remove(packageName);
    } else {
      favorites.add(packageName);
    }
    return copyWith(
      desktopPackages: next,
      favoritePackages: favorites,
      dockPackages: dock,
      desktopAppPositions: positions,
    );
  }

  LauncherSettings toggleDockApp(String packageName) {
    if (packageName.isEmpty) {
      return this;
    }
    final next = {...dockPackages};
    if (!next.add(packageName)) {
      next.remove(packageName);
    }
    return copyWith(dockPackages: next);
  }

  LauncherSettings moveDesktopApp(
    String packageName,
    DesktopItemPosition position,
  ) {
    if (!desktopPackages.contains(packageName)) {
      return this;
    }
    return copyWith(
      desktopAppPositions: {
        ...desktopAppPositions,
        packageName: position.normalized(),
      },
    );
  }

  LauncherSettings moveWidget(
    LauncherWidgetType type,
    DesktopItemPosition position,
  ) {
    return copyWith(
      widgetPositions: {...widgetPositions, type: position.normalized()},
    );
  }

  LauncherSettings toggleWidget(LauncherWidgetType type, bool enabled) {
    final next = {...enabledWidgets};
    if (enabled) {
      next.add(type);
    } else {
      next.remove(type);
    }
    final order = [...widgetOrder];
    if (enabled && !order.contains(type)) {
      order.add(type);
    }
    return copyWith(enabledWidgets: next, widgetOrder: order);
  }

  LauncherSettings replaceWidget(
    LauncherWidgetType previous,
    LauncherWidgetType next,
  ) {
    final widgets = {...enabledWidgets}
      ..remove(previous)
      ..add(next);
    final order = [...widgetOrder];
    final previousIndex = order.indexOf(previous);
    order.remove(next);
    if (previousIndex == -1) {
      order.add(next);
    } else {
      order[previousIndex] = next;
    }
    return copyWith(enabledWidgets: widgets, widgetOrder: order);
  }

  List<LauncherWidgetType> orderedEnabledWidgets() {
    final order = [
      ...widgetOrder,
      for (final type in LauncherWidgetType.values)
        if (!widgetOrder.contains(type)) type,
    ];
    return order.where(enabledWidgets.contains).toSet().toList(growable: false);
  }

  LauncherSettings saveCurrentTheme({DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    final label =
        'Тема ${timestamp.day.toString().padLeft(2, '0')}.'
        '${timestamp.month.toString().padLeft(2, '0')} '
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}';
    final next = [
      SavedLauncherTheme(name: label, payload: exportTheme()),
      ...savedThemes,
    ];
    return copyWith(savedThemes: next.take(8).toList());
  }

  LauncherSettings deleteSavedTheme(int index) {
    if (index < 0 || index >= savedThemes.length) {
      return this;
    }
    final next = [...savedThemes]..removeAt(index);
    return copyWith(savedThemes: next);
  }

  LauncherSettings applySavedTheme(int index) {
    if (index < 0 || index >= savedThemes.length) {
      return this;
    }
    return applyThemePayload(savedThemes[index].payload);
  }

  String exportTheme() {
    return jsonEncode({
      'schema': 1,
      'gridColumns': gridColumns,
      'accentIndex': accentIndex,
      'backgroundGradientIndex': backgroundGradientIndex,
      'iconGradientIndex': iconGradientIndex,
      'accentColorValue': accentColorValue,
      'backgroundStartColorValue': backgroundStartColorValue,
      'backgroundEndColorValue': backgroundEndColorValue,
      'iconStartColorValue': iconStartColorValue,
      'iconEndColorValue': iconEndColorValue,
      'appFrameColorValue': appFrameColorValue,
      'drawerBackgroundColorValue': drawerBackgroundColorValue,
      'showDesktopGrid': showDesktopGrid,
      'performanceMode': performanceMode,
      'qualityProfile': qualityProfile.name,
      'transitionStyle': transitionStyle.name,
      'iconScale': iconScale,
      'widgetScale': widgetScale,
      'enabledWidgets': enabledWidgets.map((type) => type.name).toList()
        ..sort(),
      'widgetOrder': widgetOrder.map((type) => type.name).toList(),
      'desktopAppPositions': _appPositionsToJson(desktopAppPositions),
      'widgetPositions': _widgetPositionsToJson(widgetPositions),
      'desktopPackages': desktopPackages.toList()..sort(),
      'dockPackages': dockPackages.toList()..sort(),
      'swipeUpOpensDrawer': swipeUpOpensDrawer,
      'swipeDownOpensSearch': swipeDownOpensSearch,
    });
  }

  LauncherSettings applyThemePayload(String payload) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Theme payload must be a JSON object');
    }
    return copyWith(
      gridColumns: _clampedIntValue(decoded['gridColumns'], 3, 5),
      accentIndex: _intValue(decoded['accentIndex']),
      backgroundGradientIndex: _intValue(decoded['backgroundGradientIndex']),
      iconGradientIndex: _intValue(decoded['iconGradientIndex']),
      accentColorValue: _colorValue(decoded['accentColorValue']),
      backgroundStartColorValue: _colorValue(
        decoded['backgroundStartColorValue'],
      ),
      backgroundEndColorValue: _colorValue(decoded['backgroundEndColorValue']),
      iconStartColorValue: _colorValue(decoded['iconStartColorValue']),
      iconEndColorValue: _colorValue(decoded['iconEndColorValue']),
      appFrameColorValue: _colorValue(decoded['appFrameColorValue']),
      drawerBackgroundColorValue: _colorValue(
        decoded['drawerBackgroundColorValue'],
      ),
      showDesktopGrid: _boolValue(decoded['showDesktopGrid']),
      performanceMode: _boolValue(decoded['performanceMode']),
      qualityProfile: _qualityProfile(decoded['qualityProfile']),
      transitionStyle: _transitionStyle(decoded['transitionStyle']),
      iconScale: _clampedDoubleValue(decoded['iconScale'], 0.75, 1.35),
      widgetScale: _clampedDoubleValue(decoded['widgetScale'], 0.75, 1.35),
      enabledWidgets: _widgetTypes(decoded['enabledWidgets']),
      widgetOrder: _widgetList(decoded['widgetOrder']),
      desktopAppPositions: _appPositionMap(decoded['desktopAppPositions']),
      widgetPositions: _widgetPositionMap(decoded['widgetPositions']),
      desktopPackages: _stringSet(decoded['desktopPackages']),
      favoritePackages: _stringSet(decoded['desktopPackages']),
      dockPackages: _stringSet(decoded['dockPackages']),
      swipeUpOpensDrawer: _boolValue(decoded['swipeUpOpensDrawer']),
      swipeDownOpensSearch: _boolValue(decoded['swipeDownOpensSearch']),
    );
  }
}

Map<String, Object?> _appPositionsToJson(
  Map<String, DesktopItemPosition> positions,
) {
  return positions.map((key, value) => MapEntry(key, value.toJson()));
}

Map<String, Object?> _widgetPositionsToJson(
  Map<LauncherWidgetType, DesktopItemPosition> positions,
) {
  return positions.map((key, value) => MapEntry(key.name, value.toJson()));
}

const _unchanged = Object();

int? _clampedIntValue(Object? value, int min, int max) {
  final parsed = _intValue(value);
  if (parsed == null) {
    return null;
  }
  return parsed.clamp(min, max).toInt();
}

double? _clampedDoubleValue(Object? value, double min, double max) {
  final parsed = _doubleValue(value);
  if (parsed == null) {
    return null;
  }
  return parsed.clamp(min, max).toDouble();
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return null;
}

double? _doubleValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

int? _colorValue(Object? value) {
  final parsed = _intValue(value);
  if (parsed == null) {
    return null;
  }
  return parsed.clamp(0xFF000000, 0xFFFFFFFF).toInt();
}

bool? _boolValue(Object? value) => value is bool ? value : null;

LauncherTransitionStyle? _transitionStyle(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return LauncherTransitionStyle.fromName(value);
}

LauncherQualityProfile? _qualityProfile(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return LauncherQualityProfile.fromName(value);
}

Set<String>? _stringSet(Object? value) {
  if (value is! List) {
    return null;
  }
  return value.whereType<String>().where((item) => item.isNotEmpty).toSet();
}

Set<LauncherWidgetType>? _widgetTypes(Object? value) {
  if (value is! List) {
    return null;
  }
  return value
      .whereType<String>()
      .map(LauncherWidgetType.tryFromName)
      .whereType<LauncherWidgetType>()
      .toSet();
}

List<LauncherWidgetType>? _widgetList(Object? value) {
  if (value is! List) {
    return null;
  }
  final seen = <LauncherWidgetType>{};
  final next = <LauncherWidgetType>[];
  for (final name in value.whereType<String>()) {
    final type = LauncherWidgetType.tryFromName(name);
    if (type != null && seen.add(type)) {
      next.add(type);
    }
  }
  return next.isEmpty ? null : next;
}

Map<String, DesktopItemPosition>? _appPositionMap(Object? value) {
  if (value is! Map<String, dynamic>) {
    return null;
  }
  final next = <String, DesktopItemPosition>{};
  for (final entry in value.entries) {
    final position = DesktopItemPosition.fromJson(entry.value);
    if (entry.key.isNotEmpty && position != null) {
      next[entry.key] = position;
    }
  }
  return next;
}

Map<LauncherWidgetType, DesktopItemPosition>? _widgetPositionMap(
  Object? value,
) {
  if (value is! Map<String, dynamic>) {
    return null;
  }
  final next = <LauncherWidgetType, DesktopItemPosition>{};
  for (final entry in value.entries) {
    final type = LauncherWidgetType.tryFromName(entry.key);
    final position = DesktopItemPosition.fromJson(entry.value);
    if (type != null && position != null) {
      next[type] = position;
    }
  }
  return next.isEmpty ? null : {...defaultWidgetPositions, ...next};
}
