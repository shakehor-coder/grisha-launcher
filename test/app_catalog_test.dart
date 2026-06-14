import 'package:flutter_test/flutter_test.dart';
import 'package:grisha_launcher/models/installed_app.dart';
import 'package:grisha_launcher/state/app_catalog.dart';

void main() {
  const apps = [
    InstalledApp(
      label: 'Chrome',
      packageName: 'com.android.chrome',
      iconBytes: null,
      isSystem: false,
      category: 'Приложения',
    ),
    InstalledApp(
      label: 'Calculator',
      packageName: 'com.android.calculator2',
      iconBytes: null,
      isSystem: true,
      category: 'Работа',
    ),
  ];

  test('избранное сортируется перед остальным каталогом', () {
    final sorted = applyFavorites(apps, {'com.android.chrome'});

    expect(sorted.first.label, 'Chrome');
    expect(sorted.first.isFavorite, isTrue);
  });

  test('поиск работает по названиям и package names', () {
    expect(filterApps(apps, 'calc').single.label, 'Calculator');
    expect(filterApps(apps, 'chrome').single.packageName, 'com.android.chrome');
  });

  test('категории включают Все и найденные русские категории', () {
    expect(appCategories(apps), ['Все', 'Приложения', 'Работа']);
  });
}
