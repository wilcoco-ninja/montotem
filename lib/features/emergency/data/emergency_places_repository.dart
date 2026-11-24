import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import 'package:montotem/core/services/routing_service.dart';
import 'package:montotem/features/emergency/domain/emergency_models.dart';

class EmergencyPlace {
  const EmergencyPlace({
    required this.id,
    required this.nom,
    required this.kind,
    required this.position,
    this.telephone,
  });

  final String id;
  final String nom;
  final ServiceKind kind;
  final LatLng position;
  final String? telephone;

  factory EmergencyPlace.fromJson(Map<String, dynamic> j) => EmergencyPlace(
    id: '${j['id']}',
    nom: '${j['nom']}',
    kind: ServiceKind.fromCode(j['kind'] as String?) ?? ServiceKind.ambulance,
    position: LatLng(
      (j['lat'] as num).toDouble(),
      (j['lng'] as num).toDouble(),
    ),
    telephone: j['tel'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nom': nom,
    'kind': kind.name,
    'lat': position.latitude,
    'lng': position.longitude,
    if (telephone != null) 'tel': telephone,
  };
}

class CachedRoute {
  const CachedRoute({
    required this.origine,
    required this.points,
    required this.distanceKm,
  });

  final LatLng origine;
  final List<LatLng> points;
  final double distanceKm;

  factory CachedRoute.fromJson(Map<String, dynamic> j) => CachedRoute(
    origine: LatLng(
      (j['olat'] as num).toDouble(),
      (j['olng'] as num).toDouble(),
    ),
    distanceKm: (j['km'] as num).toDouble(),
    points: (j['pts'] as List)
        .map((e) => LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble()))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'olat': origine.latitude,
    'olng': origine.longitude,
    'km': distanceKm,
    'pts': [
      for (final p in points) [p.latitude, p.longitude],
    ],
  };
}

/// Hôpitaux, commissariats et casernes autour de l'utilisateur, conservés sur
/// le téléphone (14 jours) avec les itinéraires routiers vers les plus proches.
class EmergencyPlacesRepository {
  EmergencyPlacesRepository._();
  static final EmergencyPlacesRepository instance =
      EmergencyPlacesRepository._();

  static const double _rayonKm = 25;
  static const Duration _validite = Duration(days: 14);
  static const Distance _distance = Distance();

  List<EmergencyPlace> _lieux = const [];
  Map<String, CachedRoute> _routes = {};
  LatLng? _centre;
  DateTime? _date;
  bool _charge = false;
  bool _enCours = false;
  bool _routesEnCours = false;

  List<EmergencyPlace> get lieux => _lieux;
  bool get vide => _lieux.isEmpty;
  DateTime? get dateMiseAJour => _date;

  Future<File> _fichier() async {
    final d = await getApplicationSupportDirectory();
    return File('${d.path}/emergency_cache.json');
  }

  Future<void> charger() async {
    if (_charge || kIsWeb) return;
    _charge = true;
    try {
      final f = await _fichier();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _centre = LatLng(
        (j['lat'] as num).toDouble(),
        (j['lng'] as num).toDouble(),
      );
      _date = DateTime.tryParse('${j['date']}');
      _lieux = (j['lieux'] as List)
          .whereType<Map>()
          .map((e) => EmergencyPlace.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _routes = {
        for (final e in ((j['routes'] as Map?) ?? const {}).entries)
          '${e.key}': CachedRoute.fromJson(
            Map<String, dynamic>.from(e.value as Map),
          ),
      };
    } catch (e) {
      developer.log(
        'lecture cache urgences',
        error: e,
        name: 'EmergencyPlaces',
      );
    }
  }

  Future<void> _enregistrer() async {
    if (kIsWeb) return;
    try {
      final f = await _fichier();
      await f.writeAsString(
        jsonEncode({
          'lat': _centre?.latitude,
          'lng': _centre?.longitude,
          'date': _date?.toIso8601String(),
          'lieux': _lieux.map((e) => e.toJson()).toList(),
          'routes': {for (final e in _routes.entries) e.key: e.value.toJson()},
        }),
      );
    } catch (e) {
      developer.log(
        'écriture cache urgences',
        error: e,
        name: 'EmergencyPlaces',
      );
    }
  }

  /// Établissements les plus proches, du plus près au plus loin.
  List<({EmergencyPlace lieu, double km})> plusProches(
    LatLng pos, {
    ServiceKind? kind,
    int limite = 20,
  }) {
    final liste = <({EmergencyPlace lieu, double km})>[];
    for (final p in _lieux) {
      if (kind != null && p.kind != kind) continue;
      liste.add((
        lieu: p,
        km: _distance.as(LengthUnit.Kilometer, pos, p.position),
      ));
    }
    liste.sort((a, b) => a.km.compareTo(b.km));
    return liste.take(limite).toList();
  }

  /// Itinéraire routier enregistré, valable si on est à moins de 2 km de son départ.
  CachedRoute? routeEnCache(String lieuId, LatLng position) {
    final r = _routes[lieuId];
    if (r == null) return null;
    return _distance.as(LengthUnit.Kilometer, r.origine, position) < 2
        ? r
        : null;
  }

  Future<void> memoriserRoute(String lieuId, CachedRoute route) async {
    _routes[lieuId] = route;
    await _enregistrer();
  }

  /// Garde au plus [max] points d'une ligne pour limiter la taille du cache.
  static List<LatLng> alleger(List<LatLng> points, {int max = 300}) {
    if (points.length <= max) return points;
    final pas = points.length / max;
    final out = <LatLng>[
      for (var i = 0; i < max; i++) points[(i * pas).floor()],
      points.last,
    ];
    return out;
  }

  /// Télécharge la zone si le cache est absent, ancien ou trop éloigné.
  Future<void> preparer(LatLng pos, {bool force = false}) async {
    await charger();
    if (_enCours) return;
    final c = _centre;
    final d = _date;
    final frais =
        c != null &&
        d != null &&
        DateTime.now().difference(d) < _validite &&
        _distance.as(LengthUnit.Kilometer, c, pos) < _rayonKm * 0.4 &&
        _lieux.isNotEmpty;

    if (!(frais && !force)) {
      _enCours = true;
      try {
        final lieux = await _telecharger(pos);
        if (lieux.isNotEmpty) {
          _lieux = lieux;
          _centre = pos;
          _date = DateTime.now();
          _routes = {};
          await _enregistrer();
        }
      } catch (e) {
        developer.log(
          'téléchargement urgences',
          error: e,
          name: 'EmergencyPlaces',
        );
      } finally {
        _enCours = false;
      }
    }
    unawaited(_preparerRoutes(pos));
  }

  Future<List<EmergencyPlace>> _telecharger(LatLng pos) async {
    final r = (_rayonKm * 1000).round();
    final a = '(around:$r,${pos.latitude},${pos.longitude})';
    final requete =
        '[out:json][timeout:25];('
        'nwr["amenity"="hospital"]$a;'
        'nwr["amenity"="clinic"]["emergency"="yes"]$a;'
        'nwr["amenity"="police"]$a;'
        'nwr["amenity"="fire_station"]$a;'
        ');out center 120;';

    final res = await http
        .post(
          Uri.parse('https://overpass-api.de/api/interpreter'),
          headers: {'User-Agent': 'MonTotem/1.0 (bj.totem.app)'},
          body: {'data': requete},
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw Exception('Overpass ${res.statusCode}');

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final out = <EmergencyPlace>[];
    for (final e
        in ((data['elements'] as List?) ?? const []).whereType<Map>()) {
      final tags = Map<String, dynamic>.from((e['tags'] as Map?) ?? const {});
      final kind = switch ('${tags['amenity'] ?? ''}') {
        'hospital' || 'clinic' => ServiceKind.ambulance,
        'police' => ServiceKind.police,
        'fire_station' => ServiceKind.fire,
        _ => null,
      };
      if (kind == null) continue;
      final lat = (e['lat'] ?? (e['center'] as Map?)?['lat']) as num?;
      final lon = (e['lon'] ?? (e['center'] as Map?)?['lon']) as num?;
      if (lat == null || lon == null) continue;
      final nom = '${tags['name'] ?? tags['name:fr'] ?? ''}'.trim();
      final tel = '${tags['phone'] ?? tags['contact:phone'] ?? ''}'.trim();
      out.add(
        EmergencyPlace(
          id: '${e['type']}${e['id']}',
          nom: nom.isEmpty ? kind.libelleLieu : nom,
          kind: kind,
          position: LatLng(lat.toDouble(), lon.toDouble()),
          telephone: tel.isEmpty ? null : tel.split(';').first.trim(),
        ),
      );
    }
    return out;
  }

  /// Enregistre l'itinéraire routier vers les 2 établissements les plus proches
  /// de chaque type, pour qu'il reste disponible hors ligne.
  Future<void> _preparerRoutes(LatLng pos) async {
    if (_routesEnCours || kIsWeb) return;
    _routesEnCours = true;
    try {
      final routing = RoutingService();
      var modifie = false;
      for (final kind in ServiceKind.values) {
        for (final item in plusProches(pos, kind: kind, limite: 2)) {
          final existant = _routes[item.lieu.id];
          if (existant != null &&
              _distance.as(LengthUnit.Kilometer, existant.origine, pos) < 1.5) {
            continue;
          }
          final r = await routing.getRoute(
            origin: pos,
            destination: item.lieu.position,
          );
          // Le service de routage renvoie une ligne droite en cas d'échec : on ne la garde pas.
          if (r.summary.contains('oiseau') || r.geometry.length < 3) continue;
          _routes[item.lieu.id] = CachedRoute(
            origine: pos,
            points: alleger(r.geometry),
            distanceKm: r.distanceKm,
          );
          modifie = true;
        }
      }
      if (modifie) await _enregistrer();
    } catch (e) {
      developer.log('itinéraires urgences', error: e, name: 'EmergencyPlaces');
    } finally {
      _routesEnCours = false;
    }
  }
}
