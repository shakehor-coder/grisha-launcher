class LauncherSettings {
  const LauncherSettings({
    this.favoritePackages = const <String>{},
    this.gridColumns = 4,
    this.accentIndex = 0,
    this.swipeUpOpensDrawer = true,
    this.swipeDownOpensSearch = true,
  });

  final Set<String> favoritePackages;
  final int gridColumns;
  final int accentIndex;
  final bool swipeUpOpensDrawer;
  final bool swipeDownOpensSearch;

  LauncherSettings copyWith({
    Set<String>? favoritePackages,
    int? gridColumns,
    int? accentIndex,
    bool? swipeUpOpensDrawer,
    bool? swipeDownOpensSearch,
  }) {
    return LauncherSettings(
      favoritePackages: favoritePackages ?? this.favoritePackages,
      gridColumns: gridColumns ?? this.gridColumns,
      accentIndex: accentIndex ?? this.accentIndex,
      swipeUpOpensDrawer: swipeUpOpensDrawer ?? this.swipeUpOpensDrawer,
      swipeDownOpensSearch: swipeDownOpensSearch ?? this.swipeDownOpensSearch,
    );
  }
}
