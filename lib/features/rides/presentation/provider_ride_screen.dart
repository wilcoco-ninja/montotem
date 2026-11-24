import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;
import 'package:url_launcher/url_launcher.dart';

import 'package:montotem/core/services/routing_service.dart';
import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/auth/data/location_service.dart';
import 'package:montotem/features/emergency/data/emergency_actions.dart'
    show ouvrirNavigation;
import 'package:montotem/features/rides/data/ride_service.dart';
import 'package:montotem/features/rides/domain/ride_model.dart';
import 'package:montotem/features/wallet/data/wallet_service.dart';
import 'package:montotem/features/wallet/domain/wallet_model.dart';

/// Course en cours côté conducteur : itinéraire, GPS, arrivée, démarrage,
/// fin de course avec prix final et commission.
class ProviderRideScreen extends StatefulWidget {
  const ProviderRideScreen({super.key, required this.rideId});

  final String rideId;

  @override
  State<ProviderRideScreen> createState() => _ProviderRideScreenState();
}

class _ProviderRideScreenState extends State<ProviderRideScreen> {
  static const double _rayonArriveeM = 300;
  static const Distance _distance = Distance();

  final RideService _service = RideService();
  final WalletService _wallets = WalletService();
  final LocationService _location = LocationService();
  final RoutingService _routing = RoutingService();
  final MapController _map = MapController();

  RealtimeChannel? _canal;
  StreamSubscription<Position>? _gps;
  bool _gpsDemarre = false;

  Ride? _r;
  LatLng? _me;
  List<LatLng> _route = const [];
  WalletConfig _config = const WalletConfig();
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRoute = DateTime.fromMillisecondsSinceEpoch(0);
  bool _mapReady = false;
  bool _cadre = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _charger();
    _wallets.lireConfig().then((v) {
      if (mounted) setState(() => _config = v);
    });
    _canal = _service.ecouterCourse(widget.rideId, () {
      if (mounted) _charger(silencieux: true);
    });
  }

  @override
  void dispose() {
    _gps?.cancel();
    final c = _canal;
    if (c != null) _service.arreter(c);
    _map.dispose();
    super.dispose();
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  LatLng _cible(Ride r) =>
      r.status == RideStatus.inProgress ? r.dropoff : r.pickup;

  int? _distanceCibleM(Ride r) {
    final me = _me;
    if (me == null) return null;
    return _distance.as(LengthUnit.Meter, me, _cible(r)).round();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) setState(() => _loading = true);
    try {
      final r = await _service.details(widget.rideId);
      if (!mounted) return;
      final precedent = _r?.status;
      setState(() {
        _r = r;
        _error = null;
        if (precedent != null && precedent != r.status) {
          _route = const [];
          _lastRoute = DateTime.fromMillisecondsSinceEpoch(0);
        }
      });
      _ajusterCarte();
      await _synchroniserGps(r);
    } on RideException catch (e) {
      if (mounted && _r == null) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _synchroniserGps(Ride r) async {
    if (!r.status.actif) {
      await _gps?.cancel();
      _gps = null;
      _gpsDemarre = false;
      return;
    }
    if (_gpsDemarre) return;
    _gpsDemarre = true;
    try {
      final p = await _location.getCurrentLocation();
      _surPosition(p);
      _gps = _location.watchPosition().listen(_surPosition, onError: (_) {});
    } catch (_) {
      _gpsDemarre = false;
      if (mounted) _msg('Activez la localisation pour être guidé et suivi.');
    }
  }

  void _surPosition(Position p) {
    final r = _r;
    if (!mounted || r == null) return;
    final me = LatLng(p.latitude, p.longitude);
    setState(() => _me = me);
    _ajusterCarte();

    final now = DateTime.now();
    if (now.difference(_lastSent) > const Duration(seconds: 8)) {
      _lastSent = now;
      _envoyerPosition(p);
    }
    if (r.status.actif &&
        now.difference(_lastRoute) > const Duration(seconds: 45)) {
      _lastRoute = now;
      _actualiserItineraire(me, _cible(r));
    }
  }

  Future<void> _envoyerPosition(Position p) async {
    try {
      final statut = await _service.envoyerPosition(
        widget.rideId,
        p.latitude,
        p.longitude,
      );
      if (statut != _r?.status.value) await _charger(silencieux: true);
    } on RideException {
      // Erreur passagère : la prochaine position réessaiera.
    }
  }

  Future<void> _actualiserItineraire(LatLng from, LatLng to) async {
    final res = await _routing.getRoute(origin: from, destination: to);
    if (mounted) setState(() => _route = res.geometry);
  }

  void _ajusterCarte() {
    final r = _r;
    if (!_mapReady || _cadre || r == null) return;
    final me = _me;
    if (me == null) return;
    _cadre = true;
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [me, r.pickup, r.dropoff],
        padding: const EdgeInsets.all(70),
        maxZoom: 16,
      ),
    );
  }

  Future<void> _agir(String action, {int? tarif}) async {
    setState(() => _busy = true);
    try {
      final me = _me;
      if (action == 'arrived' && me != null) {
        // Position fraîche avant la vérification de proximité côté serveur.
        await _service.envoyerPosition(
          widget.rideId,
          me.latitude,
          me.longitude,
        );
      }
      await _service.action(widget.rideId, action, tarifFcfa: tarif);
      await _charger(silencieux: true);
    } on RideException catch (e) {
      if (mounted) _msg(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _terminer(Ride r) async {
    final prix = await showDialog<int>(
      context: context,
      builder: (_) => _PrixFinalDialog(
        convenu: r.fareFcfa,
        plafond: (r.fareFcfa * 3) ~/ 2,
        mobileMoney: r.payment.mobileMoney,
        commissionPct: _config.commissionPourCourse(
          mobileMoney: r.payment.mobileMoney,
        ),
      ),
    );
    if (prix != null) await _agir('complete', tarif: prix);
  }

  /// Verifie la fin de course avec le code a 6 chiffres transmis par le
  /// client. La commission est debitee apres ce code uniquement.
  Future<void> _confirmerFin(Ride r) async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _CodeVerificationDialog(),
    );
    if (code == null) return;
    setState(() => _busy = true);
    try {
      await _service.confirmerFin(r.id, code);
      await _charger(silencieux: true);
    } on RideException catch (e) {
      if (mounted) _msg(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _annuler() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la course ?'),
        content: const Text(
          'Le client sera prévenu.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non, continuer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _service.action(
        widget.rideId,
        'cancel',
        motif: 'Annulée par le conducteur',
      );
      await _charger(silencieux: true);
    } on RideException catch (e) {
      if (mounted) _msg(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _appeler(String? phone) async {
    final tel = phone?.replaceAll(RegExp(r'[^\d+]'), '');
    if (tel == null || tel.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: tel));
    } catch (_) {
      if (mounted) _msg('Impossible de lancer l\'appel.');
    }
  }

  Future<void> _naviguer(Ride r) async {
    final c = _cible(r);
    final ok = await ouvrirNavigation(
      lat: c.latitude,
      lng: c.longitude,
      libelle: r.status == RideStatus.inProgress ? 'Destination' : 'Client',
    );
    if (!ok && mounted) _msg('Aucune application de navigation trouvée.');
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      appBar: AppBar(title: const Text('Course')),
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
                final lateral = c.maxWidth >= 720 || c.maxWidth > c.maxHeight;
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
    final me = _me;
    final ligne = _route.length >= 2
        ? _route
        : (me != null && r.status.actif ? [me, _cible(r)] : const <LatLng>[]);

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: r.pickup,
        initialZoom: 14,
        onMapReady: () {
          _mapReady = true;
          _ajusterCarte();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'bj.totem.app',
        ),
        if (ligne.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: ligne,
                color: scheme.primary,
                strokeWidth: 6,
                borderColor: Colors.white,
                borderStrokeWidth: 2,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
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
            if (me != null)
              Marker(
                point: me,
                width: 30,
                height: 30,
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

  Widget _panneau(Ride r, {bool lateral = false}) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.8);

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
                  Icon(
                    r.kind.icone,
                    size: 30,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      TravelFee.fcfa(r.prixFcfa),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  StatusPill(
                    label: r.status.libelle,
                    color: r.status.couleur,
                    icon: r.status.icone,
                  ),
                ],
              ),
              if (r.status.actif || r.status == RideStatus.completed) ...[
                const SizedBox(height: 14),
                _EtapesConducteur(status: r.status),
              ],
              const SizedBox(height: 10),
              InfoRow(
                icon: Icons.person_outline_rounded,
                label: 'Client',
                value: r.clientName,
                trailing: (r.clientPhone != null && !r.status.termine)
                    ? IconButton.filledTonal(
                        icon: const Icon(Icons.call_rounded),
                        tooltip: 'Appeler le client',
                        onPressed: () => _appeler(r.clientPhone),
                      )
                    : null,
              ),
              InfoRow(
                icon: Icons.trip_origin_rounded,
                label: 'Départ',
                value: (r.pickupAddress ?? '').isEmpty
                    ? 'Point affiché sur la carte'
                    : r.pickupAddress!,
              ),
              InfoRow(
                icon: Icons.flag_rounded,
                label: 'Arrivée',
                value: (r.dropoffAddress ?? '').isEmpty
                    ? 'Point affiché sur la carte'
                    : r.dropoffAddress!,
              ),
              InfoRow(
                icon: Icons.route_rounded,
                label: 'Trajet',
                value: r.distanceLibelle,
              ),
              const SizedBox(height: 10),
              _cartePaiement(r),
              const SizedBox(height: 16),
              ..._actions(r, muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cartePaiement(Ride r) {
    if (r.status == RideStatus.completed) return _recapitulatif(r);

    final cash = !r.payment.mobileMoney;
    final pct = _config.commissionPourCourse(
      mobileMoney: r.payment.mobileMoney,
    );
    final texte = cash
        ? 'Le client vous remet ${TravelFee.fcfa(r.prixFcfa)} en espèces. '
              '$pct % sont déduits de votre wallet à la fin de la course.'
        : 'Le client vous paie par ${r.payment.libelle} sur votre numéro '
              'enregistré. Vérifiez la réception avant de terminer. '
              '$pct % de commission sont déduits de votre wallet à la fin de '
              'la course.';

    return SoftCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            cash ? Icons.payments_outlined : Icons.phone_android_rounded,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texte,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recapitulatif(Ride r) {
    final commission = r.commissionFcfa ?? 0;
    final net = r.prixFcfa - commission;
    return SoftCard(
      child: Column(
        children: [
          InfoRow(
            icon: Icons.receipt_long_outlined,
            label: 'Prix final',
            value: TravelFee.fcfa(r.prixFcfa),
          ),
          InfoRow(
            icon: Icons.percent_rounded,
            label: 'Commission retenue sur votre wallet',
            value: '-${TravelFee.fcfa(commission)}',
          ),
          InfoRow(
            icon: Icons.savings_outlined,
            label: 'Gain net',
            value: TravelFee.fcfa(net),
          ),
        ],
      ),
    );
  }

  List<Widget> _actions(Ride r, Color muted) {
    final dist = _distanceCibleM(r);

    switch (r.status) {
      case RideStatus.requested:
        return [
          Text(
            'Cette course n\'est pas encore à vous.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: muted),
          ),
        ];

      case RideStatus.accepted:
        final proche = dist != null && dist <= _rayonArriveeM;
        return [
          AppButton(
            label: 'Ouvrir la navigation vers le client',
            icon: Icons.directions_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: () => _naviguer(r),
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'Je suis arrivé',
            icon: Icons.place_rounded,
            loading: _busy,
            onPressed: proche ? () => _agir('arrived') : null,
          ),
          const SizedBox(height: 8),
          Text(
            dist == null
                ? 'Recherche de votre position…'
                : proche
                ? 'Vous êtes au point de départ.'
                : 'Vous êtes à ${formaterDistance(dist)}. Le bouton '
                      's\'active à moins de ${_rayonArriveeM.round()} m.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: muted),
          ),
          AppButton(
            label: 'Annuler la course',
            variant: AppButtonVariant.text,
            onPressed: _busy ? null : _annuler,
          ),
        ];

      case RideStatus.arrived:
        return [
          AppButton(
            label: 'Démarrer la course',
            icon: Icons.play_arrow_rounded,
            loading: _busy,
            onPressed: () => _agir('start'),
          ),
          AppButton(
            label: 'Annuler la course',
            variant: AppButtonVariant.text,
            onPressed: _busy ? null : _annuler,
          ),
        ];

      case RideStatus.inProgress:
        return [
          AppButton(
            label: 'Ouvrir la navigation vers la destination',
            icon: Icons.directions_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: () => _naviguer(r),
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'Terminer la course',
            icon: Icons.stop_rounded,
            loading: _busy,
            onPressed: () => _terminer(r),
          ),
          if (dist != null) ...[
            const SizedBox(height: 8),
            Text(
              'Destination à ${formaterDistance(dist)}.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: muted),
            ),
          ],
        ];

      case RideStatus.verifying:
        return [
          AppButton(
            label: 'Saisir le code du client',
            icon: Icons.pin_rounded,
            loading: _busy,
            onPressed: () => _confirmerFin(r),
          ),
          AppButton(
            label: 'Générer un nouveau code',
            variant: AppButtonVariant.text,
            loading: _busy,
            onPressed: () => _agir('complete', tarif: r.prixFcfa),
          ),
          const SizedBox(height: 8),
          Text(
            'Demandez au client le code à 6 chiffres affiché sur son écran, '
            'puis saisissez-le pour valider la fin de la course.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: muted),
          ),
        ];

      case RideStatus.completed:
        return [
          Text(
            'Course terminée. Merci !',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: muted),
          ),
        ];

      case RideStatus.cancelled:
        return [
          Text(
            (r.cancelReason ?? '').isEmpty
                ? 'Cette course a été annulée.'
                : r.cancelReason!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: muted),
          ),
        ];
    }
  }
}

/// Saisie du prix final : baisse libre, hausse limitée à +50 % du prix convenu.
class _PrixFinalDialog extends StatefulWidget {
  const _PrixFinalDialog({
    required this.convenu,
    required this.plafond,
    required this.mobileMoney,
    required this.commissionPct,
  });

  final int convenu;
  final int plafond;
  final bool mobileMoney;
  final int commissionPct;

  @override
  State<_PrixFinalDialog> createState() => _PrixFinalDialogState();
}

class _PrixFinalDialogState extends State<_PrixFinalDialog> {
  late final TextEditingController _c = TextEditingController(
    text: '${widget.convenu}',
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  int get _saisi => int.tryParse(_c.text.trim()) ?? 0;
  bool get _valide => _saisi >= 100 && _saisi <= widget.plafond;
  int get _commission => (_saisi * widget.commissionPct / 100).round();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = context.textSecondary;
    return AlertDialog(
      title: const Text('Terminer la course'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Prix convenu avec le client : ${TravelFee.fcfa(widget.convenu)}.\n'
            'Vous pouvez le baisser, ou l\'augmenter jusqu\'à '
            '${TravelFee.fcfa(widget.plafond)}.',
            style: const TextStyle(fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              labelText: 'Prix final',
              suffixText: 'FCFA',
              counterText: '',
            ),
          ),
          if (_saisi > 0 && !_valide)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Entre 100 et ${TravelFee.fcfa(widget.plafond)}.',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.error,
                ),
              ),
            ),
          if (_valide)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Commission ${widget.commissionPct} % '
                '(${widget.mobileMoney ? 'Mobile Money' : 'cash'}) : '
                '-${TravelFee.fcfa(_commission)} · Gain net '
                '${TravelFee.fcfa(_saisi - _commission)}',
                style: TextStyle(fontSize: 15, height: 1.35, color: muted),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _valide ? () => Navigator.pop(context, _saisi) : null,
          child: const Text('Terminer la course'),
        ),
      ],
    );
  }
}

/// Saisie du code à 6 chiffres transmis par le client en fin de course.
class _CodeVerificationDialog extends StatefulWidget {
  const _CodeVerificationDialog();

  @override
  State<_CodeVerificationDialog> createState() =>
      _CodeVerificationDialogState();
}

class _CodeVerificationDialogState extends State<_CodeVerificationDialog> {
  late final TextEditingController _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _saisi => _c.text.trim();
  bool get _valide => RegExp(r'^[0-9]{6}$').hasMatch(_saisi);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fin de course'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Demandez au client le code à 6 chiffres affiché sur son écran.',
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 6,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              fontSize: 24,
              letterSpacing: 8,
              fontWeight: FontWeight.w700,
            ),
            decoration: const InputDecoration(
              labelText: 'Code du client',
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _valide ? () => Navigator.pop(context, _saisi) : null,
          child: const Text('Confirmer'),
        ),
      ],
    );
  }
}

/// En route → Arrivé → En course → Terminée.
class _EtapesConducteur extends StatelessWidget {
  const _EtapesConducteur({required this.status});

  final RideStatus status;

  static const _labels = ['En route', 'Arrivé', 'En course', 'Terminée'];

  int get _index => switch (status) {
    RideStatus.accepted => 0,
    RideStatus.arrived => 1,
    RideStatus.inProgress => 2,
    RideStatus.completed => 3,
    _ => -1,
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
                  width: 36,
                  height: 36,
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
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 21,
                        )
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 16,
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
                      fontSize: 14,
                      fontWeight: i == courant
                          ? FontWeight.w800
                          : FontWeight.w600,
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
