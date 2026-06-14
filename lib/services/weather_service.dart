import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../models/weather_snapshot.dart';

abstract class WeatherService {
  Future<WeatherSnapshot> loadCurrentWeatherByLocation();
}

class OpenMeteoWeatherService implements WeatherService {
  OpenMeteoWeatherService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<WeatherSnapshot> loadCurrentWeatherByLocation() async {
    try {
      final permission = await _ensurePermission();
      if (!permission) {
        return WeatherSnapshot.fallback('Геолокация выключена');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': position.latitude.toStringAsFixed(4),
        'longitude': position.longitude.toStringAsFixed(4),
        'current': 'temperature_2m,weather_code',
        'timezone': 'auto',
      });
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        return WeatherSnapshot.fallback('Погода недоступна');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final current = json['current'] as Map<String, dynamic>?;
      return WeatherSnapshot(
        temperatureCelsius: (current?['temperature_2m'] as num?)?.toDouble(),
        conditionCode: (current?['weather_code'] as num?)?.toInt(),
        updatedAt: DateTime.now(),
        placeLabel:
            '${position.latitude.toStringAsFixed(2)}, ${position.longitude.toStringAsFixed(2)}',
      );
    } catch (_) {
      return WeatherSnapshot.fallback('Погода офлайн');
    }
  }

  Future<bool> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}
