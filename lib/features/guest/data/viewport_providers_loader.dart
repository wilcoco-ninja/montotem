import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/features/tracking/domain/prestataire_model.dart';

/// Charge les prestataires de la zone visible, n'importe où dans le monde.
///
/// - Une seule requête légère par zone (RPC `providers_in_bounds`), avec une
///   marge autour de l'écran : de petits déplacements ne refont aucun appel.
/// - Fusionne les résultats (pas de doublons, pas de « clignotement »).
/// - Ignore les réponses périmées quand l'utilisateur a déjà bougé ailleurs.
/// - Repli automatique sur l'ancienne RPC `providers_nearby` tant que la
///   migration 005 n'est pas appliquée.
class ViewportProvidersLoader extends ChangeNotifier {
  ViewportProvidersLoader({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const int _maxStored = 3000;

  final Map<String, Prestataire> _byId = {};
  final Map<String, List<String>> _vehicules = {};
  LatLngBounds? _loaded;
  int _generation = 0;
  bool _legacyMode = false;
  DateTime? _legacyLoadedAt;

  bool loading = false;
  Object? error;

  List<Prestataire> get all => _byId.values.toList(growable: false);

  /// id → types de véhicules (vide = ancien dossier, visible sous tout filtre).
  Map<String, List<String>> get vehicules => _vehicules;

  /// Appelé quand la carte s'arrête de bouger. [force] ignore la zone déjà
  /// chargée (bouton « réessayer », pull to refresh).
  Future<void> ensure(LatLngBounds visible, {bool force = false}) async {
    if (!force && _isCovered(visible)) return;

    final gen = ++_generation;
    loading = true;
    error = null;
    notifyListeners();

    try {
      final zone = _legacyMode ? visible : _expand(visible, 1.0);
      final rows = await _fetch(zone);
      if (gen != _generation) {
        return; // une requête plus récente a pris le relais
      }

      for (final row in rows) {
        final p = Prestataire.fromJson(row);
        if (p.id.isEmpty) continue;
        _byId[p.id] = p;
        final types = row['vehicle_types'];
        if (types is List) {
          _vehicules[p.id] = types.map((e) => '$e').toList();
        }
      }
      _trim(visible.center);
      _loaded = _legacyMode ? null : zone;
      if (_legacyMode) _legacyLoadedAt = DateTime.now();
    } catch (e) {
      if (gen != _generation) return;
      error = e;
    } finally {
      if (gen == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetch(LatLngBounds z) async {
    if (!_legacyMode) {
      try {
        // Plus de 360° visibles (zoom très éloigné) : le monde entier.
        final worldWide = (z.east - z.west) >= 360;
        final data = await _client.rpc('providers_in_bounds', params: {
          'p_min_lat': z.south.clamp(-90.0, 90.0),
          'p_min_lng': worldWide ? -180.0 : _wrapLng(z.west),
          'p_max_lat': z.north.clamp(-90.0, 90.0),
          'p_max_lng': worldWide ? 180.0 : _wrapLng(z.east),
          'p_limit': 400,
        }) as List;
        return data.whereType<Map>().map(Map<String, dynamic>.from).toList();
      } on PostgrestException catch (e) {
        // 42883 / PGRST202 : fonction absente => migration 005 pas encore faite.
        if (e.code == '42883' || e.code == 'PGRST202') {
          _legacyMode = true;
        } else {
          rethrow;
        }
      }
    }
    final data = await _client.rpc('providers_nearby') as List;
    return data.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  bool _isCovered(LatLngBounds v) {
    // Ancienne RPC : liste globale, inutile de la recharger à chaque geste.
    if (_legacyMode) {
      final at = _legacyLoadedAt;
      return at != null && DateTime.now().difference(at).inMinutes < 2;
    }
    final l = _loaded;
    if (l == null) return false;
    return v.south >= l.south &&
        v.north <= l.north &&
        v.west >= l.west &&
        v.east <= l.east;
  }

  LatLngBounds _expand(LatLngBounds b, double factor) {
    final dLat = (b.north - b.south) * factor / 2;
    final dLng = (b.east - b.west) * factor / 2;
    return LatLngBounds(
      LatLng((b.south - dLat).clamp(-85.0, 85.0).toDouble(), b.west - dLng),
      LatLng((b.north + dLat).clamp(-85.0, 85.0).toDouble(), b.east + dLng),
    );
  }

  static double _wrapLng(double lng) {
    var x = lng;
    while (x > 180) {
      x -= 360;
    }
    while (x < -180) {
      x += 360;
    }
    return x;
  }

  /// Garde la mémoire raisonnable : on retire les plus lointains du centre.
  void _trim(LatLng center) {
    if (_byId.length <= _maxStored) return;
    const dist = Distance();
    final sorted = _byId.values.toList()
      ..sort((a, b) => dist(center, LatLng(a.latitude, a.longitude))
          .compareTo(dist(center, LatLng(b.latitude, b.longitude))));
    for (final p in sorted.skip(_maxStored)) {
      _byId.remove(p.id);
      _vehicules.remove(p.id);
    }
  }
}
