
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:url_launcher/url_launcher.dart';

import 'package:montotem/core/services/routing_service.dart';
import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/rides/data/ride_service.dart';
import 'package:montotem/features/rides/domain/ride_model.dart';

/// Suivi d'une course cÃƒÂ´tÃƒÂ© client : carte en direct, ÃƒÂ©tat, conducteur,
/// paiement, annulation. Se met ÃƒÂ  jour par Supabase Realtime.
class RideTrackingScreen extends StatefulWidget {
  const RideTrackingScreen({super.key, required this.rideId});

  final String rideId;

  @override
  State<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends State<RideTrackingScreen> {
  static const Distance _distance = Distance();

  final RideService _service = RideService();
  final RoutingService _routing = RoutingService();
  final MapController _map = MapController();

  RealtimeChannel? _canal;
  Timer? _tick;

  Ride? _ride;
  List<LatLng> _route = const [];
  bool _routeDemandee = false;
  bool _mapPrete = false;
  bool _cadre = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _charger();
    _canal = _service.ecouterCourse(widget.rideId, () {
      if (mounted) _charger(silencieux: true);
    });
    // Filet de sÃƒÂ©curitÃƒÂ© si un ÃƒÂ©vÃƒÂ¨nement Realtime est manquÃƒÂ©.
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final r = _ride;
      if (r == null || !r.status.termine) _charger(silencieux: true);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    final c = _canal;
    if (c != null) _service.arreter(c);
    _map.dispose();
    super.dispose();
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) setState(() => _loading = true);
    try {
      final r = await _service.details(widget.rideId);
      if (!mounted) return;
      setState(() {
        _ride = r;
        _error = null;
      });
      _ajusterCarte();
      if (!_routeDemandee) {
        _routeDemandee = true;
        _chargerRoute(r);
      }
    } on RideException catch (e) {
      if (mounted && _ride == null) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _chargerRoute(Ride r) async {
    final res =
        await _routing.getRoute(origin: r.pickup, destination: r.dropoff);
    if (mounted) setState(() => _route = res.geometry);
  }

  void _ajusterCarte() {
    final r = _ride;
    if (!_mapPrete || _cadre || r == null) return;
    _cadre = true;
    _map.fitCamera(CameraFit.coordinates(
      coordinates: [
        r.pickup,
        r.dropoff,
        if (r.providerPoint != null) r.providerPoint!
      ],
      padding: const EdgeInsets.all(70),
      maxZoom: 16,
    ));
  }

  Future<void> _appeler(String? phone) async {
    final tel = phone?.replaceAll(RegExp(r'[^\d+]'), '');
    if (tel == null || tel.isEmpty) {
      _msg('NumÃƒÂ©ro pas encore disponible.');
      return;
    }
    try {
      await launchUrl(Uri(scheme: 'tel', path: tel));
    } catch (_) {
      if (mounted) _msg('Impossible de lancer l\'appel.');
    }
  }

  Future<void> _copier(String texte) async {
    await Clipboard.setData(ClipboardData(text: texte));
    if (!mounted) return;
    _msg('NumÃƒÂ©ro copiÃƒÂ©.');
  }

  Future<void> _annuler(Ride r) async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la course ?'),
        content: Text(
          r.providerId == null
              ? 'Votre demande sera retirÃƒÂ©e.'
              : 'Le conducteur sera prÃƒÂ©venu.',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non, garder'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _service.action(r.id, 'cancel', motif: 'AnnulÃƒÂ©e par le client');
      await _charger(silencieux: true);
    } on RideException catch (e) {
      if (mounted) _msg(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double _metresEntre(LatLng a, LatLng b) =>
      _distance.as(LengthUnit.Meter, a, b);

  @override
  Widget build(BuildContext context) {
    final r = _ride;
    return Scaffold(
      appBar: AppBar(title: const Text('Ma course')),
      body: _loading && r == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && r == null
              ? Center(
                  child: SingleChildScrollView(
                    child: ErrorState(message: _error!, onRetry: _charger),
                  ),
                )
              : r == null
                  ? const SizedBox.shrink()
                  : LayoutBuilder(
                      builder: (context, c) {
                        final lateral =
                            c.maxWidth >= 720 || c.maxWidth > c.maxHeight;
                        if (lateral) {
                          return Row(
                            children: [
                              Expanded(child: _carte(r)),
                              SizedBox(
                                width: math.min(c.maxWidth * 0.42, 460.0),
                                child: _panneau(r, lateral: true),
                              ),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            Expanded(flex: 4, child: _carte(r)),
                            Expanded(flex: 5, child: _panneau(r)),
                          ],
                        );
                      },
                    ),
    );
  }

  Widget _carte(Ride r) {
    final scheme = Theme.of(context).colorScheme;
    final prov = r.providerPoint;
    final versDepart = r.status == RideStatus.accepted && prov != null;

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: r.pickup,
        initialZoom: 14,
        onMapReady: () {
          _mapPrete = true;
          _ajusterCarte();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'bj.totem.app',
        ),
        PolylineLayer(polylines: [
          Polyline(
            points: _route.length >= 2 ? _route : [r.pickup, r.dropoff],
            color: scheme.primary.withValues(alpha: 0.75),
            strokeWidth: 5,
            borderColor: Colors.white,
            borderStrokeWidth: 2,
          ),
          if (versDepart)
            Polyline(
              points: [prov, r.pickup],
              color: scheme.tertiary,
              strokeWidth: 4,
            ),
        ]),
        MarkerLayer(markers: [
          Marker(
            point: r.pickup,
            width: 48,
            height: 48,
            alignment: Alignment.topCenter,
            child: Icon(Icons.location_on, size: 44, color: scheme.secondary),
          ),
          Marker(
            point: r.dropoff,
            width: 48,
            height: 48,
            alignment: Alignment.topCenter,
            child: Icon(Icons.location_on, size: 44, color: scheme.error),
          ),
          if (prov != null && r.status.actif)
            Marker(
              point: prov,
              width: 46,
              height: 46,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: Icon(r.kind.icone, color: Colors.white, size: 22),
              ),
            ),
        ]),
        const RichAttributionWidget(attributions: [
          TextSourceAttribution('Ã‚Â© OpenStreetMap contributors'),
        ]),
      ],
    );
  }

  Widget _panneau(Ride r, {bool lateral = false}) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
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
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(r.kind.icone,
                      size: 30, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(r.kind.libelle,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  StatusPill(
                    label: r.status.libelle,
                    color: r.status.couleur,
                    icon: r.status.icone,
                  ),
                ],
              ),
              if (r.status != RideStatus.cancelled) ...[
                const SizedBox(height: 14),
                _Etapes(status: r.status),
              ],
              const SizedBox(height: 12),
              ..._etat(r),
              const SectionTitle('DÃƒÂ©tails'),
              SoftCard(
                child: Column(
                  children: [
                    InfoRow(
                      icon: Icons.trip_origin_rounded,
                      label: 'DÃƒÂ©part',
                      value: (r.pickupAddress ?? '').isEmpty
                          ? 'Point choisi sur la carte'
                          : r.pickupAddress!,
                    ),
                    InfoRow(
                      icon: Icons.flag_rounded,
                      label: 'ArrivÃƒÂ©e',
                      value: (r.dropoffAddress ?? '').isEmpty
                          ? 'Point choisi sur la carte'
                          : r.dropoffAddress!,
                    ),
                    InfoRow(
                      icon: Icons.route_rounded,
                      label: 'Distance',
                      value: r.distanceLibelle,
                    ),
                    InfoRow(
                      icon: Icons.payments_outlined,
                      label: r.status == RideStatus.completed
                          ? 'Prix final'
                          : 'Prix convenu',
                      value: TravelFee.fcfa(r.prixFcfa),
                    ),
                    InfoRow(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Paiement',
                      value: r.payment.libelle,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (r.status == RideStatus.requested ||
                  r.status == RideStatus.accepted ||
                  r.status == RideStatus.arrived)
                AppButton(
                  label: 'Annuler la course',
                  icon: Icons.close_rounded,
                  variant: AppButtonVariant.secondary,
                  loading: _busy,
                  onPressed: () => _annuler(r),
                ),
              if (r.status.termine)
                AppButton(
                  label: 'Nouvelle course',
                  icon: Icons.add_rounded,
                  onPressed: () => context.pushReplacement('/ride/new'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bloc principal selon l'ÃƒÂ©tat de la course.
  List<Widget> _etat(Ride r) {
    final scheme = Theme.of(context).colorScheme;
    switch (r.status) {
      case RideStatus.requested:
        final minutes = DateTime.now().difference(r.createdAt).inMinutes;
        return [
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Recherche d\'un conducteur depuis '
                  '${minutes < 1 ? 'moins d\'une minute' : '$minutes min'}Ã¢â‚¬Â¦',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const LinearProgressIndicator(minHeight: 6),
                const SizedBox(height: 10),
                Text(
                  'Les conducteurs proches ont ÃƒÂ©tÃƒÂ© prÃƒÂ©venus. Sans rÃƒÂ©ponse '
                  'aprÃƒÂ¨s 30 minutes, la demande expire. Vous pouvez aussi '
                  'proposer un prix plus ÃƒÂ©levÃƒÂ© en annulant puis en '
                  'redemandant.',
                  style: TextStyle(
                      fontSize: 15, height: 1.4, color: context.textSecondary),
                ),
              ],
            ),
          ),
        ];

      case RideStatus.accepted:
      case RideStatus.arrived:
      case RideStatus.inProgress:
        final prov = r.providerPoint;
        String? proximite;
        if (r.status == RideStatus.accepted && prov != null) {
          final m = _metresEntre(prov, r.pickup).round();
          final minutes = math.max(1, (m / 1000 * 1.25 / 25 * 60).ceil());
          proximite =
              'Ãƒâ‚¬ ${formaterDistance(m)} de vous Ã‚Â· environ $minutes min';
        } else if (r.status == RideStatus.arrived) {
          proximite = 'Votre conducteur est arrivÃƒÂ© au point de dÃƒÂ©part.';
        }
        return [
          SoftCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  child: Icon(r.kind.icone, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.providerName ?? 'Conducteur',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      if (proximite != null)
                        Text(proximite,
                            style: TextStyle(
                                fontSize: 14.5, color: context.textSecondary)),
                    ],
                  ),
                ),
                if (r.providerPhone != null &&
                    r.status != RideStatus.inProgress)
                  IconButton.filledTonal(
                    iconSize: 26,
                    tooltip: 'Appeler le conducteur',
                    icon: const Icon(Icons.call_rounded),
                    onPressed: () => _appeler(r.providerPhone),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _cartePaiement(r),
        ];

      case RideStatus.completed:
        final change = r.finalFareFcfa != null && r.finalFareFcfa != r.fareFcfa;
        return [
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: scheme.secondary, size: 30),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Course terminÃƒÂ©e',
                          style: TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Montant ÃƒÂ  rÃƒÂ©gler : ${TravelFee.fcfa(r.prixFcfa)}'
                  '${change ? ' (prix convenu : ${TravelFee.fcfa(r.fareFcfa)})' : ''}',
                  style: const TextStyle(
                      fontSize: 16.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _cartePaiement(r),
        ];

      case RideStatus.cancelled:
        return [
          SoftCard(
            child: Row(
              children: [
                Icon(Icons.cancel_rounded, color: scheme.error, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    (r.cancelReason ?? '').isEmpty
                        ? 'Cette course a ÃƒÂ©tÃƒÂ© annulÃƒÂ©e.'
                        : r.cancelReason!,
                    style: const TextStyle(
                        fontSize: 16.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ];
    }
  }

  Widget _cartePaiement(Ride r) {
    final scheme = Theme.of(context).colorScheme;
    final momo = r.providerMomo;
    final montant = TravelFee.fcfa(r.prixFcfa);

    if (!r.payment.mobileMoney) {
      return SoftCard(
        child: Row(
          children: [
            const Icon(Icons.payments_outlined, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'EspÃƒÂ¨ces : remettez $montant au conducteur ÃƒÂ  l\'arrivÃƒÂ©e.',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    if (momo == null) {
      return SoftCard(
        child: Text(
          'Paiement ${r.payment.libelle} : le numÃƒÂ©ro du conducteur s\'affiche '
          'ici dÃƒÂ¨s qu\'il est disponible.',
          style: TextStyle(
              fontSize: 15.5, height: 1.4, color: context.textSecondary),
        ),
      );
    }

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Payez $montant par ${momo.methode.libelle} au conducteur :',
            style: const TextStyle(
                fontSize: 16.5, fontWeight: FontWeight.w800, height: 1.35),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(momo.numero,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      if ((momo.titulaire ?? '').isNotEmpty)
                        Text('Au nom de ${momo.titulaire}',
                            style: const TextStyle(fontSize: 14.5)),
                    ],
                  ),
                ),
                IconButton(
                  iconSize: 26,
                  tooltip: 'Copier le numÃƒÂ©ro',
                  icon: const Icon(Icons.copy_rounded),
                  onPressed: () => _copier(momo.numero),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Recherche Ã¢â€ â€™ En route Ã¢â€ â€™ ArrivÃƒÂ© Ã¢â€ â€™ En course Ã¢â€ â€™ TerminÃƒÂ©e.
class _Etapes extends StatelessWidget {
  const _Etapes({required this.status});

  final RideStatus status;

  static const _labels = [
    'Recherche',
    'En route',
    'ArrivÃƒÂ©',
    'En course',
    'TerminÃƒÂ©e'
  ];

  int get _index => switch (status) {
        RideStatus.requested => 0,
        RideStatus.accepted => 1,
        RideStatus.arrived => 2,
        RideStatus.inProgress => 3,
        RideStatus.completed => 4,
        RideStatus.cancelled => -1,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final courant = _index;
    final fini = status == RideStatus.completed;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _labels.length; i++)
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < courant || (i == courant && fini)
                        ? scheme.secondary
                        : (i == courant ? scheme.primary : Colors.transparent),
                    border: Border.all(
                      color: i <= courant
                          ? Colors.transparent
                          : scheme.onSurface.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: i < courant || (i == courant && fini)
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 20)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: i == courant
                                ? scheme.onPrimary
                                : scheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _labels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          i == courant ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
