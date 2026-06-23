import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../models/installed_app.dart';
import '../models/launcher_settings.dart';
import '../models/weather_snapshot.dart';
import '../services/app_icon_repository.dart';
import '../services/installed_apps_service.dart';
import '../services/launcher_system_service.dart';
import '../services/settings_repository.dart';
import '../services/wallpaper_service.dart';
import '../services/weather_service.dart';
import '../state/app_catalog.dart';
import 'launcher_palette.dart';
import 'wallpaper_background.dart';

int _colorToInt(Color color) => color.toARGB32();

(int, int, int) _rgbFromColor(Color color) {
  final value = _colorToInt(color);
  return ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF);
}

Color _colorFromRgb(int red, int green, int blue) {
  return Color(
    0xFF000000 |
        ((red.clamp(0, 255).toInt()) << 16) |
        ((green.clamp(0, 255).toInt()) << 8) |
        blue.clamp(0, 255).toInt(),
  );
}

bool _stringSetsEqual(Set<String> first, Set<String> second) {
  return first.length == second.length && first.containsAll(second);
}

enum _ColorTarget { accent, desktop, drawer, icons, frames }

enum _SettingsTab { view, desktop, motion, themes, system }

class LauncherHome extends StatefulWidget {
  const LauncherHome({
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
  State<LauncherHome> createState() => _LauncherHomeState();
}

class _LauncherHomeState extends State<LauncherHome>
    with WidgetsBindingObserver {
  static const _iconSizePx = 96;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _drawerScrollController = ScrollController();
  late final AppIconRepository _iconRepository;
  LauncherSettings _settings = const LauncherSettings();
  WeatherSnapshot? _weather;
  List<InstalledApp> _apps = const [];
  List<InstalledApp> _catalog = const [];
  List<InstalledApp> _favorites = const [];
  List<InstalledApp> _visibleApps = const [];
  List<String> _categories = const ['Все'];
  Map<String, String?> _iconPaths = const {};
  _ColorTarget _colorTarget = _ColorTarget.desktop;
  _SettingsTab _settingsTab = _SettingsTab.view;
  String _category = 'Все';
  int _pageIndex = 0;
  int _pageDirection = 1;
  bool _loading = true;
  bool? _isDefaultLauncher;
  bool _launcherStatusLoading = false;
  String? _error;
  String? _wallpaperStatus;
  String? _themeStatus;
  Timer? _settingsSaveTimer;
  LauncherSettings? _pendingSettingsSave;

  Color get _accent => Color(_settings.accentColorValue);

  Color get _appFrameColor => Color(_settings.appFrameColorValue);

  bool get _performanceOptimized {
    return _performanceOptimizedFor(_settings);
  }

  bool _performanceOptimizedFor(LauncherSettings settings) {
    return settings.performanceMode ||
        settings.qualityProfile == LauncherQualityProfile.smooth ||
        settings.qualityProfile == LauncherQualityProfile.saver;
  }

  bool get _showRichMotion {
    return !_performanceOptimized &&
        _settings.qualityProfile == LauncherQualityProfile.beautiful;
  }

  int get _iconPrefetchWindowSize {
    return switch (_settings.qualityProfile) {
      LauncherQualityProfile.saver => 10,
      LauncherQualityProfile.smooth => 16,
      LauncherQualityProfile.balanced => 24,
      LauncherQualityProfile.beautiful => 30,
    };
  }

  double get _drawerCacheExtent {
    return switch (_settings.qualityProfile) {
      LauncherQualityProfile.saver => 360,
      LauncherQualityProfile.smooth => 620,
      LauncherQualityProfile.balanced => 900,
      LauncherQualityProfile.beautiful => 1200,
    };
  }

  Duration get _pageAnimationDuration {
    return _performanceOptimized
        ? const Duration(milliseconds: 170)
        : _showRichMotion
        ? const Duration(milliseconds: 430)
        : const Duration(milliseconds: 330);
  }

  LinearGradient get _iconGradient {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(_settings.iconStartColorValue),
        Color(_settings.iconEndColorValue),
      ],
    );
  }

  List<InstalledApp> get _dockApps {
    final appsByPackage = {for (final app in _catalog) app.packageName: app};
    final pinned = [
      for (final packageName in _settings.dockPackages)
        if (appsByPackage[packageName] != null) appsByPackage[packageName]!,
    ];
    if (pinned.isNotEmpty) {
      return pinned.take(5).toList(growable: false);
    }
    final fallback = _favorites.isNotEmpty ? _favorites : _catalog;
    return fallback.take(5).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _iconRepository = AppIconRepository(widget.appsService);
    _searchController.addListener(_handleSearchChanged);
    _drawerScrollController.addListener(_handleDrawerScroll);
    _load();
    unawaited(_refreshLauncherStatus());
  }

  @override
  void dispose() {
    unawaited(_flushPendingSettings());
    WidgetsBinding.instance.removeObserver(this);
    _searchController.removeListener(_handleSearchChanged);
    _drawerScrollController.removeListener(_handleDrawerScroll);
    _drawerScrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshLauncherStatus());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flushPendingSettings());
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final loadedSettings = await widget.settingsRepository.load();
      if (!mounted) {
        return;
      }

      setState(() {
        _settings = loadedSettings;
        if (_performanceOptimizedFor(loadedSettings)) {
          _weather = WeatherSnapshot.fallback('Быстрый режим');
        }
        _loading = false;
      });
      unawaited(_loadAppsCatalog());
      if (!_performanceOptimizedFor(loadedSettings)) {
        unawaited(_loadWeather());
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = 'Служба лаунчера недоступна';
      });
    }
  }

  Future<void> _loadAppsCatalog() async {
    try {
      final apps = await widget.appsService.loadApps();
      if (!mounted) {
        return;
      }
      setState(() {
        _apps = apps;
        _iconRepository.clearMemory();
        _iconPaths = const {};
        _refreshDerivedState();
      });
      _queuePrimaryIconPrefetch();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Служба лаунчера недоступна');
    }
  }

  Future<void> _loadWeather() async {
    try {
      final weather = await widget.weatherService
          .loadCurrentWeatherByLocation();
      if (mounted) {
        setState(() => _weather = weather);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _weather = null);
      }
    }
  }

  Future<void> _saveSettings(
    LauncherSettings settings, {
    bool debounce = false,
  }) async {
    final previous = _settings;
    final desktopAppsChanged = !_stringSetsEqual(
      previous.desktopPackages,
      settings.desktopPackages,
    );
    if (mounted) {
      setState(() {
        _settings = settings;
        if (!_performanceOptimizedFor(previous) &&
            _performanceOptimizedFor(settings)) {
          _weather = WeatherSnapshot.fallback('Быстрый режим');
        }
        if (desktopAppsChanged) {
          _refreshDerivedState();
        }
      });
      if (desktopAppsChanged) {
        _queuePrimaryIconPrefetch();
      }
    }
    if (debounce) {
      _pendingSettingsSave = settings;
      _settingsSaveTimer?.cancel();
      _settingsSaveTimer = Timer(const Duration(milliseconds: 260), () {
        final pending = _pendingSettingsSave;
        _pendingSettingsSave = null;
        if (pending != null) {
          unawaited(widget.settingsRepository.save(pending));
        }
      });
      return;
    }
    _settingsSaveTimer?.cancel();
    _pendingSettingsSave = null;
    await widget.settingsRepository.save(settings);
    if (_performanceOptimizedFor(previous) &&
        !_performanceOptimizedFor(settings)) {
      unawaited(_loadWeather());
    }
  }

  Future<void> _flushPendingSettings() async {
    _settingsSaveTimer?.cancel();
    final pendingSettings = _pendingSettingsSave;
    _pendingSettingsSave = null;
    if (pendingSettings != null) {
      await widget.settingsRepository.save(pendingSettings);
    }
  }

  Future<void> _toggleFavorite(InstalledApp app) async {
    await _saveSettings(_settings.toggleDesktopApp(app.packageName));
  }

  Future<void> _toggleDockApp(InstalledApp app) async {
    await _saveSettings(_settings.toggleDockApp(app.packageName));
  }

  Future<void> _refreshLauncherStatus() async {
    if (_launcherStatusLoading) {
      return;
    }
    setState(() => _launcherStatusLoading = true);

    try {
      final isDefault = await widget.launcherSystemService.isDefaultLauncher();
      if (!mounted) {
        return;
      }
      setState(() {
        _isDefaultLauncher = isDefault;
        _launcherStatusLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isDefaultLauncher = null;
        _launcherStatusLoading = false;
      });
    }
  }

  Future<void> _requestDefaultLauncher() async {
    try {
      await widget.launcherSystemService.requestDefaultLauncher();
    } finally {
      unawaited(_refreshLauncherStatus());
    }
  }

  void _openDrawer({bool focusSearch = false}) {
    _setPageIndex(1);
    if (focusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    }
  }

  void _setPageIndex(int index) {
    final next = index.clamp(0, 2).toInt();
    if (next == _pageIndex) {
      return;
    }
    setState(() {
      _pageDirection = next > _pageIndex ? 1 : -1;
      _pageIndex = next;
    });
  }

  void _handleSearchChanged() {
    setState(() => _visibleApps = _filteredVisibleApps());
    _queueIconPrefetch(_visibleApps.take(_iconPrefetchWindowSize));
  }

  void _handleDrawerScroll() {
    if (!_drawerScrollController.hasClients || _visibleApps.isEmpty) {
      return;
    }
    final position = _drawerScrollController.position;
    if (position.extentAfter > 900) {
      return;
    }
    final maxScroll = position.maxScrollExtent;
    final progress = maxScroll <= 0 ? 0.0 : position.pixels / maxScroll;
    final index = (progress * _visibleApps.length).floor();
    _queueVisibleWindowPrefetch(index);
  }

  void _refreshDerivedState() {
    _catalog = applyFavorites(_apps, _settings.desktopPackages);
    _favorites = _catalog.where((app) => app.isFavorite).toList();
    _categories = appCategories(_catalog);
    if (!_categories.contains(_category)) {
      _category = 'Все';
    }
    _visibleApps = _filteredVisibleApps();
  }

  List<InstalledApp> _filteredVisibleApps() {
    final searched = filterApps(_catalog, _searchController.text);
    if (_category == 'Все') {
      return searched;
    }
    return searched.where((app) => app.category == _category).toList();
  }

  void _queuePrimaryIconPrefetch() {
    final apps = <InstalledApp>[
      ..._favorites,
      ..._visibleApps.take(_iconPrefetchWindowSize),
    ];
    _queueIconPrefetch(apps);
  }

  void _queueVisibleWindowPrefetch(int index) {
    final end = math.min(index + 16, _visibleApps.length);
    _queueIconPrefetch(_visibleApps.getRange(index, end));
  }

  void _queueIconPrefetch(Iterable<InstalledApp> apps) {
    final packages = apps
        .map((app) => app.packageName)
        .where((packageName) => packageName.isNotEmpty)
        .where((packageName) => !_iconRepository.hasResolved(packageName))
        .toSet()
        .toList();
    if (packages.isEmpty) {
      return;
    }

    unawaited(_loadIconPaths(packages));
  }

  Future<void> _loadIconPaths(List<String> packageNames) async {
    final paths = await _iconRepository.loadIconPaths(
      packageNames,
      sizePx: _iconSizePx,
    );
    if (!mounted || paths.isEmpty) {
      return;
    }

    setState(() {
      _iconPaths = {..._iconPaths, ...paths};
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -260 && _settings.swipeUpOpensDrawer) {
      _openDrawer();
    }
    if (velocity > 260 && _settings.swipeDownOpensSearch) {
      _openDrawer(focusSearch: true);
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 260) {
      return;
    }
    if (velocity < 0) {
      _setPageIndex(_pageIndex + 1);
    } else {
      _setPageIndex(_pageIndex - 1);
    }
  }

  String? _iconPathFor(InstalledApp app) {
    return _settings.customIconPaths[app.packageName] ??
        _iconPaths[app.packageName];
  }

  @override
  Widget build(BuildContext context) {
    final themed = Theme.of(context).copyWith(
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.dark,
        seedColor: _accent,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? _accent.withValues(alpha: 0.24)
                : Colors.white.withValues(alpha: 0.06);
          }),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected) ? _accent : null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? _accent.withValues(alpha: 0.36)
              : null;
        }),
      ),
    );

    return Theme(
      data: themed,
      child: GestureDetector(
        onVerticalDragEnd: _handleDragEnd,
        onHorizontalDragEnd: _handleHorizontalDragEnd,
        child: Scaffold(
          body: WallpaperBackground(
            settings: _settings,
            overlayOpacity: _pageIndex == 0 ? 0.48 : 0.78,
            playVideo:
                _pageIndex == 0 &&
                !_performanceOptimized &&
                _settings.qualityProfile != LauncherQualityProfile.saver,
            child: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: _pageAnimationDuration,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: _buildPageTransition,
                      child: _loading
                          ? _LoadingView(
                              key: const ValueKey('loading'),
                              accent: _accent,
                            )
                          : KeyedSubtree(
                              key: ValueKey(
                                '$_pageIndex-${_settings.transitionStyle.name}',
                              ),
                              child: _buildPage(),
                            ),
                    ),
                  ),
                  _BottomNav(
                    index: _pageIndex,
                    accent: _accent,
                    backgroundColor: _pageIndex == 1
                        ? Color(_settings.drawerBackgroundColorValue)
                        : Color(_settings.backgroundEndColorValue),
                    onChanged: _setPageIndex,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage() {
    return switch (_pageIndex) {
      0 => _buildHome(),
      1 => _buildDrawer(),
      _ => _buildSettings(),
    };
  }

  Widget _buildPageTransition(Widget child, Animation<double> animation) {
    final style = _performanceOptimized
        ? LauncherTransitionStyle.fade
        : _settings.transitionStyle;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return switch (style) {
      LauncherTransitionStyle.none => child,
      LauncherTransitionStyle.fade => FadeTransition(
        opacity: curved,
        child: child,
      ),
      LauncherTransitionStyle.slide => SlideTransition(
        position: Tween<Offset>(
          begin: Offset(0.16 * _pageDirection, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
      LauncherTransitionStyle.scale => FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      ),
      LauncherTransitionStyle.zoom => FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 1.04, end: 1).animate(curved),
          child: child,
        ),
      ),
      LauncherTransitionStyle.smooth => FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0.08 * _pageDirection, 0),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
            child: child,
          ),
        ),
      ),
    };
  }

  Widget _buildHome() {
    return _DesktopSurface(
      settings: _settings,
      apps: _favorites,
      dockApps: _dockApps,
      weather: _weather,
      error: _error,
      accent: _accent,
      iconGradient: _iconGradient,
      appFrameColor: _appFrameColor,
      iconPathFor: _iconPathFor,
      onLaunchApp: widget.appsService.launch,
      onAppMenu: _showAppActions,
      onAddApp: _showAddAppToDesktopSheet,
      onAddWidget: () => _showWidgetPicker(),
      onAddDockApp: _showAddDockAppSheet,
      onDockAppMenu: _showAppActions,
      onToggleGrid: _toggleDesktopGrid,
      onDesktopActions: _showDesktopActions,
      onMoveApp: _moveDesktopApp,
      onMoveWidget: _moveDesktopWidget,
      onRemoveApp: _removeDesktopApp,
      onRemoveWidget: _removeDesktopWidget,
      onWidgetMenu: _showWidgetActions,
      onOpenDrawer: () => _openDrawer(),
      onOpenSettings: () => _setPageIndex(2),
    );
  }

  Widget _buildDrawer() {
    final categories = _categories;

    return ColoredBox(
      color: Color(_settings.drawerBackgroundColorValue),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: TextField(
              key: const Key('app-search'),
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Поиск приложений',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Очистить',
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.close),
                      ),
                filled: true,
                fillColor: const Color(0xFF1B1E25),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final category = categories[index];
                final selected = category == _category;
                return ChoiceChip(
                  label: Text(category),
                  selected: selected,
                  selectedColor: _accent.withValues(alpha: 0.26),
                  backgroundColor: const Color(0xFF1B1E25),
                  onSelected: (_) {
                    setState(() {
                      _category = category;
                      _visibleApps = _filteredVisibleApps();
                    });
                    _queueIconPrefetch(
                      _visibleApps.take(_iconPrefetchWindowSize),
                    );
                  },
                );
              },
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemCount: categories.length,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            child: _SectionHeader(
              title: 'Все приложения',
              count: _visibleApps.length,
            ),
          ),
          Expanded(
            child: _visibleApps.isEmpty
                ? _StatusStrip(text: 'Ничего не найдено', accent: _accent)
                : GridView.builder(
                    controller: _drawerScrollController,
                    scrollCacheExtent: ScrollCacheExtent.pixels(
                      _drawerCacheExtent,
                    ),
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _settings.gridColumns,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: _gridAspectRatio(_settings.gridColumns),
                    ),
                    itemCount: _visibleApps.length,
                    itemBuilder: (context, index) {
                      final app = _visibleApps[index];
                      return _AppTile(
                        app: app,
                        accent: _accent,
                        iconGradient: _iconGradient,
                        appFrameColor: _appFrameColor,
                        iconPath: _iconPathFor(app),
                        iconScale: _settings.iconScale,
                        onLaunch: widget.appsService.launch,
                        onLongPress: _showAppActions,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _colorPresetTitle(_ColorTarget target) {
    return switch (target) {
      _ColorTarget.accent => 'Акцент',
      _ColorTarget.desktop => 'Фон',
      _ColorTarget.drawer => 'Фон приложений',
      _ColorTarget.icons => 'Иконки',
      _ColorTarget.frames => 'Рамки',
    };
  }

  List<LauncherGradientPreset> _colorPresets(_ColorTarget target) {
    return switch (target) {
      _ColorTarget.accent => launcherAccentPresets,
      _ColorTarget.desktop => launcherBackgroundPresets,
      _ColorTarget.drawer => launcherBackgroundPresets,
      _ColorTarget.icons => launcherIconPresets,
      _ColorTarget.frames => launcherIconPresets,
    };
  }

  int _selectedColorPresetIndex(_ColorTarget target) {
    return switch (target) {
      _ColorTarget.accent => _settings.accentIndex,
      _ColorTarget.desktop => _settings.backgroundGradientIndex,
      _ColorTarget.drawer => _presetIndexByFirstColor(
        launcherBackgroundPresets,
        Color(_settings.drawerBackgroundColorValue),
      ),
      _ColorTarget.icons => _settings.iconGradientIndex,
      _ColorTarget.frames => _presetIndexByFirstColor(
        launcherIconPresets,
        Color(_settings.appFrameColorValue),
      ),
    };
  }

  int _presetIndexByFirstColor(
    List<LauncherGradientPreset> presets,
    Color color,
  ) {
    final value = _colorToInt(color);
    return presets.indexWhere(
      (preset) =>
          preset.colors.isNotEmpty && _colorToInt(preset.colors.first) == value,
    );
  }

  void _applyColorPreset(int index) {
    final presets = _colorPresets(_colorTarget);
    if (index < 0 || index >= presets.length) {
      return;
    }
    final preset = presets[index];
    final startColorValue = _colorToInt(preset.colors.first);
    final endColorValue = _colorToInt(preset.colors.last);
    final frameFollowsIcons =
        _settings.appFrameColorValue == _settings.iconStartColorValue;
    final next = switch (_colorTarget) {
      _ColorTarget.accent => _settings.copyWith(
        accentIndex: index,
        accentColorValue: startColorValue,
      ),
      _ColorTarget.desktop => _settings.copyWith(
        backgroundGradientIndex: index,
        backgroundStartColorValue: startColorValue,
        backgroundEndColorValue: endColorValue,
      ),
      _ColorTarget.drawer => _settings.copyWith(
        drawerBackgroundColorValue: startColorValue,
      ),
      _ColorTarget.icons => _settings.copyWith(
        iconGradientIndex: index,
        iconStartColorValue: startColorValue,
        iconEndColorValue: endColorValue,
        appFrameColorValue: frameFollowsIcons ? startColorValue : null,
      ),
      _ColorTarget.frames => _settings.copyWith(
        appFrameColorValue: startColorValue,
      ),
    };
    unawaited(_saveSettings(next));
  }

  List<Widget> _colorControlsForTarget(_ColorTarget target) {
    return switch (target) {
      _ColorTarget.accent => [
        _ColorControl(
          title: 'Акцент вручную',
          value: Color(_settings.accentColorValue),
          onChanged: (color) => _saveSettings(
            _settings.copyWith(accentColorValue: _colorToInt(color)),
            debounce: true,
          ),
        ),
      ],
      _ColorTarget.desktop => [
        _ColorControl(
          title: 'Фон 1',
          value: Color(_settings.backgroundStartColorValue),
          onChanged: (color) => _saveSettings(
            _settings.copyWith(backgroundStartColorValue: _colorToInt(color)),
            debounce: true,
          ),
        ),
        _ColorControl(
          title: 'Фон 2',
          value: Color(_settings.backgroundEndColorValue),
          onChanged: (color) => _saveSettings(
            _settings.copyWith(backgroundEndColorValue: _colorToInt(color)),
            debounce: true,
          ),
        ),
      ],
      _ColorTarget.drawer => [
        _ColorControl(
          title: 'Фон приложений',
          value: Color(_settings.drawerBackgroundColorValue),
          onChanged: (color) => _saveSettings(
            _settings.copyWith(drawerBackgroundColorValue: _colorToInt(color)),
            debounce: true,
          ),
        ),
      ],
      _ColorTarget.icons => [
        _ColorControl(
          title: 'Иконки 1',
          value: Color(_settings.iconStartColorValue),
          onChanged: (color) => _saveSettings(
            _settings.copyWith(iconStartColorValue: _colorToInt(color)),
            debounce: true,
          ),
        ),
        _ColorControl(
          title: 'Иконки 2',
          value: Color(_settings.iconEndColorValue),
          onChanged: (color) => _saveSettings(
            _settings.copyWith(iconEndColorValue: _colorToInt(color)),
            debounce: true,
          ),
        ),
      ],
      _ColorTarget.frames => [
        _ColorControl(
          title: 'Окантовка приложений',
          value: Color(_settings.appFrameColorValue),
          onChanged: (color) => _saveSettings(
            _settings.copyWith(appFrameColorValue: _colorToInt(color)),
            debounce: true,
          ),
        ),
      ],
    };
  }

  Widget _buildSettings() {
    final panels = _settingsPanelsForTab();
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
      children: [
        const Text(
          'Настройки',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        _SettingsTabSelector(
          selected: _settingsTab,
          onChanged: (tab) => setState(() => _settingsTab = tab),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < panels.length; i++) ...[
          panels[i],
          if (i != panels.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  List<Widget> _settingsPanelsForTab() {
    return switch (_settingsTab) {
      _SettingsTab.view => [_wallpaperSettingsPanel(), _colorSettingsPanel()],
      _SettingsTab.desktop => [
        _gridSettingsPanel(),
        _sizeSettingsPanel(),
        _widgetSettingsPanel(),
      ],
      _SettingsTab.motion => [_qualitySettingsPanel(), _gestureSettingsPanel()],
      _SettingsTab.themes => [_themeSettingsPanel()],
      _SettingsTab.system => [_systemSettingsPanel()],
    };
  }

  Widget _systemSettingsPanel() {
    return _SettingsPanel(
      title: 'Системный лаунчер',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LauncherStatusStrip(
            isDefault: _isDefaultLauncher,
            loading: _launcherStatusLoading,
            accent: _accent,
          ),
          const SizedBox(height: 10),
          _WallpaperActionTile(
            icon: Icons.home,
            title: 'Сделать лаунчером по умолчанию',
            subtitle: 'Открыть выбор или приложения по умолчанию',
            accent: _accent,
            onTap: _requestDefaultLauncher,
          ),
          const SizedBox(height: 8),
          _XiaomiLauncherHint(accent: _accent),
        ],
      ),
    );
  }

  Widget _wallpaperSettingsPanel() {
    return _SettingsPanel(
      title: 'Обои',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WallpaperSummary(type: _settings.wallpaperType, accent: _accent),
          const SizedBox(height: 10),
          _WallpaperActionTile(
            icon: Icons.image,
            title: 'Фото из галереи',
            subtitle: 'Поставить фото только на фон лаунчера',
            accent: _accent,
            onTap: _pickImageWallpaper,
          ),
          _WallpaperActionTile(
            icon: Icons.video_library,
            title: 'Видео-обои',
            subtitle: 'Выбрать видео только для фона лаунчера',
            accent: _accent,
            onTap: _pickVideoWallpaper,
          ),
          _WallpaperActionTile(
            icon: Icons.layers_clear,
            title: 'Сбросить фон',
            subtitle: 'Вернуть стандартный игровой фон',
            accent: _accent,
            onTap: _clearWallpaper,
          ),
          if (_wallpaperStatus != null) ...[
            const SizedBox(height: 10),
            _StatusStrip(text: _wallpaperStatus!, accent: _accent),
          ],
        ],
      ),
    );
  }

  Widget _gridSettingsPanel() {
    return _SettingsPanel(
      title: 'Плотность сетки',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 3, label: Text('3')),
              ButtonSegment(value: 4, label: Text('4')),
              ButtonSegment(value: 5, label: Text('5')),
            ],
            selected: {_settings.gridColumns},
            onSelectionChanged: (value) {
              _saveSettings(_settings.copyWith(gridColumns: value.first));
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _settings.showDesktopGrid,
            onChanged: (value) =>
                _saveSettings(_settings.copyWith(showDesktopGrid: value)),
            title: const Text('Показывать сетку рабочего стола'),
          ),
        ],
      ),
    );
  }

  Widget _sizeSettingsPanel() {
    return _SettingsPanel(
      title: 'Размеры',
      child: Column(
        children: [
          _ScaleSlider(
            title: 'Иконки',
            value: _settings.iconScale,
            onChanged: (value) {
              _saveSettings(
                _settings.copyWith(iconScale: value),
                debounce: true,
              );
            },
          ),
          _ScaleSlider(
            title: 'Виджеты',
            value: _settings.widgetScale,
            onChanged: (value) {
              _saveSettings(
                _settings.copyWith(widgetScale: value),
                debounce: true,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _qualitySettingsPanel() {
    return _SettingsPanel(
      title: 'Плавность',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _QualityProfilePicker(
            value: _settings.qualityProfile,
            onChanged: (profile) => _saveSettings(
              _settings.copyWith(
                qualityProfile: profile,
                performanceMode: false,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _TransitionStylePicker(
            value: _settings.transitionStyle,
            enabled: !_performanceOptimized,
            onChanged: (style) =>
                _saveSettings(_settings.copyWith(transitionStyle: style)),
          ),
        ],
      ),
    );
  }

  Widget _widgetSettingsPanel() {
    return _SettingsPanel(
      title: 'Виджеты',
      child: Column(
        children: [
          for (final type in LauncherWidgetType.values)
            _WidgetSwitch(
              title: _widgetTitle(type),
              icon: _widgetIcon(type),
              value: _settings.enabledWidgets.contains(type),
              onChanged: (value) =>
                  _saveSettings(_settings.toggleWidget(type, value)),
            ),
        ],
      ),
    );
  }

  Widget _colorSettingsPanel() {
    return _SettingsPanel(
      title: 'Цвета',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ColorTargetSelector(
            selected: _colorTarget,
            onChanged: (target) => setState(() => _colorTarget = target),
          ),
          const SizedBox(height: 12),
          _ColorTargetPreview(
            target: _colorTarget,
            settings: _settings,
            accent: _accent,
            iconGradient: _iconGradient,
          ),
          const SizedBox(height: 14),
          _GradientPicker(
            title: _colorPresetTitle(_colorTarget),
            presets: _colorPresets(_colorTarget),
            selectedIndex: _selectedColorPresetIndex(_colorTarget),
            onSelected: _applyColorPreset,
          ),
          const SizedBox(height: 12),
          ..._colorControlsForTarget(_colorTarget),
        ],
      ),
    );
  }

  Widget _themeSettingsPanel() {
    return _SettingsPanel(
      title: 'Темы',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _saveThemePreset,
                icon: const Icon(Icons.bookmark_add),
                label: const Text('Сохранить'),
              ),
              OutlinedButton.icon(
                onPressed: _copyThemeToClipboard,
                icon: const Icon(Icons.ios_share),
                label: const Text('Копировать'),
              ),
              OutlinedButton.icon(
                onPressed: _pasteThemeFromClipboard,
                icon: const Icon(Icons.content_paste),
                label: const Text('Вставить'),
              ),
            ],
          ),
          if (_themeStatus != null) ...[
            const SizedBox(height: 10),
            _StatusStrip(text: _themeStatus!, accent: _accent),
          ],
          if (_settings.savedThemes.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (var i = 0; i < _settings.savedThemes.length; i++)
              _SavedThemeTile(
                theme: _settings.savedThemes[i],
                accent: _accent,
                onApply: () => _applySavedTheme(i),
                onDelete: () => _deleteSavedTheme(i),
              ),
          ],
        ],
      ),
    );
  }

  Widget _gestureSettingsPanel() {
    return _SettingsPanel(
      title: 'Жесты',
      child: Column(
        children: [
          SwitchListTile(
            value: _settings.swipeUpOpensDrawer,
            onChanged: (value) =>
                _saveSettings(_settings.copyWith(swipeUpOpensDrawer: value)),
            title: const Text('Свайп вверх открывает приложения'),
          ),
          SwitchListTile(
            value: _settings.swipeDownOpensSearch,
            onChanged: (value) =>
                _saveSettings(_settings.copyWith(swipeDownOpensSearch: value)),
            title: const Text('Свайп вниз открывает поиск'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAppActions(InstalledApp app) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (context) {
        return _ActionSheetSurface(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: _AppIcon(
                    app: app,
                    size: 42,
                    iconPath: _iconPathFor(app),
                    iconGradient: _iconGradient,
                  ),
                  title: Text(app.label),
                  subtitle: Text(app.packageName),
                ),
                ListTile(
                  leading: const Icon(Icons.play_arrow),
                  title: const Text('Запустить'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.appsService.launch(app.packageName);
                  },
                ),
                ListTile(
                  leading: Icon(
                    app.isFavorite ? Icons.desktop_windows : Icons.add,
                  ),
                  title: Text(
                    app.isFavorite
                        ? 'Убрать с рабочего стола'
                        : 'Добавить на рабочий стол',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _toggleFavorite(app);
                  },
                ),
                ListTile(
                  leading: Icon(
                    _settings.dockPackages.contains(app.packageName)
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                  ),
                  title: Text(
                    _settings.dockPackages.contains(app.packageName)
                        ? 'Убрать из dock'
                        : 'Закрепить в dock',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _toggleDockApp(app);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.palette),
                  title: const Text('Сменить иконку'),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(_pickCustomIcon(app));
                  },
                ),
                if (_settings.customIconPaths.containsKey(app.packageName))
                  ListTile(
                    leading: const Icon(Icons.restore),
                    title: const Text('Вернуть обычную иконку'),
                    onTap: () {
                      Navigator.pop(context);
                      _saveSettings(_settings.clearCustomIcon(app.packageName));
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('О приложении'),
                  onTap: () {
                    Navigator.pop(context);
                    widget.appsService.openAppInfo(app.packageName);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickCustomIcon(InstalledApp app) async {
    try {
      final selection = await widget.wallpaperService.pickCustomIcon();
      if (selection == null || !mounted) {
        return;
      }
      await _saveSettings(
        _settings.setCustomIcon(app.packageName, selection.path),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _wallpaperStatus = 'Не удалось выбрать иконку');
      }
    }
  }

  Future<void> _pickImageWallpaper() async {
    try {
      final selection = await widget.wallpaperService.pickImageWallpaper();
      if (selection == null) {
        if (mounted) {
          setState(() => _wallpaperStatus = 'Выбор отменён');
        }
        return;
      }
      if (!mounted) {
        return;
      }

      await _saveSettings(
        _settings.copyWith(
          wallpaperType: WallpaperType.image,
          wallpaperPath: selection.path,
          wallpaperFit: 'cover',
        ),
      );
      if (mounted) {
        setState(() => _wallpaperStatus = 'Фон установлен');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _wallpaperStatus = 'Не удалось выбрать файл');
      }
    }
  }

  Future<void> _pickVideoWallpaper() async {
    try {
      final selection = await widget.wallpaperService.pickVideoWallpaper();
      if (selection == null) {
        if (mounted) {
          setState(() => _wallpaperStatus = 'Выбор отменён');
        }
        return;
      }
      if (!mounted) {
        return;
      }

      await _saveSettings(
        _settings.copyWith(
          wallpaperType: WallpaperType.video,
          wallpaperPath: selection.path,
          wallpaperFit: 'cover',
        ),
      );
      if (mounted) {
        setState(() => _wallpaperStatus = 'Видео-фон установлен');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _wallpaperStatus = 'Не удалось выбрать файл');
      }
    }
  }

  Future<void> _clearWallpaper() async {
    await _saveSettings(_settings.clearWallpaper());
    if (mounted) {
      setState(() => _wallpaperStatus = 'Фон сброшен');
    }
  }

  Future<void> _toggleDesktopGrid() async {
    await _saveSettings(
      _settings.copyWith(showDesktopGrid: !_settings.showDesktopGrid),
    );
  }

  Future<void> _moveDesktopApp(
    InstalledApp app,
    DesktopItemPosition position,
  ) async {
    await _saveSettings(
      _settings.moveDesktopApp(app.packageName, position),
      debounce: true,
    );
  }

  Future<void> _moveDesktopWidget(
    LauncherWidgetType type,
    DesktopItemPosition position,
  ) async {
    await _saveSettings(_settings.moveWidget(type, position), debounce: true);
  }

  Future<void> _removeDesktopApp(InstalledApp app) async {
    await _saveSettings(_settings.toggleDesktopApp(app.packageName));
  }

  Future<void> _removeDesktopWidget(LauncherWidgetType type) async {
    await _saveSettings(_settings.toggleWidget(type, false));
  }

  Future<void> _showDesktopActions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (context) {
        return _ActionSheetSurface(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.add_to_home_screen),
                title: const Text('Добавить приложение'),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_showAddAppToDesktopSheet());
                },
              ),
              ListTile(
                leading: const Icon(Icons.widgets),
                title: const Text('Добавить виджет'),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_showWidgetPicker());
                },
              ),
              ListTile(
                leading: Icon(
                  _settings.showDesktopGrid ? Icons.grid_off : Icons.grid_on,
                ),
                title: Text(
                  _settings.showDesktopGrid ? 'Скрыть сетку' : 'Показать сетку',
                ),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_toggleDesktopGrid());
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('Обновить приложения'),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_load());
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_add),
                title: const Text('Сохранить текущую тему'),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_saveThemePreset());
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddAppToDesktopSheet() async {
    final apps = _catalog
        .where((app) => !_settings.desktopPackages.contains(app.packageName))
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (context) {
        return _ActionSheetSurface(
          child: SizedBox(
            height: math.min(MediaQuery.sizeOf(context).height * 0.72, 520),
            child: apps.isEmpty
                ? _StatusStrip(
                    text: 'Все приложения уже на рабочем столе',
                    accent: _accent,
                  )
                : ListView.separated(
                    itemCount: apps.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      return ListTile(
                        leading: _AppIcon(
                          app: app,
                          size: 42,
                          iconPath: _iconPathFor(app),
                          iconGradient: _iconGradient,
                        ),
                        title: Text(app.label),
                        subtitle: Text(app.packageName),
                        trailing: const Icon(Icons.add),
                        onTap: () {
                          Navigator.pop(context);
                          _toggleFavorite(app);
                        },
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  Future<void> _showAddDockAppSheet() async {
    final apps = _catalog
        .where((app) => !_settings.dockPackages.contains(app.packageName))
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (context) {
        return _ActionSheetSurface(
          child: SizedBox(
            height: math.min(MediaQuery.sizeOf(context).height * 0.72, 520),
            child: apps.isEmpty
                ? _StatusStrip(
                    text: 'Все приложения уже закреплены в dock',
                    accent: _accent,
                  )
                : ListView.separated(
                    itemCount: apps.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final app = apps[index];
                      return ListTile(
                        leading: _AppIcon(
                          app: app,
                          size: 42,
                          iconPath: _iconPathFor(app),
                          iconGradient: _iconGradient,
                        ),
                        title: Text(app.label),
                        subtitle: Text(app.packageName),
                        trailing: const Icon(Icons.push_pin_outlined),
                        onTap: () {
                          Navigator.pop(context);
                          _toggleDockApp(app);
                        },
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  Future<void> _showWidgetPicker({LauncherWidgetType? replace}) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (context) {
        return _ActionSheetSurface(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final type in LauncherWidgetType.values)
                ListTile(
                  leading: Icon(_widgetIcon(type)),
                  title: Text(_widgetTitle(type)),
                  trailing: _settings.enabledWidgets.contains(type)
                      ? Icon(Icons.check, color: _accent)
                      : const Icon(Icons.add),
                  onTap: () {
                    Navigator.pop(context);
                    final next = replace == null
                        ? _settings.toggleWidget(type, true)
                        : _settings.replaceWidget(replace, type);
                    _saveSettings(next);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showWidgetActions(LauncherWidgetType type) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: true,
      builder: (context) {
        return _ActionSheetSurface(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: Icon(_widgetIcon(type)),
                title: Text(_widgetTitle(type)),
              ),
              ListTile(
                leading: const Icon(Icons.zoom_in),
                title: const Text('Увеличить'),
                onTap: () {
                  Navigator.pop(context);
                  _saveSettings(
                    _settings.copyWith(
                      widgetScale: (_settings.widgetScale + 0.1)
                          .clamp(0.75, 1.35)
                          .toDouble(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.zoom_out),
                title: const Text('Уменьшить'),
                onTap: () {
                  Navigator.pop(context);
                  _saveSettings(
                    _settings.copyWith(
                      widgetScale: (_settings.widgetScale - 0.1)
                          .clamp(0.75, 1.35)
                          .toDouble(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Заменить'),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_showWidgetPicker(replace: type));
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Убрать с рабочего стола'),
                onTap: () {
                  Navigator.pop(context);
                  _saveSettings(_settings.toggleWidget(type, false));
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveThemePreset() async {
    await _saveSettings(_settings.saveCurrentTheme());
    if (mounted) {
      setState(() => _themeStatus = 'Тема сохранена');
    }
  }

  Future<void> _copyThemeToClipboard() async {
    await Clipboard.setData(ClipboardData(text: _settings.exportTheme()));
    if (mounted) {
      setState(() => _themeStatus = 'Тема скопирована');
    }
  }

  Future<void> _pasteThemeFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final payload = data?.text;
    if (payload == null || payload.trim().isEmpty) {
      if (mounted) {
        setState(() => _themeStatus = 'В буфере нет темы');
      }
      return;
    }
    try {
      await _saveSettings(_settings.applyThemePayload(payload));
      if (mounted) {
        setState(() => _themeStatus = 'Тема применена');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _themeStatus = 'Не удалось прочитать тему');
      }
    }
  }

  Future<void> _applySavedTheme(int index) async {
    await _saveSettings(_settings.applySavedTheme(index));
    if (mounted) {
      setState(() => _themeStatus = 'Тема применена');
    }
  }

  Future<void> _deleteSavedTheme(int index) async {
    await _saveSettings(_settings.deleteSavedTheme(index));
    if (mounted) {
      setState(() => _themeStatus = 'Тема удалена');
    }
  }

  String _widgetTitle(LauncherWidgetType type) {
    return switch (type) {
      LauncherWidgetType.calendar => 'Календарь',
      LauncherWidgetType.battery => 'Статус',
      LauncherWidgetType.quickActions => 'Быстрые действия',
      LauncherWidgetType.notes => 'Заметки',
      LauncherWidgetType.clock => 'Время',
      LauncherWidgetType.weather => 'Погода',
      LauncherWidgetType.music => 'Музыка',
    };
  }

  IconData _widgetIcon(LauncherWidgetType type) {
    return switch (type) {
      LauncherWidgetType.calendar => Icons.calendar_month,
      LauncherWidgetType.battery => Icons.bolt,
      LauncherWidgetType.quickActions => Icons.dashboard_customize,
      LauncherWidgetType.notes => Icons.sticky_note_2_outlined,
      LauncherWidgetType.clock => Icons.schedule,
      LauncherWidgetType.weather => Icons.cloud_queue,
      LauncherWidgetType.music => Icons.music_note,
    };
  }

  double _gridAspectRatio(int columns) {
    return switch (columns) {
      >= 5 => 0.62,
      4 => 0.70,
      _ => 0.78,
    };
  }
}

class _ClockPanel extends StatefulWidget {
  const _ClockPanel({required this.accent, this.scale = 1.0});

  final Color accent;
  final double scale;

  @override
  State<_ClockPanel> createState() => _ClockPanelState();
}

class _ClockPanelState extends State<_ClockPanel> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _scheduleNextTick();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      alignment: Alignment.topLeft,
      fit: BoxFit.scaleDown,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _timeLabel(),
            maxLines: 1,
            style: TextStyle(
              fontSize: 64 * widget.scale,
              fontWeight: FontWeight.w800,
              height: 0.95,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _dateLabel(),
            maxLines: 1,
            style: TextStyle(
              color: widget.accent,
              fontSize: 18 * widget.scale,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String _timeLabel() {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _dateLabel() {
    const months = [
      'янв.',
      'фев.',
      'мар.',
      'апр.',
      'мая',
      'июн.',
      'июл.',
      'авг.',
      'сен.',
      'окт.',
      'ноя.',
      'дек.',
    ];
    return '${_now.day} ${months[_now.month - 1]}';
  }

  void _scheduleNextTick() {
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _timer = Timer(nextMinute.difference(now), () {
      if (!mounted) {
        return;
      }
      setState(() => _now = DateTime.now());
      _scheduleNextTick();
    });
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.accent, super.key});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: 52,
        child: CircularProgressIndicator(color: accent),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.index,
    required this.accent,
    required this.backgroundColor,
    required this.onChanged,
  });

  final int index;
  final Color accent;
  final Color backgroundColor;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: index,
      indicatorColor: accent.withValues(alpha: 0.28),
      backgroundColor: backgroundColor,
      onDestinationSelected: onChanged,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard), label: 'Главная'),
        NavigationDestination(icon: Icon(Icons.grid_view), label: 'Приложения'),
        NavigationDestination(icon: Icon(Icons.tune), label: 'Настройки'),
      ],
    );
  }
}

class _DesktopToolbar extends StatelessWidget {
  const _DesktopToolbar({
    required this.accent,
    required this.editMode,
    required this.gridEnabled,
    required this.onAddApp,
    required this.onAddWidget,
    required this.onToggleGrid,
    required this.onToggleEdit,
    required this.onDesktopActions,
  });

  final Color accent;
  final bool editMode;
  final bool gridEnabled;
  final VoidCallback onAddApp;
  final VoidCallback onAddWidget;
  final VoidCallback onToggleGrid;
  final VoidCallback onToggleEdit;
  final VoidCallback onDesktopActions;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Grisha',
                style: TextStyle(
                  color: accent,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Text(
                'Рабочий стол',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        _DesktopToolButton(
          icon: Icons.add_to_home_screen,
          tooltip: 'Добавить приложение',
          accent: accent,
          onTap: onAddApp,
        ),
        const SizedBox(width: 8),
        _DesktopToolButton(
          icon: Icons.widgets,
          tooltip: 'Добавить виджет',
          accent: accent,
          onTap: onAddWidget,
        ),
        const SizedBox(width: 8),
        _DesktopToolButton(
          icon: editMode ? Icons.check : Icons.edit,
          tooltip: editMode ? 'Готово' : 'Редактировать',
          accent: accent,
          onTap: onToggleEdit,
        ),
        const SizedBox(width: 8),
        _DesktopToolButton(
          icon: gridEnabled ? Icons.grid_off : Icons.grid_on,
          tooltip: gridEnabled ? 'Скрыть сетку' : 'Показать сетку',
          accent: accent,
          onTap: onToggleGrid,
        ),
        const SizedBox(width: 8),
        _DesktopToolButton(
          icon: Icons.more_horiz,
          tooltip: 'Действия',
          accent: accent,
          onTap: onDesktopActions,
        ),
      ],
    );
  }
}

class _DesktopToolButton extends StatelessWidget {
  const _DesktopToolButton({
    required this.icon,
    required this.tooltip,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 42,
        child: Material(
          color: const Color(0xFF171A21),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Icon(icon, color: accent),
          ),
        ),
      ),
    );
  }
}

class _RemoveDropZone extends StatelessWidget {
  const _RemoveDropZone({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final danger = Color.lerp(const Color(0xFFFF4D6D), accent, 0.08)!;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFF211418),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: danger),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline, color: Color(0xFFFF6B82)),
          SizedBox(width: 8),
          Text(
            'Убрать с рабочего стола',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _EditModeHint extends StatelessWidget {
  const _EditModeHint({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF11141A).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.edit, size: 18, color: accent),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Режим редактирования: перемещайте элементы или перетащите вниз для удаления',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockBar extends StatelessWidget {
  const _DockBar({
    required this.apps,
    required this.accent,
    required this.appFrameColor,
    required this.iconGradient,
    required this.iconPathFor,
    required this.editMode,
    required this.onLaunch,
    required this.onAppMenu,
    required this.onAddApp,
  });

  final List<InstalledApp> apps;
  final Color accent;
  final Color appFrameColor;
  final Gradient iconGradient;
  final String? Function(InstalledApp app) iconPathFor;
  final bool editMode;
  final Future<void> Function(String packageName) onLaunch;
  final ValueChanged<InstalledApp> onAppMenu;
  final VoidCallback onAddApp;

  @override
  Widget build(BuildContext context) {
    final visibleApps = apps.take(5).toList(growable: false);
    return Material(
      color: const Color(0xFF0E1117).withValues(alpha: 0.88),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: appFrameColor.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 64,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final app in visibleApps)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _DockAppButton(
                  app: app,
                  accent: accent,
                  appFrameColor: appFrameColor,
                  iconGradient: iconGradient,
                  iconPath: iconPathFor(app),
                  editMode: editMode,
                  onLaunch: onLaunch,
                  onMenu: () => onAppMenu(app),
                ),
              ),
            if (visibleApps.length < 5)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: _DockAddButton(accent: accent, onTap: onAddApp),
              ),
          ],
        ),
      ),
    );
  }
}

class _DockAppButton extends StatelessWidget {
  const _DockAppButton({
    required this.app,
    required this.accent,
    required this.appFrameColor,
    required this.iconGradient,
    required this.iconPath,
    required this.editMode,
    required this.onLaunch,
    required this.onMenu,
  });

  final InstalledApp app;
  final Color accent;
  final Color appFrameColor;
  final Gradient iconGradient;
  final String? iconPath;
  final bool editMode;
  final Future<void> Function(String packageName) onLaunch;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 160),
      scale: editMode ? 0.94 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onLaunch(app.packageName),
        onLongPress: onMenu,
        child: SizedBox.square(
          dimension: 52,
          child: Stack(
            alignment: Alignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: appFrameColor.withValues(alpha: 0.56),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: _AppIcon(
                    app: app,
                    size: 38,
                    iconPath: iconPath,
                    iconGradient: iconGradient,
                  ),
                ),
              ),
              if (editMode)
                Positioned(
                  right: 1,
                  top: 1,
                  child: Icon(Icons.push_pin, size: 13, color: accent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DockAddButton extends StatelessWidget {
  const _DockAddButton({required this.accent, required this.onTap});

  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 52,
      child: Material(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Icon(Icons.add, color: accent),
        ),
      ),
    );
  }
}

class _ActionSheetSurface extends StatelessWidget {
  const _ActionSheetSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: const Color(0xFF11141A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 14),
            child: ListTileTheme(
              iconColor: colors.primary,
              textColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              tileColor: const Color(0xFF191D25),
              selectedTileColor: colors.primary.withValues(alpha: 0.18),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopSurface extends StatefulWidget {
  const _DesktopSurface({
    required this.settings,
    required this.apps,
    required this.dockApps,
    required this.weather,
    required this.error,
    required this.accent,
    required this.iconGradient,
    required this.appFrameColor,
    required this.iconPathFor,
    required this.onLaunchApp,
    required this.onAppMenu,
    required this.onAddApp,
    required this.onAddWidget,
    required this.onAddDockApp,
    required this.onDockAppMenu,
    required this.onToggleGrid,
    required this.onDesktopActions,
    required this.onMoveApp,
    required this.onMoveWidget,
    required this.onRemoveApp,
    required this.onRemoveWidget,
    required this.onWidgetMenu,
    required this.onOpenDrawer,
    required this.onOpenSettings,
  });

  final LauncherSettings settings;
  final List<InstalledApp> apps;
  final List<InstalledApp> dockApps;
  final WeatherSnapshot? weather;
  final String? error;
  final Color accent;
  final Gradient iconGradient;
  final Color appFrameColor;
  final String? Function(InstalledApp app) iconPathFor;
  final Future<void> Function(String packageName) onLaunchApp;
  final ValueChanged<InstalledApp> onAppMenu;
  final VoidCallback onAddApp;
  final VoidCallback onAddWidget;
  final VoidCallback onAddDockApp;
  final ValueChanged<InstalledApp> onDockAppMenu;
  final VoidCallback onToggleGrid;
  final VoidCallback onDesktopActions;
  final Future<void> Function(InstalledApp app, DesktopItemPosition position)
  onMoveApp;
  final Future<void> Function(
    LauncherWidgetType type,
    DesktopItemPosition position,
  )
  onMoveWidget;
  final Future<void> Function(InstalledApp app) onRemoveApp;
  final Future<void> Function(LauncherWidgetType type) onRemoveWidget;
  final ValueChanged<LauncherWidgetType> onWidgetMenu;
  final VoidCallback onOpenDrawer;
  final VoidCallback onOpenSettings;

  @override
  State<_DesktopSurface> createState() => _DesktopSurfaceState();
}

class _DesktopSurfaceState extends State<_DesktopSurface> {
  final _surfaceKey = GlobalKey();
  bool _draggingDesktopItem = false;
  bool _editMode = false;

  @override
  Widget build(BuildContext context) {
    final widgets = widget.settings.orderedEnabledWidgets();
    final empty = widget.apps.isEmpty && widgets.isEmpty;
    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned.fill(
            top: 76,
            bottom: 82,
            child: GestureDetector(
              key: _surfaceKey,
              behavior: HitTestBehavior.opaque,
              onLongPress: _enterEditMode,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      if (widget.settings.showDesktopGrid || _editMode)
                        Positioned.fill(
                          child: _DesktopGridOverlay(
                            columns: widget.settings.gridColumns,
                            accent: _editMode
                                ? widget.appFrameColor
                                : widget.accent,
                          ),
                        ),
                      for (var i = 0; i < widgets.length; i++)
                        _buildWidgetItem(widgets[i], constraints),
                      for (var i = 0; i < widget.apps.length; i++)
                        _buildAppItem(widget.apps[i], i, constraints),
                      if (empty)
                        Positioned(
                          left: 18,
                          right: 18,
                          top: 18,
                          child: _EmptyFavorites(accent: widget.accent),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            top: 18,
            child: _DesktopToolbar(
              accent: widget.accent,
              editMode: _editMode,
              gridEnabled: widget.settings.showDesktopGrid,
              onAddApp: widget.onAddApp,
              onAddWidget: widget.onAddWidget,
              onToggleGrid: widget.onToggleGrid,
              onToggleEdit: _toggleEditMode,
              onDesktopActions: widget.onDesktopActions,
            ),
          ),
          if (_editMode && !_draggingDesktopItem)
            Positioned(
              left: 18,
              right: 18,
              bottom: 92,
              child: _EditModeHint(accent: widget.accent),
            ),
          if (widget.error != null)
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: _StatusStrip(text: widget.error!, accent: widget.accent),
            ),
          if (_draggingDesktopItem)
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: _RemoveDropZone(accent: widget.accent),
            ),
          if (!_draggingDesktopItem)
            Positioned(
              left: 18,
              right: 18,
              bottom: 16,
              child: _DockBar(
                apps: widget.dockApps,
                accent: widget.accent,
                appFrameColor: widget.appFrameColor,
                iconGradient: widget.iconGradient,
                iconPathFor: widget.iconPathFor,
                editMode: _editMode,
                onLaunch: widget.onLaunchApp,
                onAppMenu: widget.onDockAppMenu,
                onAddApp: widget.onAddDockApp,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAppItem(
    InstalledApp app,
    int index,
    BoxConstraints constraints,
  ) {
    final size = _appShortcutSize(widget.settings.iconScale);
    final position =
        widget.settings.desktopAppPositions[app.packageName] ??
        _defaultAppPosition(index);
    final offset = _offsetFor(position, size, constraints.biggest);
    final child = _DesktopAppShortcut(
      app: app,
      size: size,
      accent: widget.accent,
      iconGradient: widget.iconGradient,
      appFrameColor: widget.appFrameColor,
      iconPath: widget.iconPathFor(app),
      iconScale: widget.settings.iconScale,
      onLaunch: widget.onLaunchApp,
      onMenu: () => widget.onAppMenu(app),
    );
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: offset.dx,
      top: offset.dy,
      width: size.width,
      height: size.height,
      child: LongPressDraggable<InstalledApp>(
        data: app,
        maxSimultaneousDrags: 1,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox.fromSize(size: size, child: child),
        ),
        childWhenDragging: Opacity(opacity: 0.32, child: child),
        onDragStarted: _startDesktopDrag,
        onDragEnd: (details) {
          _finishDesktopDrag();
          if (_isRemoveDrop(details.offset, size)) {
            unawaited(widget.onRemoveApp(app));
          } else {
            widget.onMoveApp(
              app,
              _positionFromGlobal(
                details.offset,
                size,
                movingKey: _desktopAppKey(app.packageName),
              ),
            );
          }
        },
        onDraggableCanceled: (_, _) => _finishDesktopDrag(),
        child: child,
      ),
    );
  }

  Widget _buildWidgetItem(LauncherWidgetType type, BoxConstraints constraints) {
    final size = _widgetSize(type, widget.settings.widgetScale);
    final position =
        widget.settings.widgetPositions[type] ??
        defaultWidgetPositions[type] ??
        const DesktopItemPosition(x: 0.04, y: 0.04);
    final offset = _offsetFor(position, size, constraints.biggest);
    final child = _DesktopWidgetTile(
      type: type,
      size: size,
      accent: widget.accent,
      onMenu: () => widget.onWidgetMenu(type),
      child: _widgetChild(type, math.min(widget.settings.widgetScale, 1.16)),
    );
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: offset.dx,
      top: offset.dy,
      width: size.width,
      height: size.height,
      child: LongPressDraggable<LauncherWidgetType>(
        data: type,
        maxSimultaneousDrags: 1,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox.fromSize(size: size, child: child),
        ),
        childWhenDragging: Opacity(opacity: 0.32, child: child),
        onDragStarted: _startDesktopDrag,
        onDragEnd: (details) {
          _finishDesktopDrag();
          if (_isRemoveDrop(details.offset, size)) {
            unawaited(widget.onRemoveWidget(type));
          } else {
            widget.onMoveWidget(
              type,
              _positionFromGlobal(
                details.offset,
                size,
                movingKey: _desktopWidgetKey(type),
              ),
            );
          }
        },
        onDraggableCanceled: (_, _) => _finishDesktopDrag(),
        child: child,
      ),
    );
  }

  Widget _widgetChild(LauncherWidgetType type, double scale) {
    return switch (type) {
      LauncherWidgetType.clock => _ClockPanel(
        accent: widget.accent,
        scale: scale,
      ),
      LauncherWidgetType.weather => _WeatherWidgetBody(
        weather: widget.weather,
        accent: widget.accent,
        scale: scale,
      ),
      LauncherWidgetType.music => _MusicPanel(
        accent: widget.accent,
        scale: scale,
      ),
      LauncherWidgetType.calendar => _CalendarWidgetBody(
        accent: widget.accent,
        scale: scale,
      ),
      LauncherWidgetType.battery => _StatusWidgetBody(
        accent: widget.accent,
        scale: scale,
      ),
      LauncherWidgetType.quickActions => _QuickActionsWidgetBody(
        accent: widget.accent,
        scale: scale,
        onOpenDrawer: widget.onOpenDrawer,
        onOpenSettings: widget.onOpenSettings,
        onAddApp: widget.onAddApp,
      ),
      LauncherWidgetType.notes => _NotesWidgetBody(
        accent: widget.accent,
        scale: scale,
      ),
    };
  }

  Size _appShortcutSize(double scale) {
    final safeScale = scale.clamp(0.75, 1.35).toDouble();
    return Size(74 * safeScale, 96 * safeScale);
  }

  Size _widgetSize(LauncherWidgetType type, double scale) {
    final safeScale = scale.clamp(0.75, 1.35).toDouble();
    final base = switch (type) {
      LauncherWidgetType.clock => const Size(224, 148),
      LauncherWidgetType.weather => const Size(158, 148),
      LauncherWidgetType.music => const Size(248, 148),
      LauncherWidgetType.calendar => const Size(186, 148),
      LauncherWidgetType.battery => const Size(176, 140),
      LauncherWidgetType.quickActions => const Size(252, 132),
      LauncherWidgetType.notes => const Size(220, 158),
    };
    return Size(base.width * safeScale, base.height * safeScale);
  }

  void _startDesktopDrag() {
    if (mounted) {
      setState(() => _draggingDesktopItem = true);
    }
  }

  void _finishDesktopDrag() {
    if (mounted && _draggingDesktopItem) {
      setState(() => _draggingDesktopItem = false);
    }
  }

  bool _isRemoveDrop(Offset globalOffset, Size itemSize) {
    final context = _surfaceKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox) {
      return false;
    }
    final center = renderObject.globalToLocal(
      globalOffset + Offset(itemSize.width / 2, itemSize.height / 2),
    );
    return center.dy > renderObject.size.height - 96;
  }

  void _enterEditMode() {
    HapticFeedback.selectionClick();
    if (mounted && !_editMode) {
      setState(() => _editMode = true);
    }
  }

  void _toggleEditMode() {
    HapticFeedback.selectionClick();
    if (mounted) {
      setState(() => _editMode = !_editMode);
    }
  }

  DesktopItemPosition _defaultAppPosition(int index) {
    final columns = widget.settings.gridColumns.clamp(3, 5).toInt();
    final column = index % columns;
    final row = index ~/ columns;
    return DesktopItemPosition(
      x: columns <= 1 ? 0 : column / (columns - 1),
      y: (0.56 + row * 0.18).clamp(0.0, 1.0).toDouble(),
    );
  }

  Offset _offsetFor(
    DesktopItemPosition position,
    Size itemSize,
    Size areaSize,
  ) {
    final maxX = math.max(0.0, areaSize.width - itemSize.width);
    final maxY = math.max(0.0, areaSize.height - itemSize.height);
    final normalized = position.normalized();
    return Offset(maxX * normalized.x, maxY * normalized.y);
  }

  DesktopItemPosition _positionFromGlobal(
    Offset globalOffset,
    Size itemSize, {
    required String movingKey,
  }) {
    final context = _surfaceKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox) {
      return const DesktopItemPosition(x: 0, y: 0);
    }
    final local = renderObject.globalToLocal(globalOffset);
    final areaSize = renderObject.size;
    final snapped = widget.settings.showDesktopGrid
        ? _nearestFreeGridOffset(
            _snapOffsetToGrid(local, itemSize, areaSize),
            itemSize,
            areaSize,
            movingKey,
          )
        : _clampOffset(local, itemSize, areaSize);
    final maxX = math.max(1.0, areaSize.width - itemSize.width);
    final maxY = math.max(1.0, areaSize.height - itemSize.height);
    return DesktopItemPosition(
      x: (snapped.dx / maxX).clamp(0.0, 1.0).toDouble(),
      y: (snapped.dy / maxY).clamp(0.0, 1.0).toDouble(),
    );
  }

  Offset _nearestFreeGridOffset(
    Offset preferred,
    Size itemSize,
    Size areaSize,
    String movingKey,
  ) {
    final occupied = _desktopOccupants(areaSize, movingKey);
    if (_isFreeOffset(preferred, itemSize, occupied)) {
      return preferred;
    }

    final columns = widget.settings.gridColumns.clamp(3, 5).toInt();
    final rows = math.max(
      5,
      (areaSize.height / (areaSize.width / columns)).ceil(),
    );
    final cellWidth = areaSize.width / columns;
    final cellHeight = areaSize.height / rows;
    final candidates = <Offset>[];
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        candidates.add(
          _clampOffset(
            Offset(
              column * cellWidth + (cellWidth - itemSize.width) / 2,
              row * cellHeight + (cellHeight - itemSize.height) / 2,
            ),
            itemSize,
            areaSize,
          ),
        );
      }
    }
    candidates.sort(
      (a, b) => (a - preferred).distanceSquared.compareTo(
        (b - preferred).distanceSquared,
      ),
    );
    for (final candidate in candidates) {
      if (_isFreeOffset(candidate, itemSize, occupied)) {
        return candidate;
      }
    }
    return _clampOffset(preferred, itemSize, areaSize);
  }

  bool _isFreeOffset(
    Offset offset,
    Size itemSize,
    List<_DesktopOccupant> occupied,
  ) {
    final rect = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      itemSize.width,
      itemSize.height,
    ).deflate(4);
    return occupied.every((item) => !item.rect.overlaps(rect));
  }

  List<_DesktopOccupant> _desktopOccupants(Size areaSize, String movingKey) {
    final occupants = <_DesktopOccupant>[];
    final widgets = widget.settings.orderedEnabledWidgets();
    for (final type in widgets) {
      final key = _desktopWidgetKey(type);
      if (key == movingKey) {
        continue;
      }
      final size = _widgetSize(type, widget.settings.widgetScale);
      final position =
          widget.settings.widgetPositions[type] ??
          defaultWidgetPositions[type] ??
          const DesktopItemPosition(x: 0.04, y: 0.04);
      occupants.add(
        _DesktopOccupant(
          Rect.fromLTWH(
            _offsetFor(position, size, areaSize).dx,
            _offsetFor(position, size, areaSize).dy,
            size.width,
            size.height,
          ).deflate(4),
        ),
      );
    }

    for (var i = 0; i < widget.apps.length; i++) {
      final app = widget.apps[i];
      final key = _desktopAppKey(app.packageName);
      if (key == movingKey) {
        continue;
      }
      final size = _appShortcutSize(widget.settings.iconScale);
      final position =
          widget.settings.desktopAppPositions[app.packageName] ??
          _defaultAppPosition(i);
      final offset = _offsetFor(position, size, areaSize);
      occupants.add(
        _DesktopOccupant(
          Rect.fromLTWH(
            offset.dx,
            offset.dy,
            size.width,
            size.height,
          ).deflate(4),
        ),
      );
    }
    return occupants;
  }

  Offset _clampOffset(Offset offset, Size itemSize, Size areaSize) {
    return Offset(
      offset.dx
          .clamp(0.0, math.max(0.0, areaSize.width - itemSize.width))
          .toDouble(),
      offset.dy
          .clamp(0.0, math.max(0.0, areaSize.height - itemSize.height))
          .toDouble(),
    );
  }

  Offset _snapOffsetToGrid(Offset offset, Size itemSize, Size areaSize) {
    final columns = widget.settings.gridColumns.clamp(3, 5).toInt();
    final rows = math.max(
      5,
      (areaSize.height / (areaSize.width / columns)).ceil(),
    );
    final cellWidth = areaSize.width / columns;
    final cellHeight = areaSize.height / rows;
    final center = offset + Offset(itemSize.width / 2, itemSize.height / 2);
    final column = (center.dx / cellWidth).floor().clamp(0, columns - 1);
    final row = (center.dy / cellHeight).floor().clamp(0, rows - 1);
    final left = column * cellWidth + (cellWidth - itemSize.width) / 2;
    final top = row * cellHeight + (cellHeight - itemSize.height) / 2;
    return Offset(
      left
          .clamp(0.0, math.max(0.0, areaSize.width - itemSize.width))
          .toDouble(),
      top
          .clamp(0.0, math.max(0.0, areaSize.height - itemSize.height))
          .toDouble(),
    );
  }
}

class _DesktopOccupant {
  const _DesktopOccupant(this.rect);

  final Rect rect;
}

String _desktopAppKey(String packageName) => 'app:$packageName';

String _desktopWidgetKey(LauncherWidgetType type) => 'widget:${type.name}';

class _DesktopAppShortcut extends StatelessWidget {
  const _DesktopAppShortcut({
    required this.app,
    required this.size,
    required this.accent,
    required this.iconGradient,
    required this.appFrameColor,
    required this.iconPath,
    required this.iconScale,
    required this.onLaunch,
    required this.onMenu,
  });

  final InstalledApp app;
  final Size size;
  final Color accent;
  final Gradient iconGradient;
  final Color appFrameColor;
  final String? iconPath;
  final double iconScale;
  final Future<void> Function(String packageName) onLaunch;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final frameColor = appFrameColor.withValues(alpha: 0.78);
    final iconSize = math.min(size.width * 0.72, 54 * iconScale);
    return Material(
      color: Colors.black.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: frameColor, width: 1.15),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onLaunch(app.packageName),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 8, 5, 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _AppIcon(
                    app: app,
                    size: iconSize,
                    iconPath: iconPath,
                    iconGradient: iconGradient,
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    height: 28,
                    child: Text(
                      app.label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      strutStyle: const StrutStyle(
                        fontSize: 11,
                        height: 1.08,
                        forceStrutHeight: true,
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        height: 1.08,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: -1,
              top: -1,
              child: SizedBox.square(
                dimension: 24,
                child: IconButton(
                  tooltip: 'Приложение',
                  padding: EdgeInsets.zero,
                  onPressed: onMenu,
                  icon: const Icon(Icons.more_vert, size: 15),
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopWidgetTile extends StatelessWidget {
  const _DesktopWidgetTile({
    required this.type,
    required this.size,
    required this.accent,
    required this.onMenu,
    required this.child,
  });

  final LauncherWidgetType type;
  final Size size;
  final Color accent;
  final VoidCallback onMenu;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tone = _widgetTone(type, accent);
    return SizedBox.fromSize(
      size: size,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tone.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tone.border),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(padding: const EdgeInsets.all(14), child: child),
              ),
              Positioned(
                right: 2,
                top: 2,
                child: IconButton(
                  tooltip: 'Виджет',
                  onPressed: onMenu,
                  icon: const Icon(Icons.more_vert),
                  color: tone.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

({Color background, Color border, Color foreground}) _widgetTone(
  LauncherWidgetType type,
  Color accent,
) {
  return switch (type) {
    LauncherWidgetType.clock => (
      background: const Color(0xFF111821),
      border: accent.withValues(alpha: 0.28),
      foreground: accent,
    ),
    LauncherWidgetType.weather => (
      background: const Color(0xFF12211E),
      border: const Color(0xFF2E7D6B),
      foreground: const Color(0xFF38E0BF),
    ),
    LauncherWidgetType.music => (
      background: const Color(0xFF201722),
      border: const Color(0xFF884D9E),
      foreground: const Color(0xFFE47CFF),
    ),
    LauncherWidgetType.calendar => (
      background: const Color(0xFF211A12),
      border: const Color(0xFFA86B2B),
      foreground: const Color(0xFFFFB15E),
    ),
    LauncherWidgetType.battery => (
      background: const Color(0xFF132016),
      border: const Color(0xFF4B8E56),
      foreground: const Color(0xFF86EF95),
    ),
    LauncherWidgetType.quickActions => (
      background: const Color(0xFF171A21),
      border: accent.withValues(alpha: 0.34),
      foreground: accent,
    ),
    LauncherWidgetType.notes => (
      background: const Color(0xFF1E1D12),
      border: const Color(0xFF9B8C31),
      foreground: const Color(0xFFF4DD5A),
    ),
  };
}

class _DesktopGridOverlay extends StatelessWidget {
  const _DesktopGridOverlay({required this.columns, required this.accent});

  final int columns;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _DesktopGridPainter(columns: columns, accent: accent),
      ),
    );
  }
}

class _DesktopGridPainter extends CustomPainter {
  const _DesktopGridPainter({required this.columns, required this.accent});

  final int columns;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    final safeColumns = columns.clamp(3, 5);
    final rows = math.max(5, (size.height / (size.width / safeColumns)).ceil());
    final cellWidth = size.width / safeColumns;
    final cellHeight = size.height / rows;
    for (var column = 1; column < safeColumns; column++) {
      final x = column * cellWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var row = 1; row < rows; row++) {
      final y = row * cellHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DesktopGridPainter oldDelegate) {
    return oldDelegate.columns != columns || oldDelegate.accent != accent;
  }
}

class _MusicPanel extends StatelessWidget {
  const _MusicPanel({required this.accent, required this.scale});

  final Color accent;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.music_note, color: accent, size: 22 * scale),
            SizedBox(width: 8 * scale),
            Expanded(
              child: Text(
                'Музыка',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 10 * scale),
        Text(
          'Не играет',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 13 * scale,
          ),
        ),
        SizedBox(height: 10 * scale),
        Row(
          children: [
            _MusicControl(
              icon: Icons.skip_previous,
              accent: accent,
              scale: scale,
            ),
            SizedBox(width: 8 * scale),
            _MusicControl(icon: Icons.play_arrow, accent: accent, scale: scale),
            SizedBox(width: 8 * scale),
            _MusicControl(icon: Icons.skip_next, accent: accent, scale: scale),
          ],
        ),
      ],
    );
  }
}

class _MusicControl extends StatelessWidget {
  const _MusicControl({
    required this.icon,
    required this.accent,
    required this.scale,
  });

  final IconData icon;
  final Color accent;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 34 * scale,
      child: Material(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {},
          child: Icon(icon, color: accent, size: 18 * scale),
        ),
      ),
    );
  }
}

class _WeatherWidgetBody extends StatelessWidget {
  const _WeatherWidgetBody({
    required this.weather,
    required this.accent,
    required this.scale,
  });

  final WeatherSnapshot? weather;
  final Color accent;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final snapshot = weather;
    final temp = snapshot?.temperatureCelsius;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.cloud_queue, color: accent, size: 24 * scale),
        SizedBox(height: 8 * scale),
        Text(
          temp == null ? '-- C' : '${temp.round()} C',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 24 * scale, fontWeight: FontWeight.w800),
        ),
        Text(
          snapshot?.conditionLabel ?? 'Загрузка',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
        ),
      ],
    );
  }
}

class _CalendarWidgetBody extends StatelessWidget {
  const _CalendarWidgetBody({required this.accent, required this.scale});

  final Color accent;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.calendar_month, color: accent, size: 22 * scale),
            SizedBox(width: 8 * scale),
            Expanded(
              child: Text(
                'Календарь',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const Spacer(),
        Text(
          now.day.toString().padLeft(2, '0'),
          style: TextStyle(
            fontSize: 44 * scale,
            height: 0.9,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 4 * scale),
        Text(
          weekdays[now.weekday - 1],
          style: TextStyle(
            color: accent,
            fontSize: 16 * scale,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _StatusWidgetBody extends StatelessWidget {
  const _StatusWidgetBody({required this.accent, required this.scale});

  final Color accent;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      alignment: Alignment.topLeft,
      fit: BoxFit.scaleDown,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt, color: accent, size: 24 * scale),
          SizedBox(height: 10 * scale),
          Text(
            'Статус',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 18 * scale, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 6 * scale),
          Text(
            'Лаунчер активен',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 12 * scale,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsWidgetBody extends StatelessWidget {
  const _QuickActionsWidgetBody({
    required this.accent,
    required this.scale,
    required this.onOpenDrawer,
    required this.onOpenSettings,
    required this.onAddApp,
  });

  final Color accent;
  final double scale;
  final VoidCallback onOpenDrawer;
  final VoidCallback onOpenSettings;
  final VoidCallback onAddApp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Быстро',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 16 * scale, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 12 * scale),
        Wrap(
          spacing: 8 * scale,
          runSpacing: 8 * scale,
          children: [
            _QuickActionButton(
              icon: Icons.apps,
              accent: accent,
              onTap: onOpenDrawer,
            ),
            _QuickActionButton(
              icon: Icons.add_to_home_screen,
              accent: accent,
              onTap: onAddApp,
            ),
            _QuickActionButton(
              icon: Icons.tune,
              accent: accent,
              onTap: onOpenSettings,
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 42,
      child: Material(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Icon(icon, color: accent),
        ),
      ),
    );
  }
}

class _NotesWidgetBody extends StatelessWidget {
  const _NotesWidgetBody({required this.accent, required this.scale});

  final Color accent;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.sticky_note_2_outlined, color: accent, size: 22 * scale),
            SizedBox(width: 8 * scale),
            Expanded(
              child: Text(
                'Заметки',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12 * scale),
        Text(
          '• Удерживай элементы, чтобы двигать',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12 * scale, height: 1.2),
        ),
        SizedBox(height: 6 * scale),
        Text(
          '• Настрой тему и сохрани пресет',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 12 * scale,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          count.toString(),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
        ),
      ],
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.accent,
    required this.iconGradient,
    required this.appFrameColor,
    required this.iconPath,
    required this.iconScale,
    required this.onLaunch,
    required this.onLongPress,
  });

  final InstalledApp app;
  final Color accent;
  final Gradient iconGradient;
  final Color appFrameColor;
  final String? iconPath;
  final double iconScale;
  final Future<void> Function(String packageName) onLaunch;
  final ValueChanged<InstalledApp> onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: app.isFavorite
          ? appFrameColor.withValues(alpha: 0.13)
          : Colors.black.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: app.isFavorite
              ? appFrameColor.withValues(alpha: 0.78)
              : appFrameColor.withValues(alpha: 0.34),
          width: app.isFavorite ? 1.2 : 0.9,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onLaunch(app.packageName),
        onLongPress: () => onLongPress(app),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = math.max(44.0, constraints.maxWidth - 12);
            final contentHeight = math.max(44.0, constraints.maxHeight - 12);
            final labelHeight = math.min(
              32.0,
              math.max(18.0, contentHeight * 0.28),
            );
            final gap = math.min(6.0, math.max(3.0, contentHeight * 0.04));
            final maxIconSize = math.max(
              20.0,
              math.min(contentWidth * 0.74, contentHeight - labelHeight - gap),
            );
            final scaleProgress = ((iconScale - 0.75) / 0.60).clamp(0.0, 1.0);
            final iconSize = maxIconSize * (0.74 + 0.26 * scaleProgress);
            final labelFontSize = math.min(
              12.0,
              math.max(9.0, labelHeight / 2.3),
            );
            return Padding(
              padding: const EdgeInsets.all(6),
              child: SizedBox(
                width: contentWidth,
                height: contentHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _AppIcon(
                          app: app,
                          size: iconSize,
                          iconPath: iconPath,
                          iconGradient: iconGradient,
                        ),
                        if (app.isFavorite)
                          Positioned(
                            right: -5,
                            top: -5,
                            child: Icon(Icons.star, size: 17, color: accent),
                          ),
                      ],
                    ),
                    SizedBox(height: gap),
                    SizedBox(
                      height: labelHeight,
                      child: Text(
                        app.label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        strutStyle: StrutStyle(
                          fontSize: labelFontSize,
                          height: 1.08,
                          forceStrutHeight: true,
                        ),
                        style: TextStyle(
                          fontSize: labelFontSize,
                          fontWeight: FontWeight.w700,
                          height: 1.08,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({
    required this.app,
    required this.size,
    required this.iconPath,
    required this.iconGradient,
  });

  final InstalledApp app;
  final double size;
  final String? iconPath;
  final Gradient iconGradient;

  @override
  Widget build(BuildContext context) {
    final icon = app.iconBytes;
    if (icon != null && icon.isNotEmpty) {
      return _IconImage(icon: icon, size: size, gradient: iconGradient);
    }

    final path = iconPath;
    if (path != null && path.isNotEmpty) {
      return _FileIconImage(
        path: path,
        size: size,
        gradient: iconGradient,
        fallbackLabel: app.label,
      );
    }

    return _AppIconPlaceholder(
      label: app.label,
      size: size,
      gradient: iconGradient,
    );
  }
}

class _AppIconPlaceholder extends StatelessWidget {
  const _AppIconPlaceholder({
    required this.label,
    required this.size,
    required this.gradient,
  });

  final String label;
  final double size;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return _IconPlate(
      size: size,
      gradient: gradient,
      child: Text(
        label.characters.firstOrNull?.toUpperCase() ?? '?',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _FileIconImage extends StatelessWidget {
  const _FileIconImage({
    required this.path,
    required this.size,
    required this.gradient,
    required this.fallbackLabel,
  });

  final String path;
  final double size;
  final Gradient gradient;
  final String fallbackLabel;

  @override
  Widget build(BuildContext context) {
    return _IconPlate(
      key: const Key('file-app-icon'),
      size: size,
      gradient: gradient,
      child: Padding(
        padding: EdgeInsets.all(math.max(3, size * 0.08)),
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          gaplessPlayback: true,
          cacheWidth: size.round(),
          cacheHeight: size.round(),
          errorBuilder: (_, _, _) {
            return Center(
              child: Text(
                fallbackLabel.characters.firstOrNull?.toUpperCase() ?? '?',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _IconImage extends StatelessWidget {
  const _IconImage({
    required this.icon,
    required this.size,
    required this.gradient,
  });

  final Uint8List icon;
  final double size;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return _IconPlate(
      size: size,
      gradient: gradient,
      child: Padding(
        padding: EdgeInsets.all(math.max(3, size * 0.08)),
        child: Image.memory(
          icon,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          cacheWidth: size.round(),
          cacheHeight: size.round(),
        ),
      ),
    );
  }
}

class _IconPlate extends StatelessWidget {
  const _IconPlate({
    required this.size,
    required this.gradient,
    required this.child,
    super.key,
  });

  final double size;
  final Gradient gradient;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(math.max(10, size * 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _ColorTargetSelector extends StatelessWidget {
  const _ColorTargetSelector({required this.selected, required this.onChanged});

  final _ColorTarget selected;
  final ValueChanged<_ColorTarget> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final target in _ColorTarget.values)
          ChoiceChip(
            selected: selected == target,
            avatar: Icon(_colorTargetIcon(target), size: 18),
            label: Text(_colorTargetLabel(target)),
            onSelected: (_) => onChanged(target),
          ),
      ],
    );
  }
}

String _colorTargetLabel(_ColorTarget target) {
  return switch (target) {
    _ColorTarget.accent => 'Акцент',
    _ColorTarget.desktop => 'Стол',
    _ColorTarget.drawer => 'Каталог',
    _ColorTarget.icons => 'Иконки',
    _ColorTarget.frames => 'Рамки',
  };
}

IconData _colorTargetIcon(_ColorTarget target) {
  return switch (target) {
    _ColorTarget.accent => Icons.bolt,
    _ColorTarget.desktop => Icons.wallpaper,
    _ColorTarget.drawer => Icons.grid_view,
    _ColorTarget.icons => Icons.apps,
    _ColorTarget.frames => Icons.crop_square,
  };
}

class _ColorTargetPreview extends StatelessWidget {
  const _ColorTargetPreview({
    required this.target,
    required this.settings,
    required this.accent,
    required this.iconGradient,
  });

  final _ColorTarget target;
  final LauncherSettings settings;
  final Color accent;
  final Gradient iconGradient;

  @override
  Widget build(BuildContext context) {
    final title = switch (target) {
      _ColorTarget.accent => 'Меняется акцент кнопок и выделения',
      _ColorTarget.desktop => 'Меняется градиент рабочего стола',
      _ColorTarget.drawer => 'Меняется фон экрана приложений',
      _ColorTarget.icons => 'Меняется цвет подложки иконок',
      _ColorTarget.frames => 'Меняется окантовка приложений',
    };
    final decoration = switch (target) {
      _ColorTarget.accent => BoxDecoration(
        color: accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent),
      ),
      _ColorTarget.desktop => BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(settings.backgroundStartColorValue),
            Color(settings.backgroundEndColorValue),
          ],
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      _ColorTarget.drawer => BoxDecoration(
        color: Color(settings.drawerBackgroundColorValue),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      _ColorTarget.icons => BoxDecoration(
        gradient: iconGradient,
        borderRadius: BorderRadius.circular(8),
      ),
      _ColorTarget.frames => BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Color(settings.appFrameColorValue), width: 2),
      ),
    };
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: decoration,
      child: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _GradientPicker extends StatelessWidget {
  const _GradientPicker({
    required this.title,
    required this.presets,
    required this.selectedIndex,
    required this.onSelected,
  });

  final String title;
  final List<LauncherGradientPreset> presets;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < presets.length; i++)
              Tooltip(
                message: presets[i].name,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelected(i),
                  child: Container(
                    width: 56,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: launcherGradient(presets[i]),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: i == selectedIndex ? Colors.white : Colors.black,
                        width: i == selectedIndex ? 3 : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ColorControl extends StatelessWidget {
  const _ColorControl({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final Color value;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final rgb = _rgbFromColor(value);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: value,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '#${_colorToInt(value).toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          _RgbSlider(
            label: 'R',
            value: rgb.$1,
            color: Colors.redAccent,
            onChanged: (next) => onChanged(_colorFromRgb(next, rgb.$2, rgb.$3)),
          ),
          _RgbSlider(
            label: 'G',
            value: rgb.$2,
            color: Colors.greenAccent,
            onChanged: (next) => onChanged(_colorFromRgb(rgb.$1, next, rgb.$3)),
          ),
          _RgbSlider(
            label: 'B',
            value: rgb.$3,
            color: Colors.lightBlueAccent,
            onChanged: (next) => onChanged(_colorFromRgb(rgb.$1, rgb.$2, next)),
          ),
        ],
      ),
    );
  }
}

class _RgbSlider extends StatelessWidget {
  const _RgbSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(label, style: TextStyle(color: color)),
        ),
        Expanded(
          child: Slider(
            min: 0,
            max: 255,
            divisions: 255,
            value: value.toDouble(),
            activeColor: color,
            onChanged: (next) => onChanged(next.round()),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            value.toString(),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _SavedThemeTile extends StatelessWidget {
  const _SavedThemeTile({
    required this.theme,
    required this.accent,
    required this.onApply,
    required this.onDelete,
  });

  final SavedLauncherTheme theme;
  final Color accent;
  final VoidCallback onApply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.palette, color: accent),
      title: Text(theme.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            tooltip: 'Применить',
            onPressed: onApply,
            icon: const Icon(Icons.check),
          ),
          IconButton(
            tooltip: 'Удалить',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _WallpaperSummary extends StatelessWidget {
  const _WallpaperSummary({required this.type, required this.accent});

  final WallpaperType type;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final text = switch (type) {
      WallpaperType.image => 'Сейчас: фото из галереи',
      WallpaperType.video => 'Сейчас: видео-обои',
      WallpaperType.none => 'Сейчас: стандартный фон',
    };
    final icon = switch (type) {
      WallpaperType.image => Icons.image,
      WallpaperType.video => Icons.video_library,
      WallpaperType.none => Icons.gradient,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.38)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _LauncherStatusStrip extends StatelessWidget {
  const _LauncherStatusStrip({
    required this.isDefault,
    required this.loading,
    required this.accent,
  });

  final bool? isDefault;
  final bool loading;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final selected = isDefault == true;
    final text = loading
        ? 'Проверяем статус...'
        : selected
        ? 'Уже выбран как лаунчер'
        : 'Не выбран как лаунчер';
    final icon = selected ? Icons.check_circle : Icons.info_outline;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: selected ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.34)),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _XiaomiLauncherHint extends StatelessWidget {
  const _XiaomiLauncherHint({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.phone_android, color: accent, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Xiaomi/HyperOS: если экран не открылся, откройте Настройки > '
              'Приложения > Приложения по умолчанию > Рабочий стол и выберите '
              'Grisha Launcher. Samsung: откройте Настройки > Приложения > '
              'Выбор приложений по умолчанию > Главный экран.',
              style: TextStyle(height: 1.25),
            ),
          ),
        ],
      ),
    );
  }
}

class _WallpaperActionTile extends StatelessWidget {
  const _WallpaperActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: accent),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Icon(Icons.chevron_right, color: accent),
      onTap: onTap,
    );
  }
}

class _ScaleSlider extends StatelessWidget {
  const _ScaleSlider({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text('${(value * 100).round()}%'),
          ],
        ),
        Slider(
          min: 0.75,
          max: 1.35,
          divisions: 12,
          value: value.clamp(0.75, 1.35).toDouble(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SettingsTabSelector extends StatelessWidget {
  const _SettingsTabSelector({required this.selected, required this.onChanged});

  final _SettingsTab selected;
  final ValueChanged<_SettingsTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in _SettingsTab.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: selected == tab,
                avatar: Icon(_settingsTabIcon(tab), size: 18),
                label: Text(_settingsTabLabel(tab)),
                onSelected: (_) => onChanged(tab),
              ),
            ),
        ],
      ),
    );
  }
}

String _settingsTabLabel(_SettingsTab tab) {
  return switch (tab) {
    _SettingsTab.view => 'Вид',
    _SettingsTab.desktop => 'Стол',
    _SettingsTab.motion => 'Плавность',
    _SettingsTab.themes => 'Темы',
    _SettingsTab.system => 'Система',
  };
}

IconData _settingsTabIcon(_SettingsTab tab) {
  return switch (tab) {
    _SettingsTab.view => Icons.palette,
    _SettingsTab.desktop => Icons.dashboard_customize,
    _SettingsTab.motion => Icons.speed,
    _SettingsTab.themes => Icons.bookmarks,
    _SettingsTab.system => Icons.settings_applications,
  };
}

class _QualityProfilePicker extends StatelessWidget {
  const _QualityProfilePicker({required this.value, required this.onChanged});

  final LauncherQualityProfile value;
  final ValueChanged<LauncherQualityProfile> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Профиль качества',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final profile in LauncherQualityProfile.values)
              ChoiceChip(
                selected: value == profile,
                avatar: Icon(_qualityProfileIcon(profile), size: 18),
                label: Text(_qualityProfileLabel(profile)),
                onSelected: (_) => onChanged(profile),
              ),
          ],
        ),
      ],
    );
  }
}

String _qualityProfileLabel(LauncherQualityProfile profile) {
  return switch (profile) {
    LauncherQualityProfile.smooth => 'Плавность',
    LauncherQualityProfile.balanced => 'Баланс',
    LauncherQualityProfile.beautiful => 'Красиво',
    LauncherQualityProfile.saver => 'Экономия',
  };
}

IconData _qualityProfileIcon(LauncherQualityProfile profile) {
  return switch (profile) {
    LauncherQualityProfile.smooth => Icons.speed,
    LauncherQualityProfile.balanced => Icons.tune,
    LauncherQualityProfile.beautiful => Icons.auto_awesome,
    LauncherQualityProfile.saver => Icons.battery_saver,
  };
}

class _TransitionStylePicker extends StatelessWidget {
  const _TransitionStylePicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final LauncherTransitionStyle value;
  final bool enabled;
  final ValueChanged<LauncherTransitionStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.46,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Анимация свайпа',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in LauncherTransitionStyle.values)
                  ChoiceChip(
                    selected: value == style,
                    avatar: Icon(_transitionIcon(style), size: 18),
                    label: Text(_transitionLabel(style)),
                    onSelected: (_) => onChanged(style),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _transitionLabel(LauncherTransitionStyle style) {
  return switch (style) {
    LauncherTransitionStyle.smooth => 'Плавная',
    LauncherTransitionStyle.slide => 'Слайд',
    LauncherTransitionStyle.zoom => 'Зум',
    LauncherTransitionStyle.scale => 'Масштаб',
    LauncherTransitionStyle.fade => 'Fade',
    LauncherTransitionStyle.none => 'Нет',
  };
}

IconData _transitionIcon(LauncherTransitionStyle style) {
  return switch (style) {
    LauncherTransitionStyle.smooth => Icons.auto_awesome_motion,
    LauncherTransitionStyle.slide => Icons.swipe,
    LauncherTransitionStyle.zoom => Icons.zoom_in_map,
    LauncherTransitionStyle.scale => Icons.open_in_full,
    LauncherTransitionStyle.fade => Icons.blur_on,
    LauncherTransitionStyle.none => Icons.block,
  };
}

class _WidgetSwitch extends StatelessWidget {
  const _WidgetSwitch({
    required this.title,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon),
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF171A21),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, textAlign: TextAlign.center),
    );
  }
}

class _EmptyFavorites extends StatelessWidget {
  const _EmptyFavorites({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return _StatusStrip(
      text:
          'Зажмите рабочий стол или приложение в каталоге, чтобы добавить ярлык',
      accent: accent,
    );
  }
}
