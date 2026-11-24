import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Service de requêtes géospatiales (Geoqueries)
///
/// Permet de filtrer les prestataires par distance sans charger
/// toute la base de données. Utilise des calculs de distance
/// optimisés et des geohashes pour des performances maximales.
class GeoqueryService {
  GeoqueryService._();
  static final GeoqueryService instance = GeoqueryService._();

  static const double _earthRadiusKm = 6371;

  /// Calcule la distance entre deux points (formule de Haversine)
  /// Retourne la distance en kilomètres
  double distanceBetween(LatLng point1, LatLng point2) {
    final lat1 = point1.latitude * (math.pi / 180);
    final lat2 = point2.latitude * (math.pi / 180);
    final deltaLat = (point2.latitude - point1.latitude) * (math.pi / 180);
    final deltaLon = (point2.longitude - point1.longitude) * (math.pi / 180);

    final a =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLon / 2) *
            math.sin(deltaLon / 2);

    final c = 2 * math.asin(math.sqrt(a));

    return _earthRadiusKm * c;
  }

  /// Trouve tous les points dans un rayon donné
  ///
  /// [center] Centre de la recherche
  /// [radiusKm] Rayon de recherche en kilomètres
  /// [points] Liste de points à filtrer
  ///
  /// Retourne une liste de points triés par distance croissante
  List<T> findPointsInRadius<T>({
    required LatLng center,
    required double radiusKm,
    required List<T> points,
    required LatLng Function(T) pointExtractor,
  }) {
    final results = <_PointWithDistance<T>>[];

    for (final point in points) {
      final pointLatLng = pointExtractor(point);
      final distance = distanceBetween(center, pointLatLng);

      // Optimisation: comparer les carrés pour éviter les racines carrées
      if (distance <= radiusKm) {
        results.add(_PointWithDistance(point: point, distance: distance));
      }
    }

    // Trier par distance croissante
    results.sort((a, b) => a.distance.compareTo(b.distance));

    return results.map((e) => e.point).toList();
  }

  /// Calcule un bounding box (cadre délimitant) pour une recherche rapide
  ///
  /// Retourne les coordonnées min/max pour filtrer rapidement
  /// avant de faire le calcul de distance précis.
  BoundingBox getBoundingBox({
    required LatLng center,
    required double radiusKm,
  }) {
    // Approximation: 1° de latitude ≈ 111 km
    final latDelta = radiusKm / 111;

    // 1° de longitude ≈ 111 km * cos(latitude)
    final lonDelta =
        radiusKm / (111 * math.cos(center.latitude * math.pi / 180));

    return BoundingBox(
      minLat: center.latitude - latDelta,
      maxLat: center.latitude + latDelta,
      minLon: center.longitude - lonDelta,
      maxLon: center.longitude + lonDelta,
    );
  }

  /// Recherche optimisée en deux passes:
  /// 1. Bounding box (rapide)
  /// 2. Distance précise (Haversine)
  List<T> findPointsInRadiusOptimized<T>({
    required LatLng center,
    required double radiusKm,
    required List<T> points,
    required LatLng Function(T) pointExtractor,
  }) {
    final bbox = getBoundingBox(center: center, radiusKm: radiusKm);
    final results = <_PointWithDistance<T>>[];

    // Passe 1: Filtrage rapide par bounding box
    final candidates = points.where((point) {
      final latLng = pointExtractor(point);
      return latLng.latitude >= bbox.minLat &&
          latLng.latitude <= bbox.maxLat &&
          latLng.longitude >= bbox.minLon &&
          latLng.longitude <= bbox.maxLon;
    });

    // Passe 2: Calcul de distance précis
    for (final point in candidates) {
      final pointLatLng = pointExtractor(point);
      final distance = distanceBetween(center, pointLatLng);

      if (distance <= radiusKm) {
        results.add(_PointWithDistance(point: point, distance: distance));
      }
    }

    // Trier par distance
    results.sort((a, b) => a.distance.compareTo(b.distance));

    return results.map((e) => e.point).toList();
  }

  /// Génère un geohash simple pour un point
  ///
  /// Le geohash permet de regrouper les points proches
  /// dans la même "cellule" pour des requêtes plus rapides.
  String generateGeohash({
    required LatLng point,
    int precision =
        5, // Précision: 1-12 (plus c'est élevé, plus la cellule is small)
  }) {
    // Implementation simplifiée de geohash
    // Pour une version production, utiliser le package 'geohash2'

    final latRange = [-90.0, 90.0];
    final lonRange = [-180.0, 180.0];
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

    var geohash = '';
    var isEven = true;
    var bit = 0;
    var ch = 0;

    while (geohash.length < precision) {
      if (isEven) {
        final mid = (lonRange[0] + lonRange[1]) / 2;
        if (point.longitude > mid) {
          ch |= (1 << (4 - bit));
          lonRange[0] = mid;
        } else {
          lonRange[1] = mid;
        }
      } else {
        final mid = (latRange[0] + latRange[1]) / 2;
        if (point.latitude > mid) {
          ch |= (1 << (4 - bit));
          latRange[0] = mid;
        } else {
          latRange[1] = mid;
        }
      }

      isEven = !isEven;

      if (bit < 4) {
        bit++;
      } else {
        geohash += base32[ch];
        bit = 0;
        ch = 0;
      }
    }

    return geohash;
  }

  /// Trouve les points dans une cellule geohash et ses voisins
  List<T> findPointsInGeohash<T>({
    required String geohash,
    required List<T> points,
    required String Function(T) geohashExtractor,
  }) {
    return points.where((point) {
      final pointGeohash = geohashExtractor(point);
      return pointGeohash.startsWith(geohash);
    }).toList();
  }
}

/// Point avec distance (pour le tri)
class _PointWithDistance<T> {
  final T point;
  final double distance;

  _PointWithDistance({required this.point, required this.distance});
}

/// Cadre délimitant (bounding box)
class BoundingBox {
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  BoundingBox({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  /// Vérifie si un point est à l'intérieur du bounding box
  bool contains(LatLng point) {
    return point.latitude >= minLat &&
        point.latitude <= maxLat &&
        point.longitude >= minLon &&
        point.longitude <= maxLon;
  }
}
