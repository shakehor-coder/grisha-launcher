class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureCelsius,
    required this.conditionCode,
    required this.updatedAt,
    this.placeLabel,
    this.message,
  });

  final double? temperatureCelsius;
  final int? conditionCode;
  final DateTime updatedAt;
  final String? placeLabel;
  final String? message;

  bool get hasWeather => temperatureCelsius != null && conditionCode != null;

  String get conditionLabel {
    return switch (conditionCode) {
      0 => 'Ясно',
      1 || 2 => 'Облачно',
      3 => 'Пасмурно',
      45 || 48 => 'Туман',
      51 || 53 || 55 || 61 || 63 || 65 => 'Дождь',
      71 || 73 || 75 || 77 => 'Снег',
      80 || 81 || 82 => 'Ливень',
      95 || 96 || 99 => 'Гроза',
      _ => message ?? 'Погода недоступна',
    };
  }

  static WeatherSnapshot fallback(String message) {
    return WeatherSnapshot(
      temperatureCelsius: null,
      conditionCode: null,
      updatedAt: DateTime.now(),
      message: message,
    );
  }
}
