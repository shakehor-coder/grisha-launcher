import 'dart:typed_data';

class InstalledApp {
  const InstalledApp({
    required this.label,
    required this.packageName,
    required this.iconBytes,
    required this.isSystem,
    required this.category,
    this.isFavorite = false,
  });

  final String label;
  final String packageName;
  final Uint8List? iconBytes;
  final bool isSystem;
  final String category;
  final bool isFavorite;

  factory InstalledApp.fromMap(Map<Object?, Object?> map) {
    final icon = map['iconBytes'];
    return InstalledApp(
      label: map['label'] as String? ?? 'Unknown',
      packageName: map['packageName'] as String? ?? '',
      iconBytes: icon is Uint8List
          ? icon
          : icon is List<int>
          ? Uint8List.fromList(icon)
          : null,
      isSystem: map['isSystem'] as bool? ?? false,
      category: map['category'] as String? ?? 'Приложения',
    );
  }

  InstalledApp copyWith({bool? isFavorite}) {
    return InstalledApp(
      label: label,
      packageName: packageName,
      iconBytes: iconBytes,
      isSystem: isSystem,
      category: category,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    return label.toLowerCase().contains(normalized) ||
        packageName.toLowerCase().contains(normalized) ||
        category.toLowerCase().contains(normalized);
  }
}
