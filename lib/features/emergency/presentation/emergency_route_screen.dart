import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:montotem/core/services/routing_service.dart';
import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/emergency/data/emergency_actions.dart';
import 'package:montotem/features/emergency/data/emergency_connectivity.dart';
import 'package:montotem/features/emergency/data/emergency_numbers_repository.dart';
import 'package:montotem/features/emergency/data/emergency_places_repository.dart';
import 'package:montotem/features/emergency/data/emergency_tile_provider.dart';
import 'package:montotem/features/emergency/domain/emergency_models.dart';

/// Aller vers un établissement de secours.
/// Avec internet : itinéraire routier. Hors ligne : itinéraire enregistré s'il
/// existe, sinon direction, cap et distance en temps réel (le GPS suffit).
class EmergencyRouteScreen extends StatefulWidget {
  const EmergencyRouteScreen({super.key, required this.lieu});

  final EmergencyPlace lieu;

  @override
  State<EmergencyRouteScreen> createState() => _EmergencyRouteScreenState();
}

class _EmergencyRouteScreenState extends State<EmergencyRouteScreen> {
  static const Distance _distance = Distance();
  static const List<String> _points = [
    'Nord',
    'Nord-Est',
    'Est',
    'Sud-Est',
    'Sud',
    'Sud-Ouest',
    'Ouest',
    'Nord-Ouest',
  ];

  final EmergencyPlacesRepository _lieux = EmergencyPlacesRepository.instance;
  final EmergencyNumbersRepository _numeros =
      EmergencyNumbersRepository.instance;
  final MapController _map = MapController();
  final CachedTileProvider _tuiles = CachedTileProvider();

  StreamSubscription<Position>? _gps;
  StreamSubscription<bool>? _connSub;
  Position? _pos;
  bool _horsLigne = false;
  bool _mapPrete = false;
  bool _cadre = false;
  bool _routeChargee = false;
  bool _routeReelle = false;
  List<LatLng> _route = const [];

  EmergencyPlace get _lieu => widget.lieu;

  @override
  void initState() {
    super.initState();
    _numeros.init().then((_) {
      if (mounted) setState(() {});
    });
    estHorsLigne().then((v) {
      if (mounted) setState(() => _horsLigne = v);
    });
    _connSub = horsLigneStream().listen((v) {
      if (mounted) setState(() => _horsLigne = v);
    });
    _demarrerGps();
  }

  @override
  void dispose() {
    _gps?.cancel();
    _connSub?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _demarrerGps() async {
    final d = await SosLocator.derniere();
    if (mounted && d != null) _surPosition(d);
    final a = await SosLocator.actuelle();
    if (mounted && a != null) _surPosition(a);
    try {
      _gps = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(_surPosition, onError: (_) {});
    } catch (_) {}
  }

  void _surPosition(Position p) {
    if (!mounted) return;
    setState(() => _pos = p);
    _chargerRoute();
    _ajusterCarte();
  }

  LatLng? get _moi =>
      _pos == null ? null : LatLng(_pos!.latitude, _pos!.longitude);

  Future<void> _chargerRoute() async {
    final origine = _moi;
    if (_routeChargee || origine == null) return;
    _routeChargee = true;

    final cache = _lieux.routeEnCache(_lieu.id, origine);
    if (cache != null && mounted) {
      setState(() {
        _route = cache.points;
        _routeReelle = true;
      });
    }
    if (await estHorsLigne()) return;
    try {
      final r = await RoutingService().getRoute(
        origin: origine,
        destination: _lieu.position,
      );
      // Le service renvoie une ligne droite en cas d'échec : on ne l'affiche pas comme route.
      if (!mounted || r.summary.contains('oiseau')) return;
      setState(() {
        _route = r.geometry;
        _routeReelle = true;
      });
      unawaited(
        _lieux.memoriserRoute(
          _lieu.id,
          CachedRoute(
            origine: origine,
            points: EmergencyPlacesRepository.alleger(r.geometry),
            distanceKm: r.distanceKm,
          ),
        ),
      );
    } catch (_) {}
  }

  void _ajusterCarte() {
    final moi = _moi;
    if (!_mapPrete || _cadre || moi == null) return;
    _cadre = true;
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [moi, _lieu.position],
        padding: const EdgeInsets.all(60),
        maxZoom: 17,
      ),
    );
  }

  String _formatDistance(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    final moi = _moi;
    final pays = _numeros.resoudre(lat: moi?.latitude, lng: moi?.longitude);
    final lignes = <LatLng>[
      if (_route.length >= 2)
        ..._route
      else if (moi != null) ...[
        moi,
        _lieu.position,
      ],
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Aller vers les secours')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final lateral =
              constraints.maxWidth >= 720 ||
              constraints.maxWidth > constraints.maxHeight;
          final carte = _carte(moi, lignes);
          final panneau = _panneau(moi, pays, lateral: lateral);
          if (lateral) {
            final largeurPanneau = math.min(constraints.maxWidth * 0.42, 460.0);
            return Row(
              children: [
                Expanded(child: carte),
                SizedBox(width: largeurPanneau, child: panneau),
              ],
            );
          }
          return Column(
            children: [
              Expanded(flex: 4, child: carte),
              Expanded(flex: 5, child: panneau),
            ],
          );
        },
      ),
    );
  }

  Widget _carte(LatLng? moi, List<LatLng> lignes) {
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _lieu.position,
        initialZoom: 15,
        onMapReady: () {
          _mapPrete = true;
          _ajusterCarte();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'bj.totem.app',
          tileProvider: _tuiles,
        ),
        if (lignes.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: lignes,
                color: _routeReelle
                    ? AppTheme.primaryColor
                    : AppTheme.warningColor,
                strokeWidth: 6,
                borderColor: Colors.white,
                borderStrokeWidth: 2,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            Marker(
              point: _lieu.position,
              width: 52,
              height: 52,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: _lieu.kind.couleur, width: 3.5),
                ),
                child: Icon(
                  _lieu.kind.icone,
                  color: _lieu.kind.couleur,
                  size: 28,
                ),
              ),
            ),
            if (moi != null)
              Marker(
                point: moi,
                width: 32,
                height: 32,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
        ),
      ],
    );
  }

  Widget _panneau(LatLng? moi, CountryNumbers pays, {required bool lateral}) {
    final scheme = Theme.of(context).colorScheme;
    final distM = moi == null
        ? null
        : _distance.as(LengthUnit.Meter, moi, _lieu.position);
    final cap = moi == null
        ? null
        : ((_distance.bearing(moi, _lieu.position) % 360) + 360) % 360;
    final p = _pos;
    final enMouvement = p != null && p.speed > 1.0 && p.heading >= 0;
    final angle = cap == null
        ? 0.0
        : ((enMouvement ? cap - p.heading : cap) * math.pi / 180);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: lateral
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: lateral ? const Offset(-4, 0) : const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        left: !lateral,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _lieu.nom,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                  label: _lieu.kind.libelleLieu,
                  color: _lieu.kind.couleur,
                  icon: _lieu.kind.icone,
                ),
              ),
              const SizedBox(height: 12),
              if (distM == null)
                Text(
                  'Recherche de votre position GPS…',
                  style: TextStyle(
                    fontSize: 16.5,
                    color: context.textSecondary,
                  ),
                )
              else
                Row(
                  children: [
                    Transform.rotate(
                      angle: angle,
                      child: Icon(
                        Icons.navigation_rounded,
                        size: 64,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDistance(distM),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'Direction : ${_points[(((cap! + 22.5) % 360) ~/ 45)]} (${cap.round()}°)',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            enMouvement
                                ? 'La flèche indique où tourner par rapport à votre déplacement.'
                                : 'La flèche pointe vers le lieu, le nord étant en haut.',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.3,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              Text(
                _routeReelle
                    ? 'Itinéraire routier affiché (${_horsLigne ? 'enregistré sur ce téléphone' : 'en ligne'}).'
                    : (_horsLigne
                          ? 'Hors ligne : distance et direction à vol d\'oiseau. '
                                'La route exacte n\'est pas disponible ici.'
                          : 'Recherche de l\'itinéraire routier…'),
                style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              AppButton(
                label: 'Ouvrir dans une application de navigation',
                icon: Icons.directions_rounded,
                onPressed: () async {
                  final ok = await ouvrirNavigation(
                    lat: _lieu.position.latitude,
                    lng: _lieu.position.longitude,
                    libelle: _lieu.nom,
                  );
                  if (!ok && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Aucune application de navigation trouvée.',
                        ),
                      ),
                    );
                  }
                },
              ),
              if (_lieu.telephone != null) ...[
                const SizedBox(height: 10),
                AppButton(
                  label: 'Appeler cet établissement',
                  icon: Icons.call_rounded,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => appelerNumero(_lieu.telephone!),
                ),
              ],
              const SizedBox(height: 10),
              AppButton(
                label: 'Appeler les secours : ${pays.numero(_lieu.kind)}',
                icon: Icons.sos_outlined,
                variant: AppButtonVariant.danger,
                onPressed: () => appelerNumero(pays.numero(_lieu.kind)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
