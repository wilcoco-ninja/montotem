import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../emergency/presentation/widgets/sos_button.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/travel_fee.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_ui.dart';
import '../../auth/data/location_service.dart';
import '../../requests/data/mission_service.dart';
import '../../requests/domain/mission_model.dart';
import '../../requests/presentation/mission_chat_sheet.dart';
import '../../requests/presentation/widgets/mission_payments_card.dart';
import 'widgets/swipe_to_confirm.dart';

/// Intervention côté prestataire : carte plein écran, bandeau de navigation,
/// panneau coulissant et glissière de confirmation (arrivée, début, fin).
class ProviderMissionScreen extends StatefulWidget {
  const ProviderMissionScreen({super.key, required this.missionId});

  final String missionId;

  @override
  State<ProviderMissionScreen> createState() => _ProviderMissionScreenState();
}

class _ProviderMissionScreenState extends State<ProviderMissionScreen> {
  static const double _rayonArriveeM = 300;

  final MissionService _service = MissionService();
  final LocationService _location = LocationService();
  final RoutingService _routing = RoutingService();
  final MapController _map = MapController();

  Mission? _m;
  RealtimeChannel? _canal;
  StreamSubscription<Position>? _gps;
  Timer? _tick;

  LatLng? _me;
  double? _distM;
  List<LatLng> _route = const [];
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRoute = DateTime.fromMillisecondsSinceEpoch(0);
  bool _mapReady = false;
  bool _cadre = false;
  bool _lateral = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _charger();
    _canal = _service.ecouterMission(widget.missionId, () {
      if (mounted) _charger(silencieux: true);
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _m?.status == MissionStatus.working) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _gps?.cancel();
    final c = _canal;
    if (c != null) _service.arreter(c);
    _map.dispose();
    super.dispose();
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ── Données et GPS ───────────────────────────────────────────────────────

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) setState(() => _loading = true);
    try {
      final m = await _service.obtenir(widget.missionId);
      if (!mounted) return;
      setState(() {
        _m = m;
        _error = null;
      });
      await _synchroniserGps(m);
    } on MissionException catch (e) {
      if (mounted && _m == null) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _synchroniserGps(Mission m) async {
    if (!m.status.actif) {
      await _gps?.cancel();
      _gps = null;
      return;
    }
    if (_gps != null) return;
    try {
      final p = await _location.getCurrentLocation();
      _surPosition(p);
      _gps = _location.watchPosition().listen(_surPosition);
    } catch (e) {
      if (mounted) _msg('Activez la localisation pour être guidé et suivi.');
    }
  }

  void _surPosition(Position p) {
    final m = _m;
    if (!mounted || m == null) return;
    final me = LatLng(p.latitude, p.longitude);
    setState(() {
      _me = me;
      _distM = _location.distanceBetween(
        p.latitude,
        p.longitude,
        m.clientPoint.latitude,
        m.clientPoint.longitude,
      );
    });
    _ajusterCarte();

    final now = DateTime.now();
    if (now.difference(_lastSent) > const Duration(seconds: 8)) {
      _lastSent = now;
      _envoyerPosition(p);
    }
    if (m.status == MissionStatus.accepted &&
        now.difference(_lastRoute) > const Duration(seconds: 45)) {
      _lastRoute = now;
      _actualiserItineraire(me, m.clientPoint);
    }
  }

  Future<void> _envoyerPosition(Position p) async {
    try {
      final statut = await _service.envoyerPosition(
          widget.missionId, p.latitude, p.longitude);
      if (statut != _m?.status.value) await _charger(silencieux: true);
    } on MissionException {
      // Erreur réseau passagère
    }
  }

  Future<void> _actualiserItineraire(LatLng from, LatLng to) async {
    final r = await _routing.getRoute(origin: from, destination: to);
    if (mounted) setState(() => _route = r.geometry);
  }

  void _ajusterCarte() {
    final m = _m;
    if (!_mapReady || m == null || _cadre) return;
    final me = _me;
    if (me == null) return;
    _cadre = true;
    _map.fitCamera(CameraFit.coordinates(
      coordinates: [me, m.clientPoint],
      padding: EdgeInsets.fromLTRB(60, 230, 60, _lateral ? 70 : 380),
      maxZoom: 17,
    ));
  }

  void _recadrer(Mission m) {
    if (_me == null) {
      if (_mapReady) _map.move(m.clientPoint, 16);
      return;
    }
    _cadre = false;
    _ajusterCarte();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _agir(String action) async {
    setState(() => _busy = true);
    try {
      await _service.agir(widget.missionId, action);
      await _charger(silencieux: true);
    } on MissionException catch (e) {
      if (mounted) _msg(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Saisie du coût de réparation et validation via la RPC Supabase[cite: 3].
  Future<void> _finTravail(Mission m) async {
    final controller = TextEditingController(
      text: m.repairFeeFcfa > 0 ? '${m.repairFeeFcfa}' : '',
    );
    final montant = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fin de travail'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Indiquez le prix de la réparation (sans le déplacement).',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 8,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                labelText: 'Prix de la réparation',
                suffixText: 'FCFA',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(controller.text.trim()) ?? 0),
            child: const Text('Terminer le travail'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (montant != null) {
      try {
        setState(() => _busy = true);
        // Appel de la RPC Supabase pour finaliser avec le montant validé[cite: 3]
        await Supabase.instance.client.rpc(
          'mission_provider_action',
          params: {
            'p_mission': widget.missionId,
            'p_action': 'end_work',
            'p_amount': montant,
          },
        );
        await _charger(silencieux: true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        if (mounted) setState(() => _busy = false);
      }
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

  void _retour() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/provider/home');
    }
  }

  // ── Formats ──────────────────────────────────────────────────────────────

  String _dist(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  String _chrono(Duration d) {
    String t(int n) => n.toString().padLeft(2, '0');
    return '${t(d.inHours)}:${t(d.inMinutes.remainder(60))}:${t(d.inSeconds.remainder(60))}';
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final m = _m;
    if (m == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Intervention')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: SingleChildScrollView(
                  child: ErrorState(
                    message: _error ?? 'Intervention introuvable.',
                    onRetry: () => _charger(),
                  ),
                ),
              ),
      );
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) {
          final lateral = c.maxWidth >= 720 || c.maxWidth > c.maxHeight;
          _lateral = lateral;
          final proche = _distM != null && _distM! <= _rayonArriveeM;

          final carte = Stack(
            children: [
              Positioned.fill(child: _carte(m)),
              Positioned.fill(child: _overlayHaut(m)),
            ],
          );

          if (lateral) {
            return Row(
              children: [
                Expanded(child: carte),
                SizedBox(
                  width: math.min(c.maxWidth * 0.42, 460.0),
                  child: _contenuPanneau(m, proche, arrondi: false),
                ),
              ],
            );
          }
          return Stack(
            children: [
              Positioned.fill(child: carte),
              Positioned.fill(child: _feuille(m, proche, c.maxHeight)),
            ],
          );
        },
      ),
    );
  }

  // ── Carte ────────────────────────────────────────────────────────────────

  Widget _carte(Mission m) {
    final me = _me ?? m.providerPoint;
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: m.clientPoint,
        initialZoom: 15,
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
        if (_route.length >= 2)
          PolylineLayer(polylines: [
            Polyline(
              points: _route,
              color: AppTheme.primaryColor,
              strokeWidth: 6,
              borderColor: Colors.white,
              borderStrokeWidth: 2,
            ),
          ]),
        MarkerLayer(markers: [
          Marker(
            point: m.clientPoint,
            width: 56,
            height: 56,
            alignment: Alignment.topCenter,
            child: const Icon(Icons.location_on,
                size: 52, color: AppTheme.errorColor),
          ),
          if (me != null)
            Marker(
              point: me,
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

  Widget _overlayHaut(Mission m) {
    final scheme = Theme.of(context).colorScheme;
    final banniere = _banniere(m);

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _RondBouton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Retour',
                    onTap: _retour,
                  ),
                  const Spacer(),
                  Material(
                    color: scheme.surface,
                    elevation: 5,
                    shadowColor: Colors.black45,
                    borderRadius: BorderRadius.circular(30),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: StatusPill(
                        label: m.status.libelle,
                        color: m.status.couleur,
                        icon: m.status.icone,
                      ),
                    ),
                  ),
                  const Spacer(),
                  const SosAppBarButton(type: 'accident'),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: banniere ?? const SizedBox.shrink()),
                  const SizedBox(width: 8),
                  _RondBouton(
                    icon: Icons.my_location_rounded,
                    tooltip: 'Recentrer la carte',
                    onTap: () => _recadrer(m),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(fontSize: 11, color: context.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _banniere(Mission m) {
    switch (m.status) {
      case MissionStatus.accepted:
        final d = _distM;
        final eta = d == null ? null : (d / 1000 / 25 * 60).ceil();
        return _Bandeau(
          fond: AppColors.navy,
          icone: Icons.navigation_rounded,
          iconeCouleur: Colors.white,
          titre: d == null ? 'Recherche de votre position…' : _dist(d),
          titreCouleur: Colors.white,
          sousTitre: d == null
              ? 'Activez le GPS pour être guidé'
              : 'jusqu\'au client · ≈ ${eta == null || eta < 1 ? 1 : eta} min',
          sousTitreCouleur: AppColors.navyOnDark,
        );
      case MissionStatus.arrived:
        return const _Bandeau(
          fond: AppColors.emergencyStrong,
          icone: Icons.place_rounded,
          iconeCouleur: Colors.white,
          titre: 'Vous êtes arrivé',
          titreCouleur: Colors.white,
          sousTitre: 'Glissez pour démarrer le travail',
          sousTitreCouleur: Colors.white,
          grand: false,
        );
      case MissionStatus.working:
        final d = m.dureeTravail;
        return _Bandeau(
          fond: AppTheme.warningColor,
          icone: Icons.timer_rounded,
          iconeCouleur: AppColors.navy,
          titre: d == null ? '00:00:00' : _chrono(d),
          titreCouleur: AppColors.navy,
          sousTitre: 'Temps de travail',
          sousTitreCouleur: AppColors.navy,
        );
      default:
        return null;
    }
  }

  // ── Panneau ──────────────────────────────────────────────────────────────

  Widget _feuille(Mission m, bool proche, double h) {
    final mini = (250 / h).clamp(0.2, 0.5).toDouble();
    final init = (440 / h).clamp(mini, 0.75).toDouble();
    return DraggableScrollableSheet(
      initialChildSize: init,
      minChildSize: mini,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: init > mini ? [init] : null,
      builder: (context, controller) =>
          _contenuPanneau(m, proche, controller: controller, arrondi: true),
    );
  }

  Widget _contenuPanneau(
    Mission m,
    bool proche, {
    ScrollController? controller,
    required bool arrondi,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: arrondi
            ? const BorderRadius.vertical(top: Radius.circular(28))
            : BorderRadius.zero,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: arrondi ? const Offset(0, -6) : const Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              children: _blocs(m, arrondi),
            ),
          ),
          _barreAction(m, proche),
        ],
      ),
    );
  }

  List<Widget> _blocs(Mission m, bool avecPoignee) {
    final scheme = Theme.of(context).colorScheme;
    final vehicule = switch (m.vehicleType) {
      'moto' => ('Moto', Icons.two_wheeler_rounded),
      'camion' => ('Camion', Icons.local_shipping_rounded),
      _ => ('Auto', Icons.directions_car_rounded),
    };
    final suivi = m.status.actif || m.status == MissionStatus.completed;

    return [
      if (avecPoignee)
        Center(
          child: Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      if (avecPoignee) const SizedBox(height: 14),
      Text(m.problem,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          StatusPill(
              label: m.status.libelle,
              color: m.status.couleur,
              icon: m.status.icone),
          StatusPill(
              label: vehicule.$1,
              color: AppTheme.primaryColor,
              icon: vehicule.$2),
        ],
      ),
      if (suivi) ...[
        const SizedBox(height: 18),
        _EtapesMission(status: m.status),
      ],
      const SectionTitle('Client'),
      _carteClient(m),
      const SectionTitle('Détails'),
      SoftCard(
        child: Column(
          children: [
            if (m.clientAddress != null && m.clientAddress!.isNotEmpty)
              InfoRow(
                  icon: Icons.place_outlined,
                  label: 'Adresse',
                  value: m.clientAddress!),
            if (m.status == MissionStatus.accepted && _distM != null)
              InfoRow(
                  icon: Icons.near_me_rounded,
                  label: 'Distance restante',
                  value: _dist(_distM!)),
            InfoRow(
                icon: Icons.payments_outlined,
                label: 'Frais de déplacement',
                value: TravelFee.fcfa(m.travelFeeFcfa)),
            if (m.status == MissionStatus.completed) ...[
              InfoRow(
                  icon: Icons.build_circle_outlined,
                  label: 'Réparation',
                  value: TravelFee.fcfa(m.repairFeeFcfa)),
              InfoRow(
                  icon: Icons.receipt_long_outlined,
                  label: 'Total à percevoir',
                  value: TravelFee.fcfa(m.totalFcfa)),
              if (m.dureeTravail != null)
                InfoRow(
                    icon: Icons.timer_outlined,
                    label: 'Durée du travail',
                    value: '${m.dureeTravail!.inMinutes} min'),
            ],
          ],
        ),
      ),
      if (suivi) ...[
        const SectionTitle('Paiements'),
        MissionPaymentsCard(mission: m, asClient: false),
      ],
    ];
  }

  Widget _carteClient(Mission m) {
    final scheme = Theme.of(context).colorScheme;
    final peutAppeler = m.clientPhone != null && !m.status.termine;
    final peutDiscuter = !m.status.termine && m.status != MissionStatus.pending;

    return SoftCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person_rounded, color: scheme.primary, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              m.clientName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          if (peutDiscuter) ...[
            const SizedBox(width: 8),
            IconButton.filledTonal(
              iconSize: 26,
              tooltip: 'Discuter avec le client',
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              onPressed: () => showMissionChatSheet(context, m.id),
            ),
          ],
          if (peutAppeler) ...[
            const SizedBox(width: 8),
            IconButton.filled(
              iconSize: 26,
              tooltip: 'Appeler le client',
              icon: const Icon(Icons.call_rounded),
              onPressed: () => _appeler(m.clientPhone),
            ),
          ],
        ],
      ),
    );
  }

  Widget _barreAction(Mission m, bool proche) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.onSurface.withValues(alpha: 0.10)),
        ),
      ),
      child: _action(m, proche),
    );
  }

  Widget _action(Mission m, bool proche) {
    switch (m.status) {
      case MissionStatus.pending:
        return Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Refuser',
                variant: AppButtonVariant.secondary,
                onPressed: _busy ? null : () => _agir('refuse'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: AppButton(
                label: 'Accepter la demande',
                icon: Icons.check_rounded,
                loading: _busy,
                onPressed: () => _agir('accept'),
              ),
            ),
          ],
        );
      case MissionStatus.accepted:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwipeToConfirm(
              label: 'Glisser : je suis arrivé',
              icon: Icons.place_rounded,
              enabled: proche,
              loading: _busy,
              disabledLabel: _distM == null
                  ? 'Recherche de votre position…'
                  : 'À ${_dist(_distM!)} : approchez-vous (moins de 300 m)',
              onConfirmed: () => _agir('arrived'),
            ),
            const SizedBox(height: 6),
            Text(
              'L\'arrivée est aussi détectée automatiquement par GPS.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: context.textSecondary),
            ),
          ],
        );
      case MissionStatus.arrived:
        return SwipeToConfirm(
          label: 'Glisser : début du travail',
          icon: Icons.play_arrow_rounded,
          color: AppTheme.successColor,
          loading: _busy,
          onConfirmed: () => _agir('start_work'),
        );
      case MissionStatus.working:
        return SwipeToConfirm(
          label: 'Glisser : fin du travail',
          icon: Icons.stop_rounded,
          color: AppColors.emergencyStrong,
          loading: _busy,
          onConfirmed: () => _finTravail(m),
        );
      case MissionStatus.completed:
        return AppButton(
          label: 'Retour à l\'accueil',
          icon: Icons.home_rounded,
          onPressed: () => context.go('/provider/home'),
        );
      case MissionStatus.cancelled:
      case MissionStatus.refused:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Cette demande n\'est plus active.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: context.textSecondary),
            ),
            const SizedBox(height: 10),
            AppButton(
              label: 'Retour à l\'accueil',
              icon: Icons.home_rounded,
              onPressed: () => context.go('/provider/home'),
            ),
          ],
        );
    }
  }
}

// ----------------------------------------------------------------------------
// Widgets Annexes
// ----------------------------------------------------------------------------

class _RondBouton extends StatelessWidget {
  const _RondBouton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surface,
        elevation: 5,
        shadowColor: Colors.black45,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(icon, size: 26, color: scheme.onSurface),
          ),
        ),
      ),
    );
  }
}

class _Bandeau extends StatelessWidget {
  const _Bandeau({
    required this.fond,
    required this.icone,
    required this.iconeCouleur,
    required this.titre,
    required this.titreCouleur,
    required this.sousTitre,
    required this.sousTitreCouleur,
    this.grand = true,
  });

  final Color fond;
  final IconData icone;
  final Color iconeCouleur;
  final String titre;
  final Color titreCouleur;
  final String sousTitre;
  final Color sousTitreCouleur;
  final bool grand;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: fond,
      elevation: 6,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icone, color: iconeCouleur, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      titre,
                      style: TextStyle(
                        color: titreCouleur,
                        fontSize: grand ? 30 : 22,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                  ),
                  Text(
                    sousTitre,
                    style: TextStyle(
                      color: sousTitreCouleur,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EtapesMission extends StatelessWidget {
  const _EtapesMission({required this.status});

  final MissionStatus status;

  static const _labels = ['En route', 'Arrivé', 'Travail', 'Terminé'];

  int get _index => switch (status) {
        MissionStatus.accepted => 0,
        MissionStatus.arrived => 1,
        MissionStatus.working => 2,
        MissionStatus.completed => 3,
        _ => -1,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final courant = _index;
    final termine = status == MissionStatus.completed;
    final gris = scheme.onSurface.withValues(alpha: 0.2);
    final dernier = _labels.length - 1;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _labels.length; i++)
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 3,
                        color: i == 0
                            ? Colors.transparent
                            : (i <= courant ? AppTheme.successColor : gris),
                      ),
                    ),
                    _rond(context, i, courant, termine),
                    Expanded(
                      child: Container(
                        height: 3,
                        color: i == dernier
                            ? Colors.transparent
                            : (i < courant || termine
                                ? AppTheme.successColor
                                : gris),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _labels[i],
                    style: TextStyle(
                      fontSize: 14,
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

  Widget _rond(BuildContext context, int i, int courant, bool termine) {
    final scheme = Theme.of(context).colorScheme;
    final fait = i < courant || (i == courant && termine);
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fait
            ? AppTheme.successColor
            : (i == courant ? scheme.primary : Colors.transparent),
        border: Border.all(
          color: i <= courant
              ? Colors.transparent
              : scheme.onSurface.withValues(alpha: 0.4),
          width: 2,
        ),
      ),
      child: fait
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
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
    );
  }
}