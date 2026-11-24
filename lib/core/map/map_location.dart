import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

enum LocationIssue { servicesOff, denied, deniedForever, unavailable }

class LocationFix {
  const LocationFix(this.point, {this.accuracyM, this.fromCache = false});
  final LatLng point;
  final double? accuracyM;

  /// true = dernière position connue (affichée tout de suite, avant le GPS).
  final bool fromCache;
}

/// Localisation « monde entier » : aucune position de repli codée en dur.
/// Stratégie rapide : dernière position connue immédiatement, puis position
/// précise ; suivi continu avec filtre de distance pour économiser la batterie.
class MapLocation {
  MapLocation._();
  static final MapLocation instance = MapLocation._();

  LocationIssue? lastIssue;
  LatLng? _memo;

  /// Dernière position obtenue pendant cette session.
  LatLng? get memo => _memo;

  /// Vérifie le service et les permissions. Retourne null si tout est bon.
  Future<LocationIssue?> ensureReady({bool askPermission = true}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationIssue.servicesOff;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && askPermission) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        return LocationIssue.deniedForever;
      }
      if (perm == LocationPermission.denied) return LocationIssue.denied;
      return null;
    } catch (_) {
      return LocationIssue.unavailable;
    }
  }

  /// Dernière position connue : quasi instantanée (inexistante sur le web).
  Future<LocationFix?> quick() async {
    if (_memo != null) return LocationFix(_memo!, fromCache: true);
    try {
      final p = await Geolocator.getLastKnownPosition();
      if (p == null) return null;
      _memo = LatLng(p.latitude, p.longitude);
      return LocationFix(_memo!, accuracyM: p.accuracy, fromCache: true);
    } catch (_) {
      return null;
    }
  }

  /// Position précise. Retourne null et renseigne [lastIssue] en cas d'échec.
  Future<LocationFix?> precise({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    lastIssue = await ensureReady();
    if (lastIssue != null) return null;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(timeout);
      _memo = LatLng(p.latitude, p.longitude);
      return LocationFix(_memo!, accuracyM: p.accuracy);
    } on TimeoutException {
      lastIssue = LocationIssue.unavailable;
      return null;
    } catch (_) {
      lastIssue = LocationIssue.unavailable;
      return null;
    }
  }

  /// Suivi continu (point bleu qui bouge). Ne s'abonne que si la permission
  /// est déjà accordée : n'ouvre jamais de dialogue par surprise.
  Stream<LocationFix> watch({int distanceFilterM = 15}) async* {
    final issue = await ensureReady(askPermission: false);
    if (issue != null) return;
    try {
      yield* Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: distanceFilterM,
        ),
      ).map((p) {
        _memo = LatLng(p.latitude, p.longitude);
        return LocationFix(_memo!, accuracyM: p.accuracy);
      });
    } catch (e) {
      if (kDebugMode) debugPrint('MapLocation.watch: $e');
    }
  }

  static String messageFor(LocationIssue issue) => switch (issue) {
    LocationIssue.servicesOff => 'Activez la localisation de votre téléphone.',
    LocationIssue.denied =>
      'Autorisez la localisation pour voir '
          'les dépanneurs autour de vous.',
    LocationIssue.deniedForever =>
      'Localisation refusée. Autorisez-la dans les réglages de l\'application.',
    LocationIssue.unavailable => 'Position introuvable pour le moment.',
  };
}
