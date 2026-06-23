import 'package:flutter/material.dart';

class LauncherGradientPreset {
  const LauncherGradientPreset({required this.name, required this.colors});

  final String name;
  final List<Color> colors;
}

const launcherAccentPresets = [
  LauncherGradientPreset(
    name: 'Кибер',
    colors: [Color(0xFF19E6D2), Color(0xFF4F8CFF)],
  ),
  LauncherGradientPreset(
    name: 'Огонь',
    colors: [Color(0xFFFF4D6D), Color(0xFFFFA24D)],
  ),
  LauncherGradientPreset(
    name: 'Лайм',
    colors: [Color(0xFF8AF26E), Color(0xFF18D8A7)],
  ),
  LauncherGradientPreset(
    name: 'Неон',
    colors: [Color(0xFFB76BFF), Color(0xFFFF4FD8)],
  ),
];

const launcherBackgroundPresets = [
  LauncherGradientPreset(
    name: 'Графит',
    colors: [Color(0xFF101116), Color(0xFF1C1F27), Color(0xFF0A0B0F)],
  ),
  LauncherGradientPreset(
    name: 'Красный',
    colors: [Color(0xFF141114), Color(0xFF3A111B), Color(0xFF0C0D10)],
  ),
  LauncherGradientPreset(
    name: 'Лед',
    colors: [Color(0xFF07151A), Color(0xFF123744), Color(0xFF050A10)],
  ),
  LauncherGradientPreset(
    name: 'Плазма',
    colors: [Color(0xFF15101D), Color(0xFF321C4F), Color(0xFF100A13)],
  ),
];

const launcherIconPresets = [
  LauncherGradientPreset(
    name: 'Красный',
    colors: [Color(0xFFE72E45), Color(0xFF8B1020)],
  ),
  LauncherGradientPreset(
    name: 'Бирюза',
    colors: [Color(0xFF19D6C8), Color(0xFF116BFF)],
  ),
  LauncherGradientPreset(
    name: 'Золото',
    colors: [Color(0xFFFFD166), Color(0xFFB55C17)],
  ),
  LauncherGradientPreset(
    name: 'Моно',
    colors: [Color(0xFF2A2D35), Color(0xFF15171D)],
  ),
];

int normalizePresetIndex(int index, int length) {
  if (length <= 0) {
    return 0;
  }
  return index.abs() % length;
}

Color launcherAccentColor(int index) {
  final preset =
      launcherAccentPresets[normalizePresetIndex(
        index,
        launcherAccentPresets.length,
      )];
  return preset.colors.first;
}

LinearGradient launcherGradient(LauncherGradientPreset preset) {
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: preset.colors,
  );
}
