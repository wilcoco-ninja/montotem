import 'dart:async';

import 'package:latlong2/latlong.dart';

import 'package:montotem/features/emergency/data/emergency_connectivity.dart';
import 'package:montotem/features/emergency/data/emergency_numbers_repository.dart';
import 'package:montotem/features/emergency/data/emergency_places_repository.dart';
import 'package:montotem/features/emergency/data/emergency_tile_provider.dart';

/// Prépare le mode hors ligne du SOS dès que la position est connue et qu'il y
/// a du réseau : numéros du pays, établissements proches, itinéraires, tuiles.
class EmergencyPreparation {
  static DateTime? _derniere;

  static Future<void> lancer(LatLng position) async {
    final d = _derniere;
    if (d != null &&
        DateTime.now().difference(d) < const Duration(minutes: 30)) {
      return;
    }
    _derniere = DateTime.now();

    await EmergencyNumbersRepository.instance.init();
    await EmergencyPlacesRepository.instance.charger();
    if (await estHorsLigne()) return;

    unawaited(EmergencyNumbersRepository.instance.synchroniser());
    unawaited(EmergencyPlacesRepository.instance.preparer(position));
    unawaited(TileDiskCache.instance.prechargerAutour(position));
  }
}
