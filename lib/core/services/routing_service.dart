import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Résultat d'un calcul d'itinéraire
class RouteResult {
  final int index; // Index de la route (0 = principale, 1+ = alternatives)
  final double distanceMeters;
  final double durationSeconds;
  final List<LatLng> geometry;
  final String summary;

  /// true = ligne droite (OSRM indisponible) : distance sous-estimée.
  final bool isFallback;

  RouteResult({
    this.index = 0,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.geometry,
    required this.summary,
    this.isFallback = false,
  });

  /// Distance en kilomètres
  double get distanceKm => distanceMeters / 1000;

  /// Durée en minutes
  double get durationMinutes => durationSeconds / 60;

  /// Temps estimé à pied (~5 km/h - comme Google Maps)
  Duration get walkingTime {
    final hours = distanceKm / 5;
    return Duration(hours: hours.floor(), minutes: ((hours % 1) * 60).round());
  }

  /// Temps estimé à moto (~40 km/h - comme Google Maps pour deux-roues)
  Duration get motorcycleTime {
    final hours = distanceKm / 40;
    return Duration(hours: hours.floor(), minutes: ((hours % 1) * 60).round());
  }

  /// Temps estimé en voiture (~50 km/h - comme Google Maps en ville)
  Duration get carTime {
    final hours = distanceKm / 50;
    return Duration(hours: hours.floor(), minutes: ((hours % 1) * 60).round());
  }

  /// Formatage du temps (ex: "12 min")
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}min';
    }
    return '${minutes}min';
  }

  /// Formatage de la durée pour affichage court
  String get formattedDuration {
    final minutes = durationMinutes.round();
    if (minutes < 60) return '$minutes min';
    final hours = (minutes / 60).floor();
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) return '${hours}h';
    return '${hours}h ${remainingMinutes}min';
  }

  /// Copie avec de nouveaux paramètres potentiels
  RouteResult copyWith({
    int? index,
    bool? isFallback,
  }) {
    return RouteResult(
      index: index ?? this.index,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      geometry: geometry,
      summary: summary,
      isFallback: isFallback ?? this.isFallback,
    );
  }
}

/// Service de calcul d'itinéraires utilisant OSRM (Open Source Routing Machine)
/// API gratuite, pas de clé requise
class RoutingService {
  static const String _baseUrl = 'https://router.project-osrm.org/route/v1';

  /// Calcule un itinéraire entre deux points
  ///
  /// [origin] Point de départ
  /// [destination] Point d'arrivée
  /// [profile] Profil de transport: 'driving', 'walking', 'cycling'
  /// [alternatives] Nombre maximum d'itinéraires alternatifs à retourner (0 = aucun)
  ///
  /// Retourne une liste de RouteResult (le premier est le meilleur)
  Future<List<RouteResult>> getRoutes({
    required LatLng origin,
    required LatLng destination,
    String profile = 'driving',
    int alternatives = 2, // Demande jusqu'à 2 alternatives
  }) async {
    try {
      // Construction de l'URL OSRM avec alternatives
      // OSRM retourne naturellement plusieurs routes si disponibles
      final url = Uri.parse(
        '$_baseUrl/$profile/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}?overview=full&geometries=geojson&alternatives=${alternatives > 0 ? 'true' : 'false'}',
      );

      final response = await http.get(url).timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Timeout du service de routing'),
          );

      if (response.statusCode != 200) {
        throw Exception('Erreur OSRM: ${response.statusCode}');
      }

      final data = json.decode(response.body);

      if (data['code'] != 'Ok' ||
          data['routes'] == null ||
          data['routes'].isEmpty) {
        throw Exception('Aucun itinéraire trouvé');
      }

      final routes = data['routes'] as List;
      final results = <RouteResult>[];

      for (var i = 0; i < routes.length; i++) {
        final route = routes[i];
        final geometry = route['geometry'];

        // Conversion GeoJSON → Liste de LatLng
        final coordinates = geometry['coordinates'] as List;
        final points = coordinates.map((coord) {
          return LatLng(coord[1] as double, coord[0] as double);
        }).toList();

        final distance = route['distance'] as double;
        results.add(RouteResult(
          index: i,
          distanceMeters: distance,
          durationSeconds: route['duration'] as double,
          geometry: points,
          summary: '${(distance / 1000).toStringAsFixed(1)} km',
          isFallback: false, // Par défaut, ce n'est pas un fallback
        ));
      }

      // Trier par durée (le plus rapide en premier)
      results.sort((a, b) => a.durationSeconds.compareTo(b.durationSeconds));

      // Réattribuer les index après tri
      for (var i = 0; i < results.length; i++) {
        results[i] = results[i].copyWith(index: i);
      }

      return results;
    } catch (e) {
      // En cas d'erreur, retourne un itinéraire simplifié (ligne droite)
      return [_createDirectRoute(origin, destination)];
    }
  }

  /// Calcule un itinéraire (retourne uniquement le meilleur)
  /// Méthode conservée pour compatibilité
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    String profile = 'driving',
  }) async {
    final routes = await getRoutes(
      origin: origin,
      destination: destination,
      profile: profile,
      alternatives: 0,
    );
    return routes.first;
  }

  /// Crée un itinéraire direct (ligne droite) en cas d'erreur OSRM
  RouteResult _createDirectRoute(LatLng origin, LatLng destination) {
    // Calcul de la distance à vol d'oiseau (formule de Haversine)
    final distance = _haversineDistance(origin, destination);

    // Durée estimée en voiture (50 km/h)
    final durationHours = distance / 50;
    final durationSeconds = durationHours * 3600;

    return RouteResult(
      index: 0,
      distanceMeters: distance * 1000,
      durationSeconds: durationSeconds,
      geometry: [origin, destination],
      summary: '${distance.toStringAsFixed(1)} km (à vol d\'oiseau)',
      isFallback: true,
    );
  }

  /// Calcule la distance entre deux points (formule de Haversine)
  double _haversineDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // km

    final lat1 = point1.latitude * (math.pi / 180);
    final lat2 = point2.latitude * (math.pi / 180);
    final deltaLat = (point2.latitude - point1.latitude) * (math.pi / 180);
    final deltaLon = (point2.longitude - point1.longitude) * (math.pi / 180);

    final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);

    final c = 2 * math.asin(math.sqrt(a));

    return earthRadius * c;
  }

  /// Calcule la distance à vol d'oiseau entre deux points
  double calculateDistance(LatLng point1, LatLng point2) {
    return _haversineDistance(point1, point2);
  }
}
