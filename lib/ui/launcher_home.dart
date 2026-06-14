import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/installed_app.dart';
import '../models/launcher_settings.dart';
import '../models/weather_snapshot.dart';
import '../services/app_icon_repository.dart';
import '../services/installed_apps_service.dart';
import '../services/settings_repository.dart';
import '../services/weather_service.dart';
import '../state/app_catalog.dart';

class LauncherHome extends StatefulWidget {
  const LauncherHome({
    required this.appsService,
    required this.settingsRepository,
    required this.weatherService,
    super.key,
  });

  final InstalledAppsService appsService;
  final SettingsRepository settingsRepository;
  final WeatherService weatherService;

  @override
  State<LauncherHome> createState() => _LauncherHomeState();
}

class _LauncherHomeState extends State<LauncherHome> {
  static const _accents = [
    Color(0xFF11D9C5),
    Color(0xFFFFC857),
    Color(0xFFFF4D6D),
    Color(0xFF8AF26E),
  ];

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  late final AppIconRepository _iconRepository;
  LauncherSettings _settings = const LauncherSettings();
  WeatherSnapshot? _weather;
  List<InstalledApp> _apps = const [];
  List<InstalledApp> _catalog = const [];
  List<InstalledApp> _favorites = const [];
  List<InstalledApp> _visibleApps = const [];
  List<String> _categories = const ['Все'];
  String _category = 'Все';
  int _pageIndex = 0;
  bool _loading = true;
  String? _error;

  Color get _accent => _accents[_settings.accentIndex % _accents.length];

  @override
  void initState() {
    super.initState();
    _iconRepository = AppIconRepository(widget.appsService);
    _searchController.addListener(_handleSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait<Object>([
        widget.settingsRepository.load(),
        widget.appsService.loadApps(),
      ]);

      setState(() {
        _settings = results[0] as LauncherSettings;
        _apps = results[1] as List<InstalledApp>;
        _iconRepository.clear();
        _refreshDerivedState();
        _loading = false;
      });
      unawaited(_loadWeather());
    } catch (error) {
      setState(() {
        _loading = false;
        _error = 'Служба лаунчера недоступна';
      });
    }
  }

  Future<void> _loadWeather() async {
    final weather = await widget.weatherService.loadCurrentWeatherByLocation();
    if (mounted) {
      setState(() => _weather = weather);
    }
  }

  Future<void> _saveSettings(LauncherSettings settings) async {
    setState(() {
      _settings = settings;
      _refreshDerivedState();
    });
    await widget.settingsRepository.save(settings);
  }

  Future<void> _toggleFavorite(InstalledApp app) async {
    final favorites = {..._settings.favoritePackages};
    if (!favorites.add(app.packageName)) {
      favorites.remove(app.packageName);
    }
    await _saveSettings(_settings.copyWith(favoritePackages: favorites));
  }

  void _openDrawer({bool focusSearch = false}) {
    setState(() => _pageIndex = 1);
    if (focusSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    }
  }

  void _handleSearchChanged() {
    setState(() => _visibleApps = _filteredVisibleApps());
  }

  void _refreshDerivedState() {
    _catalog = applyFavorites(_apps, _settings.favoritePackages);
    _favorites = _catalog.where((app) => app.isFavorite).take(8).toList();
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

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -260 && _settings.swipeUpOpensDrawer) {
      _openDrawer();
    }
    if (velocity > 260 && _settings.swipeDownOpensSearch) {
      _openDrawer(focusSearch: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragEnd: _handleDragEnd,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF080A10), Color(0xFF111827), Color(0xFF170B1A)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _loading
                        ? _LoadingView(accent: _accent)
                        : IndexedStack(
                            key: ValueKey(_pageIndex),
                            index: _pageIndex,
                            children: [
                              _buildHome(),
                              _buildDrawer(),
                              _buildSettings(),
                            ],
                          ),
                  ),
                ),
                _BottomNav(
                  index: _pageIndex,
                  accent: _accent,
                  onChanged: (index) => setState(() => _pageIndex = index),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHome() {
    final weather = _weather;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_ClockPanel(accent: _accent)],
                ),
              ),
              _WeatherPanel(weather: weather, accent: _accent),
            ],
          ),
          const SizedBox(height: 24),
          _QuickActions(
            accent: _accent,
            onSearch: () => _openDrawer(focusSearch: true),
            onApps: _openDrawer,
            onSettings: () => setState(() => _pageIndex = 2),
            onRefresh: _load,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _StatusStrip(text: _error!, accent: _accent),
          ],
          const SizedBox(height: 24),
          _SectionHeader(title: 'Избранное', count: _favorites.length),
          const SizedBox(height: 12),
          if (_favorites.isEmpty)
            _EmptyFavorites(accent: _accent)
          else
            _AppGrid(
              apps: _favorites,
              columns: math.min(_settings.gridColumns, 4),
              accent: _accent,
              iconRepository: _iconRepository,
              onLaunch: widget.appsService.launch,
              onLongPress: _showAppActions,
            ),
          const SizedBox(height: 24),
          _SectionHeader(title: 'Каталог', count: _catalog.length),
          const SizedBox(height: 12),
          _AppGrid(
            apps: _catalog.take(8).toList(),
            columns: math.min(_settings.gridColumns, 4),
            accent: _accent,
            iconRepository: _iconRepository,
            onLaunch: widget.appsService.launch,
            onLongPress: _showAppActions,
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    final categories = _categories;

    return Column(
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
              fillColor: Colors.white.withValues(alpha: 0.08),
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
                onSelected: (_) => setState(() => _category = category),
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
                      iconRepository: _iconRepository,
                      onLaunch: widget.appsService.launch,
                      onLongPress: _showAppActions,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSettings() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
      children: [
        const Text(
          'Настройки',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 18),
        _SettingsPanel(
          title: 'Плотность сетки',
          child: SegmentedButton<int>(
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
        ),
        const SizedBox(height: 12),
        _SettingsPanel(
          title: 'Акцент',
          child: Wrap(
            spacing: 12,
            children: [
              for (var i = 0; i < _accents.length; i++)
                Tooltip(
                  message: 'Акцент ${i + 1}',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () =>
                        _saveSettings(_settings.copyWith(accentIndex: i)),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _accents[i],
                        border: Border.all(
                          color: i == _settings.accentIndex
                              ? Colors.white
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SettingsPanel(
          title: 'Жесты',
          child: Column(
            children: [
              SwitchListTile(
                value: _settings.swipeUpOpensDrawer,
                onChanged: (value) => _saveSettings(
                  _settings.copyWith(swipeUpOpensDrawer: value),
                ),
                title: const Text('Свайп вверх открывает приложения'),
              ),
              SwitchListTile(
                value: _settings.swipeDownOpensSearch,
                onChanged: (value) => _saveSettings(
                  _settings.copyWith(swipeDownOpensSearch: value),
                ),
                title: const Text('Свайп вниз открывает поиск'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showAppActions(InstalledApp app) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: _AppIcon(
                  app: app,
                  size: 42,
                  iconRepository: _iconRepository,
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
                leading: Icon(app.isFavorite ? Icons.star : Icons.star_border),
                title: Text(
                  app.isFavorite ? 'Убрать из избранного' : 'В избранное',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _toggleFavorite(app);
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
        );
      },
    );
  }

  double _gridAspectRatio(int columns) {
    return switch (columns) {
      >= 5 => 0.72,
      4 => 0.76,
      _ => 0.82,
    };
  }
}

class _ClockPanel extends StatefulWidget {
  const _ClockPanel({required this.accent});

  final Color accent;

  @override
  State<_ClockPanel> createState() => _ClockPanelState();
}

class _ClockPanelState extends State<_ClockPanel> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _timeLabel(),
          style: const TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w800,
            height: 0.95,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _dateLabel(),
          style: TextStyle(
            color: widget.accent,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.accent});

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
    required this.onChanged,
  });

  final int index;
  final Color accent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: index,
      indicatorColor: accent.withValues(alpha: 0.28),
      backgroundColor: Colors.black.withValues(alpha: 0.2),
      onDestinationSelected: onChanged,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.dashboard), label: 'Главная'),
        NavigationDestination(icon: Icon(Icons.grid_view), label: 'Приложения'),
        NavigationDestination(icon: Icon(Icons.tune), label: 'Настройки'),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.accent,
    required this.onSearch,
    required this.onApps,
    required this.onSettings,
    required this.onRefresh,
  });

  final Color accent;
  final VoidCallback onSearch;
  final VoidCallback onApps;
  final VoidCallback onSettings;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ActionButton(icon: Icons.search, label: 'Поиск', onTap: onSearch),
        const SizedBox(width: 10),
        _ActionButton(icon: Icons.apps, label: 'Все', onTap: onApps),
        const SizedBox(width: 10),
        _ActionButton(icon: Icons.tune, label: 'Вид', onTap: onSettings),
        const SizedBox(width: 10),
        _ActionButton(
          icon: Icons.refresh,
          label: 'Обновить',
          onTap: onRefresh,
          accent: accent,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: FittedBox(child: Text(label)),
        style: FilledButton.styleFrom(
          backgroundColor: accent ?? Colors.white.withValues(alpha: 0.11),
          foregroundColor: accent == null ? Colors.white : Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          minimumSize: const Size(0, 48),
        ),
      ),
    );
  }
}

class _WeatherPanel extends StatelessWidget {
  const _WeatherPanel({required this.weather, required this.accent});

  final WeatherSnapshot? weather;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final snapshot = weather;
    final temp = snapshot?.temperatureCelsius;
    return Container(
      width: 126,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_queue, color: accent),
          const SizedBox(height: 8),
          Text(
            temp == null ? '-- C' : '${temp.round()} C',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          Text(
            snapshot?.conditionLabel ?? 'Загрузка',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.68)),
          ),
        ],
      ),
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

class _AppGrid extends StatelessWidget {
  const _AppGrid({
    required this.apps,
    required this.columns,
    required this.accent,
    required this.iconRepository,
    required this.onLaunch,
    required this.onLongPress,
  });

  final List<InstalledApp> apps;
  final int columns;
  final Color accent;
  final AppIconRepository iconRepository;
  final Future<void> Function(String packageName) onLaunch;
  final ValueChanged<InstalledApp> onLongPress;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: switch (columns) {
          >= 5 => 0.72,
          4 => 0.76,
          _ => 0.82,
        },
      ),
      itemCount: apps.length,
      itemBuilder: (context, index) {
        final app = apps[index];
        return _AppTile(
          app: app,
          accent: accent,
          iconRepository: iconRepository,
          onLaunch: onLaunch,
          onLongPress: onLongPress,
        );
      },
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.app,
    required this.accent,
    required this.iconRepository,
    required this.onLaunch,
    required this.onLongPress,
  });

  final InstalledApp app;
  final Color accent;
  final AppIconRepository iconRepository;
  final Future<void> Function(String packageName) onLaunch;
  final ValueChanged<InstalledApp> onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: app.isFavorite ? 0.13 : 0.07),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onLaunch(app.packageName),
        onLongPress: () => onLongPress(app),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final iconSize = math.min(46.0, constraints.maxHeight * 0.42);
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _AppIcon(
                        app: app,
                        size: iconSize,
                        iconRepository: iconRepository,
                      ),
                      if (app.isFavorite)
                        Positioned(
                          right: -5,
                          top: -5,
                          child: Icon(Icons.star, size: 17, color: accent),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    height: 31,
                    child: Text(
                      app.label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.18,
                      ),
                    ),
                  ),
                ],
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
    required this.iconRepository,
  });

  final InstalledApp app;
  final double size;
  final AppIconRepository iconRepository;

  @override
  Widget build(BuildContext context) {
    final icon = app.iconBytes;
    if (icon != null && icon.isNotEmpty) {
      return _IconImage(icon: icon, size: size);
    }

    final placeholder = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.13),
      ),
      child: Text(
        app.label.characters.firstOrNull?.toUpperCase() ?? '?',
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );

    return FutureBuilder(
      future: iconRepository.loadIcon(app.packageName, sizePx: size.round()),
      builder: (context, snapshot) {
        final loadedIcon = snapshot.data;
        if (loadedIcon == null || loadedIcon.isEmpty) {
          return placeholder;
        }
        return _IconImage(icon: loadedIcon, size: size);
      },
    );
  }
}

class _IconImage extends StatelessWidget {
  const _IconImage({required this.icon, required this.size});

  final Uint8List icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.memory(
        icon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        cacheWidth: size.round(),
        cacheHeight: size.round(),
      ),
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
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
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
      text: 'Зажмите приложение, чтобы добавить его сюда',
      accent: accent,
    );
  }
}
