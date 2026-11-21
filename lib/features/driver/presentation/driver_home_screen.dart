
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'package:montotem/core/constants/app_constants.dart';
import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/auth/data/location_service.dart';
import 'package:montotem/features/driver/data/driver_service.dart';
import 'package:montotem/features/rides/data/ride_service.dart';
import 'package:montotem/features/rides/domain/ride_model.dart';

/// Accueil conducteur (ZÃƒÂ©midjan / Cloboto / Kloboto) :
/// carte plein ÃƒÂ©cran, statut en ligne/hors ligne, courses proches.
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  static const Duration _intervalle = Duration(seconds: 15);

  final DriverService _driver = DriverService();
  final RideService _rides = RideService();
  final LocationService _location = LocationService();
  final MapController _map = MapController();

  StreamSubscription<Position>? _gps;
  Timer? _poll;

  DriverInfo? _info;
  List<NearbyRide> _proches = const [];
  LatLng? _me;
  bool _loading = true;
  bool _toggling = false;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _charger();
    _localiser();
    _poll = Timer.periodic(_intervalle, (_) {
      if (mounted) _chargerProches();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _gps?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    final info = await _driver.charger();
    if (!mounted) return;
    setState(() {
      _info = info;
      _loading = false;
    });
    _chargerProches();
  }

  Future<void> _localiser() async {
    try {
      final p = await _location.getCurrentLocation();
      if (!mounted) return;
      final pt = LatLng(p.latitude, p.longitude);
      setState(() => _me = pt);
      if (_mapReady) _map.move(pt, 14);
      _gps = _location.watchPosition().listen(
        (Position q) {
          if (!mounted) return;
          final n = LatLng(q.latitude, q.longitude);
          setState(() => _me = n);
          _envoyerPosition(q);
        },
        onError: (_) {},
      );
      _chargerProches();
    } catch (_) {
      // GPS indisponible : la carte reste sur Cotonou.
    }
  }

  Future<void> _envoyerPosition(Position p) async {
    final info = _info;
    if (info == null || !info.conducteur) return;
    try {
      await _driver.mettreAJourPosition(p.latitude, p.longitude);
    } catch (_) {}
  }

  Future<void> _chargerProches() async {
    final info = _info;
    final me = _me;
    if (info == null || !info.conducteur || !info.disponible || me == null) {
      if (mounted) setState(() => _proches = const []);
      return;
    }
    try {
      final liste = await _rides.proches(
        lat: me.latitude,
        lng: me.longitude,
      );
      if (mounted) setState(() => _proches = liste);
    } on RideException {
      // Erreur transitoire : la prochaine actualisation rechargera.
    }
  }

  Future<void> _basculer() async {
    final info = _info;
    if (info == null) return;
    setState(() => _toggling = true);
    try {
      await _driver.definirDisponibilite(!info.disponible);
      await _charger();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _accepter(NearbyRide n) async {
    try {
      await _rides.action(n.id, 'accept');
      if (!mounted) return;
      await context.push('/driver/rides/${n.id}');
      if (mounted) _chargerProches();
    } on RideException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_info == null || !_info!.conducteur) {
      return Scaffold(
        appBar: AppBar(title: const Text('Espace conducteur')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Ce compte n\'est pas un compte conducteur.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Inscrivez-vous comme ZÃƒÂ©midjan, Cloboto ou Kloboto pour '
                  'recevoir des courses.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/register/driver'),
                  child: const Text('Devenir conducteur'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          _carte(),
          _barreHaut(),
          _panneauBas(),
        ],
      ),
    );
  }

  Widget _carte() {
    final centre = _me ??
        const LatLng(
          AppConstants.initialLatitude,
          AppConstants.initialLongitude,
        );
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: centre,
        initialZoom: 14,
        onMapReady: () {
          _mapReady = true;
          if (_me != null) _map.move(_me!, 14);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'bj.totem.app',
        ),
        if (_me != null)
          MarkerLayer(markers: [
            Marker(
              point: _me!,
              width: 44,
              height: 44,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                  ),
                ),
              ),
            ),
          ]),
      ],
    );
  }

  Widget _barreHaut() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 4,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => context.push('/driver/profile'),
                child: const SizedBox(
                  width: 52,
                  height: 52,
                  child: Icon(Icons.account_circle_rounded, size: 28),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _panneauBas() {
    final scheme = Theme.of(context).colorScheme;
    final enLigne = _info!.disponible;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 400),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      _info!.rideKind?.icone ?? Icons.two_wheeler_rounded,
                      size: 32,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _info!.rideKind?.libelle ?? 'Conducteur',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900),
                      ),
                    ),
                    StatusPill(
                      label: enLigne ? 'En ligne' : 'Hors ligne',
                      color: enLigne ? AppTheme.successColor : Colors.grey,
                      icon:
                          enLigne ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (enLigne) ...[
                  Text(
                    '${_proches.length} course${_proches.length > 1 ? 's' : ''} '
                    'ÃƒÂ  proximitÃƒÂ©',
                    style:
                        TextStyle(fontSize: 15, color: context.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  if (_proches.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Aucune course pour le moment. Restez en ligne.',
                        style: TextStyle(
                            fontSize: 14, color: context.textSecondary),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _proches.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _carteProche(_proches[i]),
                      ),
                    ),
                ] else
                  Text(
                    'Passez en ligne pour recevoir des courses',
                    style:
                        TextStyle(fontSize: 15, color: context.textSecondary),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _toggling ? null : _basculer,
                  icon: Icon(
                    enLigne
                        ? Icons.power_settings_new_rounded
                        : Icons.play_arrow_rounded,
                    size: 26,
                  ),
                  label: Text(
                    enLigne ? 'PASSER HORS LIGNE' : 'PASSER EN LIGNE',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(58),
                    backgroundColor:
                        enLigne ? AppTheme.errorColor : AppTheme.successColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _carteProche(NearbyRide n) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      onTap: () => _accepter(n),
      child: Row(
        children: [
          Icon(n.kind.icone, size: 28, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${n.kind.libelle} Ã‚Â· ${TravelFee.fcfa(n.fareFcfa)}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
                Text(
                  'DÃƒÂ©part ÃƒÂ  ${formaterDistance(n.distanceToPickupM)} Ã‚Â· '
                  'Trajet ${formaterDistance(n.tripDistanceM)}',
                  style:
                      TextStyle(fontSize: 13.5, color: context.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
