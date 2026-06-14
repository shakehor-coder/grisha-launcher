import '../models/installed_app.dart';

List<InstalledApp> applyFavorites(
  List<InstalledApp> apps,
  Set<String> favoritePackages,
) {
  return apps
      .map(
        (app) => app.copyWith(
          isFavorite: favoritePackages.contains(app.packageName),
        ),
      )
      .toList()
    ..sort(compareApps);
}

List<InstalledApp> filterApps(List<InstalledApp> apps, String query) {
  return apps.where((app) => app.matches(query)).toList();
}

List<String> appCategories(List<InstalledApp> apps) {
  final categories = apps.map((app) => app.category).toSet().toList()..sort();
  return ['Все', ...categories];
}

int compareApps(InstalledApp a, InstalledApp b) {
  if (a.isFavorite != b.isFavorite) {
    return a.isFavorite ? -1 : 1;
  }
  return a.label.toLowerCase().compareTo(b.label.toLowerCase());
}
