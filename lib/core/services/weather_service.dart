import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// Conditions météorologiques.
enum WeatherCondition {
  sunny,
  partlyCloudy,
  cloudy,
  rainy,
  stormy,
  hot,
  windy,
  foggy,
  snowy,
  unknown,
}

/// Levée quand aucune météo réelle n'est disponible (hors ligne, service
/// indisponible). Il n'y a volontairement AUCUNE donnée inventée : mieux vaut
/// ne rien afficher qu'une fausse température.
class WeatherUnavailable implements Exception {
  const WeatherUnavailable([this.message = 'Météo indisponible']);
  final String message;
  @override
  String toString() => message;
}

/// Données météorologiques réelles (source : Open-Meteo, couverture mondiale).
class WeatherData {
  final double temperature;
  final double feelsLike;
  final int humidity;

  /// km/h
  final double windSpeed;

  /// Direction d'où vient le vent, en degrés (0 = nord), si connue.
  final double? windDirection;

  /// Précipitations en mm sur l'heure courante.
  final double precipitation;

  final bool isDay;
  final String description;
  final WeatherCondition condition;
  final String? iconCode;
  final DateTime timestamp;

  WeatherData({
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.description,
    required this.condition,
    this.iconCode,
    required this.timestamp,
    this.windDirection,
    this.precipitation = 0,
    this.isDay = true,
  });

  String get temperatureString => '${temperature.round()}°C';
  String get feelsLikeString => 'Ressenti ${feelsLike.round()}°C';
  String get windSpeedString => '${windSpeed.round()} km/h';

  /// « NE », « SO »… (point cardinal d'où vient le vent).
  String? get windCompass {
    final d = windDirection;
    if (d == null) return null;
    const pts = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
    return pts[((d % 360) / 45).round() % 8];
  }

  String get conditionEmoji {
    switch (condition) {
      case WeatherCondition.sunny:
        return isDay ? '☀️' : '🌙';
      case WeatherCondition.partlyCloudy:
        return isDay ? '⛅' : '☁️';
      case WeatherCondition.cloudy:
        return '☁️';
      case WeatherCondition.rainy:
        return '🌧️';
      case WeatherCondition.stormy:
        return '⛈️';
      case WeatherCondition.hot:
        return '🥵';
      case WeatherCondition.windy:
        return '💨';
      case WeatherCondition.foggy:
        return '🌫️';
      case WeatherCondition.snowy:
        return '❄️';
      case WeatherCondition.unknown:
        return '🌡️';
    }
  }

  bool get isHot => temperature >= 35;
  bool get isRaining =>
      condition == WeatherCondition.rainy ||
      condition == WeatherCondition.stormy;
}

/// Météo réelle via Open-Meteo : gratuit, sans clé, valable partout dans le
/// monde. Cache mémoire (10 min par zone d'environ 1 km) et requêtes
/// identiques regroupées pour ne pas solliciter le réseau à chaque
/// déplacement de la carte.
class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  /// Compatibilité avec l'ancien code `WeatherService()`.
  factory WeatherService() => instance;

  static const _host = 'api.open-meteo.com';
  static const _ttl = Duration(minutes: 10);

  final Map<String, ({WeatherData data, DateTime at})> _cache = {};
  final Map<String, Future<WeatherData>> _inFlight = {};

  static String _key(double lat, double lon) =>
      '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';

  /// Dernière valeur connue (même ancienne) pour afficher quelque chose
  /// instantanément pendant l'actualisation.
  WeatherData? cached(double latitude, double longitude) =>
      _cache[_key(latitude, longitude)]?.data;

  /// Lève [WeatherUnavailable] s'il n'y a ni réseau ni valeur en cache.
  Future<WeatherData> getWeather({
    required double latitude,
    required double longitude,
    String units = 'metric',
    bool forceRefresh = false,
  }) {
    final key = _key(latitude, longitude);
    final hit = _cache[key];
    if (!forceRefresh &&
        hit != null &&
        DateTime.now().difference(hit.at) < _ttl) {
      return Future.value(hit.data);
    }
    return _inFlight[key] ??= _fetch(
      latitude,
      longitude,
      key,
      units,
    ).whenComplete(() => _inFlight.remove(key));
  }

  /// Variante qui ne lève jamais : renvoie null si rien n'est disponible.
  Future<WeatherData?> tryGetWeather({
    required double latitude,
    required double longitude,
    bool forceRefresh = false,
  }) async {
    try {
      return await getWeather(
        latitude: latitude,
        longitude: longitude,
        forceRefresh: forceRefresh,
      );
    } catch (_) {
      return null;
    }
  }

  Future<WeatherData> _fetch(
    double lat,
    double lon,
    String key,
    String units,
  ) async {
    final fahrenheit = units == 'imperial';
    final uri = Uri.https(_host, '/v1/forecast', {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'current':
          'temperature_2m,relative_humidity_2m,apparent_temperature,'
          'is_day,precipitation,weather_code,wind_speed_10m,wind_direction_10m',
      'wind_speed_unit': 'kmh',
      'temperature_unit': fahrenheit ? 'fahrenheit' : 'celsius',
      'timezone': 'auto',
    });

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw WeatherUnavailable('Service météo (${response.statusCode})');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = _parse(json);
      _cache[key] = (data: data, at: DateTime.now());
      return data;
    } catch (_) {
      // Réseau coupé : on préfère une valeur un peu ancienne à rien du tout.
      final old = _cache[key];
      if (old != null) return old.data;
      throw const WeatherUnavailable();
    }
  }

  WeatherData _parse(Map<String, dynamic> json) {
    final c = json['current'] as Map<String, dynamic>?;
    if (c == null) throw const WeatherUnavailable();

    double num0(String k) => (c[k] as num?)?.toDouble() ?? 0;

    final temp = num0('temperature_2m');
    final code = (c['weather_code'] as num?)?.toInt() ?? -1;
    final wind = num0('wind_speed_10m');
    final isDay = (c['is_day'] as num?)?.toInt() != 0;

    var condition = _conditionFromWmo(code);
    if (condition == WeatherCondition.sunny && temp >= 35) {
      condition = WeatherCondition.hot;
    } else if ((condition == WeatherCondition.sunny ||
            condition == WeatherCondition.partlyCloudy) &&
        wind >= 45) {
      condition = WeatherCondition.windy;
    }

    return WeatherData(
      temperature: temp,
      feelsLike: (c['apparent_temperature'] as num?)?.toDouble() ?? temp,
      humidity: (c['relative_humidity_2m'] as num?)?.round() ?? 0,
      windSpeed: wind,
      windDirection: (c['wind_direction_10m'] as num?)?.toDouble(),
      precipitation: num0('precipitation'),
      isDay: isDay,
      description: _descriptionFr(code, condition, isDay),
      condition: condition,
      iconCode: '$code',
      timestamp: DateTime.now(),
    );
  }

  /// Codes WMO (https://open-meteo.com/en/docs#weather_variable_documentation).
  static WeatherCondition _conditionFromWmo(int code) {
    if (code == 0 || code == 1) return WeatherCondition.sunny;
    if (code == 2) return WeatherCondition.partlyCloudy;
    if (code == 3) return WeatherCondition.cloudy;
    if (code == 45 || code == 48) return WeatherCondition.foggy;
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
      return WeatherCondition.rainy;
    }
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
      return WeatherCondition.snowy;
    }
    if (code >= 95) return WeatherCondition.stormy;
    return WeatherCondition.unknown;
  }

  static String _descriptionFr(int code, WeatherCondition c, bool isDay) {
    switch (code) {
      case 0:
        return isDay ? 'Ciel dégagé' : 'Nuit claire';
      case 1:
        return isDay ? 'Plutôt ensoleillé' : 'Plutôt dégagé';
      case 2:
        return 'Partiellement nuageux';
      case 3:
        return 'Couvert';
      case 45:
      case 48:
        return 'Brouillard';
      case 51:
      case 53:
      case 55:
        return 'Bruine';
      case 56:
      case 57:
        return 'Bruine verglaçante';
      case 61:
        return 'Pluie faible';
      case 63:
        return 'Pluie';
      case 65:
        return 'Forte pluie';
      case 66:
      case 67:
        return 'Pluie verglaçante';
      case 71:
      case 73:
      case 75:
      case 77:
        return 'Neige';
      case 80:
      case 81:
        return 'Averses';
      case 82:
        return 'Fortes averses';
      case 85:
      case 86:
        return 'Averses de neige';
      case 95:
        return 'Orage';
      case 96:
      case 99:
        return 'Orage avec grêle';
    }
    switch (c) {
      case WeatherCondition.hot:
        return 'Très chaud';
      case WeatherCondition.windy:
        return 'Venteux';
      default:
        return 'Variable';
    }
  }

  /// Distance approximative en km (pour décider d'un rafraîchissement).
  static double kmBetween(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLon = rad(lon2 - lon1);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.sqrt(a.toDouble()));
  }
}
