
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/auth/data/location_service.dart';
import 'package:montotem/features/wallet/data/wallet_service.dart';
import 'package:montotem/features/rides/data/ride_driver_service.dart';
import 'package:montotem/features/rides/data/ride_service.dart';

/// Carte de l'accueil prestataire pour les ZÃƒÂ©midjan et Tricycle Fret :
/// courses ÃƒÂ  proximitÃƒÂ©, et mise ÃƒÂ  jour de la position tant que le conducteur
/// est en ligne. Invisible pour les autres prestataires.
class DriverRidesCard extends StatefulWidget {
  const DriverRidesCard({super.key});

  @override
  State<DriverRidesCard> createState() => _DriverRidesCardState();
}

class _DriverRidesCardState extends State<DriverRidesCard> {
  static const Duration _intervalle = Duration(seconds: 20);
  static const Duration _intervallePosition = Duration(seconds: 30);

  final RideDriverService _driver = RideDriverService();
  final RideService _rides = RideService();
  final WalletService _wallets = WalletService();
  final LocationService _location = LocationService();

  StreamSubscription<Position>? _gps;
  Timer? _timer;
  bool _gpsEnCours = false;
  DateTime _derniereSync = DateTime.fromMillisecondsSinceEpoch(0);

  DriverInfo? _info;
  bool _bloque = false;
  LatLng? _position;
  int? _courses;

  @override
  void initState() {
    super.initState();
    _actualiser();
    _timer = Timer.periodic(_intervalle, (_) => _actualiser());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _gps?.cancel();
    super.dispose();
  }

  bool get _enLigne {
    final i = _info;
    return i != null && i.conducteur && i.valide && i.disponible;
  }

  Future<void> _actualiser() async {
    final info = await _driver.charger();
    final wallet = await _wallets.lireWallet();
    if (!mounted) return;
    setState(() {
      _info = info;
      _bloque = wallet?.blocked == true;
    });

    if (_enLigne) {
      await _demarrerGps();
    } else {
      await _arreterGps();
    }
    await _compter();
  }

  Future<void> _demarrerGps() async {
    if (_gps != null || _gpsEnCours) return;
    _gpsEnCours = true;
    try {
      final p = await _location.getCurrentLocation();
      _surPosition(p);
      _gps = _location.watchPosition().listen(_surPosition, onError: (_) {});
    } catch (_) {
      // Permission refusÃƒÂ©e ou GPS coupÃƒÂ© : l'ÃƒÂ©cran Ã‚Â« Mes courses Ã‚Â» l'expliquera.
    } finally {
      _gpsEnCours = false;
    }
  }

  Future<void> _arreterGps() async {
    await _gps?.cancel();
    _gps = null;
  }

  void _surPosition(Position p) {
    if (!mounted) return;
    setState(() => _position = LatLng(p.latitude, p.longitude));
    final now = DateTime.now();
    if (now.difference(_derniereSync) >= _intervallePosition) {
      _derniereSync = now;
      unawaited(_driver.mettreAJourPosition(p.latitude, p.longitude));
    }
  }

  Future<void> _compter() async {
    final info = _info;
    final pos = _position;
    if (info == null ||
        !info.conducteur ||
        !info.valide ||
        !info.abonnementActif ||
        !info.disponible ||
        _bloque ||
        pos == null) {
      if (mounted) setState(() => _courses = null);
      return;
    }
    try {
      final liste = await _rides.proches(lat: pos.latitude, lng: pos.longitude);
      if (mounted) setState(() => _courses = liste.length);
    } on RideException {
      // Compteur indisponible : l'ÃƒÂ©cran Ã‚Â« Mes courses Ã‚Â» affichera l'erreur.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final info = _info;
    if (info == null || !info.conducteur) return const SizedBox.shrink();

    final String titre;
    final String detail;
    final Color couleur;
    if (_bloque) {
      titre = 'Wallet bloquÃƒÂ©';
      detail = 'Rechargez votre wallet pour recevoir des courses.';
      couleur = scheme.error;
    } else if (!info.valide || !info.abonnementActif) {
      titre = 'Courses';
      detail = !info.valide
          ? 'Disponible dÃƒÂ¨s que votre dossier est validÃƒÂ©.'
          : 'Un abonnement actif est nÃƒÂ©cessaire pour recevoir des courses.';
      couleur = scheme.tertiary;
    } else if (!info.disponible) {
      titre = 'Courses';
      detail = 'Passez en ligne pour recevoir des courses.';
      couleur = Colors.grey;
    } else if (_courses == null) {
      titre = 'Courses ÃƒÂ  proximitÃƒÂ©';
      detail = 'Recherche de votre positionÃ¢â‚¬Â¦';
      couleur = scheme.primary;
    } else if (_courses == 0) {
      titre = 'Courses ÃƒÂ  proximitÃƒÂ©';
      detail = 'Aucune course pour le moment. Restez en ligne.';
      couleur = scheme.primary;
    } else {
      final n = _courses!;
      titre = 'Courses ÃƒÂ  proximitÃƒÂ©';
      detail = '$n course${n > 1 ? 's' : ''} ÃƒÂ  moins de 5 km.';
      couleur = scheme.secondary;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SoftCard(
        onTap: () => context.push('/provider/rides'),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: couleur.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(info.rideKind!.icone,
                  color: context.readable(couleur), size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titre,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(detail,
                      style: TextStyle(
                          fontSize: 14.5,
                          height: 1.35,
                          color: context.textSecondary)),
                ],
              ),
            ),
            if ((_courses ?? 0) > 0)
              Container(
                constraints: const BoxConstraints(minWidth: 36),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.readable(couleur),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Text('${_courses!}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
              )
            else
              const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
