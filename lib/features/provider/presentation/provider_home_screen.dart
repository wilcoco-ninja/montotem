import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/travel_fee.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_ui.dart';
import '../../auth/data/location_service.dart';
import '../../requests/data/mission_service.dart';
import '../../requests/domain/mission_model.dart';
import '../data/provider_identity_service.dart';
import '../../wallet/data/wallet_service.dart';
import 'provider_routes.dart';
import 'widgets/provider_gains_sheet.dart';
import 'widgets/provider_wallet_card.dart';
import 'widgets/provider_momo_sheet.dart';

/// Accueil prestataire : carte plein écran, pastille de gains, panneau
/// coulissant (statut, indicateurs, raccourcis) et popup de demande entrante.
class ProviderHomeScreen extends StatefulWidget {
  const ProviderHomeScreen({super.key, this.onOpenTab});

  /// Dans la coque a onglets : change d'onglet (0 accueil, 1 gains, 2 profil).
  final ValueChanged<int>? onOpenTab;

  @override
  State<ProviderHomeScreen> createState() => _ProviderHomeScreenState();
}

class _ProviderHomeScreenState extends State<ProviderHomeScreen>
    with SingleTickerProviderStateMixin {
  final MissionService _service = MissionService();
  final ProviderIdentityService _identite = ProviderIdentityService();
  final LocationService _location = LocationService();
  final WalletService _walletService = WalletService();
  RealtimeChannel? _canalWallet;
  WalletSnapshot? _wallet;
  final MapController _map = MapController();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();
  RealtimeChannel? _canal;

  List<Mission> _missions = [];
  Map<String, dynamic>? _stats;
  IdentityStatus? _identity;
  LatLng? _me;

  bool _mapReady = false;
  bool _centered = false;
  bool _isLoading = true;
  bool _togglingDispo = false;
  bool _premierChargement = true;
  String? _busyId;
  String? _errorMessage;
  int _indexDemande = 0;
  final Set<String> _vues = <String>{};

  bool get _disponible => _stats?['disponible'] == true;

  @override
  void initState() {
    super.initState();
    _charger();
    _localiser();
    _chargerWallet();
    _canalWallet = _walletService.ecouter(() {
      if (mounted) _chargerWallet();
    });
    _canal = _service.ecouterMesMissions(() {
      if (mounted) _charger(silencieux: true);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _map.dispose();
    final c = _canal;
    if (c != null) _service.arreter(c);
    final w = _canalWallet;
    if (w != null) _walletService.arreter(w);
    super.dispose();
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ── Données ──────────────────────────────────────────────────────────────

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final res = await Future.wait<Object?>([
        _service.mesMissions(),
        _service.maStats(),
        _identite.statut(),
      ]);
      if (!mounted) return;
      final uid = _service.currentUserId;
      final missions = (res[0] as List<Mission>)
          .where((m) => m.providerId == uid)
          .toList();
      final pendantes = missions
          .where((m) => m.status == MissionStatus.pending)
          .map((m) => m.id)
          .toList();
      final nouvelle = pendantes.any((id) => !_vues.contains(id));
      _vues.addAll(pendantes);

      setState(() {
        _missions = missions;
        _stats = res[1] as Map<String, dynamic>?;
        _identity = res[2] as IdentityStatus?;
        _errorMessage = null;
      });

      if (nouvelle && !_premierChargement) {
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
      }
      _premierChargement = false;
    } on MissionException catch (e) {
      if (mounted && _missions.isEmpty) {
        setState(() => _errorMessage = e.message);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _chargerWallet() async {
    try {
      final s = await _walletService.charger();
      if (mounted) setState(() => _wallet = s);
    } on WalletException {
      // Wallet indisponible : l'accueil reste utilisable.
    }
  }

  Future<void> _localiser() async {
    try {
      final p = await _location.getCurrentLocation();
      if (!mounted) return;
      final pt = LatLng(p.latitude, p.longitude);
      setState(() => _me = pt);
      if (_mapReady) {
        _centered = true;
        _map.move(pt, 15);
      }
    } catch (_) {
      // Position indisponible : la carte reste sur Cotonou.
    }
  }

  void _centrer() {
    final me = _me;
    if (me != null && _mapReady) {
      _map.move(me, 15);
    } else {
      _localiser();
    }
  }

  Future<void> _basculerDispo(bool value) async {
    if (value && (_wallet?.wallet.blocked ?? false)) {
      _msg(kMessageCompteBloque);
      _aller(ProviderRoutes.wallet);
      return;
    }
    setState(() => _togglingDispo = true);
    try {
      await _service.definirDisponibilite(value);
      if (!mounted) return;
      setState(() => _stats = {...?_stats, 'disponible': value});
      HapticFeedback.mediumImpact();
    } on MissionException catch (e) {
      if (mounted) _msg(e.message);
    } finally {
      if (mounted) setState(() => _togglingDispo = false);
    }
  }

  Future<void> _agir(Mission m, String action) async {
    if (_busyId != null) return;
    setState(() => _busyId = m.id);
    try {
      await _service.agir(m.id, action);
      if (!mounted) return;
      if (action == 'accept') {
        await context.push('/provider/mission/${m.id}');
      }
      await _charger(silencieux: true);
    } on MissionException catch (e) {
      if (mounted) _msg(e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _ouvrir(Mission m) async {
    await context.push('/provider/mission/${m.id}');
    if (mounted) _charger(silencieux: true);
  }

  Future<void> _aller(String route) async {
    await context.push(route);
    if (mounted) _charger(silencieux: true);
  }

  void _changerDemande(int delta, List<Mission> nouvelles) {
    if (nouvelles.isEmpty) return;
    final n = nouvelles.length;
    final i = ((_indexDemande + delta) % n + n) % n;
    setState(() => _indexDemande = i);
    if (_mapReady) _map.move(nouvelles[i].clientPoint, 15);
  }

  // ── Calculs de gains ─────────────────────────────────────────────────────

  DateTime get _aujourdhui {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime get _debutMois {
    final n = DateTime.now();
    return DateTime(n.year, n.month);
  }

  int _gainsDepuis(DateTime d) => _missions
      .where((m) => !m.createdAt.isBefore(d))
      .fold<int>(0, (a, m) => a + m.paidFcfa);

  int get _termineesMois => _missions
      .where(
        (m) =>
            m.status == MissionStatus.completed &&
            !m.createdAt.isBefore(_debutMois),
      )
      .length;

  List<({DateTime date, int montant})> get _serieSemaine {
    final today = _aujourdhui;
    return List.generate(7, (i) {
      final jour = today.subtract(Duration(days: 6 - i));
      final suivant = jour.add(const Duration(days: 1));
      final total = _missions
          .where(
            (m) => !m.createdAt.isBefore(jour) && m.createdAt.isBefore(suivant),
          )
          .fold<int>(0, (a, m) => a + m.paidFcfa);
      return (date: jour, montant: total);
    });
  }

  int? get _tauxAcceptation {
    final traitees = _missions
        .where(
          (m) =>
              m.status != MissionStatus.pending &&
              m.status != MissionStatus.cancelled,
        )
        .length;
    if (traitees == 0) return null;
    final refus = _missions
        .where((m) => m.status == MissionStatus.refused)
        .length;
    return (((traitees - refus) / traitees) * 100).round();
  }

  void _ouvrirProfil() {
    final onglet = widget.onOpenTab;
    if (onglet != null) {
      onglet(2);
    } else {
      _aller(ProviderRoutes.profile);
    }
  }

  int _commissionDepuis(DateTime d) {
    final s = _wallet;
    if (s == null) return 0;
    return s.transactions
        .where((t) => t.estCommission && !t.createdAt.isBefore(d))
        .fold<int>(
          0,
          (a, t) => a + (t.amountFcfa < 0 ? -t.amountFcfa : t.amountFcfa),
        );
  }

  void _ouvrirGains() {
    final onglet = widget.onOpenTab;
    if (onglet != null) {
      onglet(1);
      return;
    }
    final serie = _serieSemaine;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => ProviderGainsSheet(
        jour: _gainsDepuis(_aujourdhui),
        semaine: serie.fold<int>(0, (a, e) => a + e.montant),
        mois: _gainsDepuis(_debutMois),
        serie: serie,
        termineesMois: _termineesMois,
        commissionJour: _commissionDepuis(_aujourdhui),
        commissionSemaine: _commissionDepuis(
          _aujourdhui.subtract(const Duration(days: 6)),
        ),
        config: _wallet?.config,
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: _body());
  }

  Widget _body() {
    if (_isLoading && _missions.isEmpty && _stats == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _missions.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(message: _errorMessage!, onRetry: () => _charger()),
        ),
      );
    }

    final nouvelles = _missions
        .where((m) => m.status == MissionStatus.pending)
        .toList();
    final enCours = _missions.where((m) => m.status.actif).toList();
    final terminees = _missions
        .where((m) => m.status == MissionStatus.completed)
        .take(5)
        .toList();
    final alertes = _alertes();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: Stack(
        children: [
          Positioned.fill(child: _carte(nouvelles, enCours)),
          Positioned.fill(child: _panneau(wide, enCours, terminees, alertes)),
          Positioned.fill(child: _barreHaut(alertes.length)),
          if (nouvelles.isNotEmpty) _demandePopup(nouvelles, wide),
        ],
      ),
    );
  }

  // ── Carte ────────────────────────────────────────────────────────────────

  Widget _carte(List<Mission> nouvelles, List<Mission> enCours) {
    final centre =
        _me ??
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
          final me = _me;
          if (me != null && !_centered) {
            _centered = true;
            _map.move(me, 15);
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'bj.totem.app',
        ),
        MarkerLayer(markers: _marqueurs(nouvelles, enCours)),
      ],
    );
  }

  List<Marker> _marqueurs(List<Mission> nouvelles, List<Mission> enCours) {
    final out = <Marker>[];
    final sel = nouvelles.isEmpty
        ? 0
        : _indexDemande.clamp(0, nouvelles.length - 1).toInt();
    for (var i = 0; i < nouvelles.length; i++) {
      final choisi = i == sel;
      out.add(
        Marker(
          point: nouvelles[i].clientPoint,
          width: choisi ? 60 : 48,
          height: choisi ? 60 : 48,
          alignment: Alignment.topCenter,
          child: Icon(
            Icons.location_on,
            size: choisi ? 56 : 44,
            color: AppTheme.errorColor,
          ),
        ),
      );
    }
    for (final m in enCours) {
      out.add(
        Marker(
          point: m.clientPoint,
          width: 50,
          height: 50,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.warningColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: const Icon(
              Icons.build_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      );
    }
    final me = _me;
    if (me != null) {
      out.add(
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
      );
    }
    return out;
  }

  // ── Barre du haut ────────────────────────────────────────────────────────

  Widget _barreHaut(int nbAlertes) {
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
                    icon: Icons.account_circle_rounded,
                    tooltip: 'Mon profil',
                    badge: nbAlertes > 0 ? '$nbAlertes' : null,
                    onTap: _ouvrirProfil,
                  ),
                  const Spacer(),
                  _PastilleGains(
                    montant: _gainsDepuis(_aujourdhui),
                    onTap: _ouvrirGains,
                  ),
                  const Spacer(),
                  const SizedBox(
                    width: 54,
                  ), // Espace équilibré sans le bouton taille texte
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface
                        .withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Panneau coulissant ───────────────────────────────────────────────────

  Widget _panneau(
    bool wide,
    List<Mission> enCours,
    List<Mission> terminees,
    List<Widget> alertes,
  ) {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        final mini = (200 / h).clamp(0.12, 0.5).toDouble();
        final init = (340 / h).clamp(mini, 0.7).toDouble();
        final sheet = DraggableScrollableSheet(
          initialChildSize: init,
          minChildSize: mini,
          maxChildSize: 0.92,
          snap: true,
          snapSizes: init > mini ? [init] : null,
          builder: (context, controller) =>
              _feuille(controller, enCours, terminees, alertes),
        );
        if (!wide) return sheet;
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(width: 440, height: h, child: sheet),
        );
      },
    );
  }

  Widget _feuille(
    ScrollController controller,
    List<Mission> enCours,
    List<Mission> terminees,
    List<Widget> alertes,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final note = (_stats?['note_moyenne'] as num?)?.toDouble() ?? 0;
    final taux = _tauxAcceptation;
    final bas = MediaQuery.paddingOf(context).bottom;

    return Container(
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
      child: ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(16, 10, 16, 32 + bas),
        children: [
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
          const SizedBox(height: 14),
          _enteteStatut(),
          const SizedBox(height: 14),
          ProviderWalletCard(
            snap: _wallet,
            onTap: () => _aller(ProviderRoutes.wallet),
          ),
          if (enCours.isNotEmpty) ...[
            const SectionTitle('Intervention en cours'),
            for (final m in enCours) _carteIntervention(m),
          ],
          if (alertes.isNotEmpty) ...[
            const SectionTitle('À faire'),
            for (final a in alertes) ...[a, const SizedBox(height: 10)],
          ],
          const SectionTitle('Mes indicateurs'),
          Row(
            children: [
              Expanded(
                child: _Kpi(
                  icon: Icons.star_rounded,
                  valeur: note.toStringAsFixed(1),
                  label: 'Ma note',
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Kpi(
                  icon: Icons.task_alt_rounded,
                  valeur: '$_termineesMois',
                  label: 'Terminées / mois',
                  color: AppTheme.successColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Kpi(
                  icon: Icons.thumb_up_alt_rounded,
                  valeur: taux == null ? '—' : '$taux %',
                  label: 'Acceptation',
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
          const SectionTitle('Raccourcis'),
          AdaptiveGrid(
            minItemWidth: 150,
            maxColumns: 2,
            spacing: 12,
            runSpacing: 12,
            children: [
              QuickTile(
                icon: Icons.payments_rounded,
                label: 'Mes gains',
                color: AppTheme.successColor,
                onTap: _ouvrirGains,
              ),
              QuickTile(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Recevoir mes paiements',
                color: AppTheme.secondaryDark,
                onTap: () => showProviderMomoSheet(context),
              ),
              QuickTile(
                icon: Icons.psychology_alt_outlined,
                label: 'Mes compétences',
                color: AppTheme.primaryColor,
                onTap: () => _aller('/provider/competences'),
              ),
              QuickTile(
                icon: Icons.savings_rounded,
                label: 'Mon portefeuille',
                color: AppColors.gold,
                onTap: () => _aller(ProviderRoutes.wallet),
              ),
            ],
          ),
          if (terminees.isNotEmpty) ...[
            const SectionTitle('Dernières interventions'),
            for (final m in terminees) _ligneHistorique(m),
          ],
        ],
      ),
    );
  }

  Widget _enteteStatut() {
    final on = _disponible;
    final aDemande = _missions.any((m) => m.status == MissionStatus.pending);

    final Widget bouton = on
        ? OutlinedButton.icon(
            onPressed: _togglingDispo ? null : () => _basculerDispo(false),
            icon: _togglingDispo
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.6),
                  )
                : const Icon(Icons.pause_rounded, size: 28),
            label: const Text('Se mettre en pause'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(64),
              textStyle: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        : FilledButton.icon(
            onPressed: _togglingDispo ? null : () => _basculerDispo(true),
            icon: _togglingDispo
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.power_settings_new_rounded, size: 30),
            label: const Text('Passer en ligne'),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.successColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(64),
              textStyle: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (on)
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) {
                        final t = _pulse.value;
                        return Container(
                          width: 12 + 24 * t,
                          height: 12 + 24 * t,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.successColor.withValues(
                              alpha: 0.35 * (1 - t),
                            ),
                          ),
                        );
                      },
                    ),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on ? AppTheme.successColor : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    on ? 'Vous êtes en ligne' : 'Vous êtes hors ligne',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    on
                        ? (aDemande
                              ? 'Une demande vous attend.'
                              : 'Recherche de demandes autour de vous…')
                        : 'Passez en ligne pour recevoir des demandes.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.3,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Ma position',
              iconSize: 28,
              icon: const Icon(Icons.my_location_rounded),
              onPressed: _centrer,
            ),
          ],
        ),
        const SizedBox(height: 14),
        bouton,
      ],
    );
  }

  Widget _carteIntervention(Mission m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SoftCard(
        onTap: () => _ouvrir(m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  m.status.icone,
                  color: context.readable(m.status.couleur),
                  size: 34,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.problem,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      StatusPill(
                        label: m.status.libelle,
                        color: m.status.couleur,
                        icon: m.status.icone,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Ouvrir l\'intervention',
              icon: Icons.navigation_rounded,
              onPressed: () => _ouvrir(m),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ligneHistorique(Mission m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        onTap: () => _ouvrir(m),
        child: Row(
          children: [
            Icon(
              m.status.icone,
              color: context.readable(m.status.couleur),
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                m.problem,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              TravelFee.fcfa(m.paidFcfa),
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: context.readable(AppTheme.successColor),
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  // ── Demande entrante ─────────────────────────────────────────────────────

  Widget _demandePopup(List<Mission> nouvelles, bool wide) {
    final total = nouvelles.length;
    final i = _indexDemande.clamp(0, total - 1).toInt();
    final m = nouvelles[i];
    final busy = _busyId == m.id;
    final eta = (m.distanceKm / 25 * 60).ceil();
    final vehicule = switch (m.vehicleType) {
      'moto' => Icons.two_wheeler_rounded,
      'camion' => Icons.local_shipping_rounded,
      _ => Icons.directions_car_rounded,
    };
    final scheme = Theme.of(context).colorScheme;

    return Positioned.fill(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: wide ? Alignment.bottomLeft : Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 440 : 560),
              child: Material(
                color: scheme.surface,
                elevation: 14,
                shadowColor: Colors.black54,
                borderRadius: BorderRadius.circular(26),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: AppTheme.successColor,
                      width: 2.5,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.successColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'NOUVELLE DEMANDE',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (total > 1) ...[
                            IconButton(
                              tooltip: 'Demande précédente',
                              icon: const Icon(Icons.chevron_left_rounded),
                              onPressed: () => _changerDemande(-1, nouvelles),
                            ),
                            Text(
                              '${i + 1}/$total',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Demande suivante',
                              icon: const Icon(Icons.chevron_right_rounded),
                              onPressed: () => _changerDemande(1, nouvelles),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          TravelFee.fcfa(m.travelFeeFcfa),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        'Frais de déplacement',
                        style: TextStyle(
                          fontSize: 15,
                          color: context.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Icon(
                              vehicule,
                              color: scheme.primary,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.problem,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  m.clientName,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    color: context.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          StatusPill(
                            label: '${m.distanceKm.toStringAsFixed(1)} km',
                            color: AppTheme.primaryColor,
                            icon: Icons.near_me_rounded,
                          ),
                          StatusPill(
                            label: '≈ $eta min',
                            color: AppTheme.secondaryDark,
                            icon: Icons.schedule_rounded,
                          ),
                        ],
                      ),
                      if (m.description != null &&
                          m.description!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          m.description!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: AppButton(
                              label: 'Refuser',
                              variant: AppButtonVariant.secondary,
                              onPressed: busy ? null : () => _agir(m, 'refuse'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: AppButton(
                              label: 'Accepter',
                              icon: Icons.check_rounded,
                              loading: busy,
                              onPressed: () => _agir(m, 'accept'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Alertes ──────────────────────────────────────────────────────────────

  List<Widget> _alertes() {
    final liste = <Widget>[];
    final id = _identity;

    if (id != null && !id.soumis) {
      liste.add(
        _Alerte(
          icon: Icons.badge_outlined,
          color: AppTheme.warningColor,
          titre: 'Envoyez vos documents',
          texte:
              'Sans dossier d\'identité, votre compte ne peut pas être validé.',
          onTap: () => _aller('/provider/identity'),
        ),
      );
    } else if (id != null && id.statutValidation == 'rejected') {
      liste.add(
        _Alerte(
          icon: Icons.error_outline_rounded,
          color: AppTheme.errorColor,
          titre: 'Dossier refusé',
          texte: (id.motifRefus ?? '').isEmpty
              ? 'Corrigez votre dossier et renvoyez-le.'
              : 'Motif : ${id.motifRefus}',
          onTap: () => _aller('/provider/identity'),
        ),
      );
    } else if (id != null && id.statutValidation == 'pending') {
      liste.add(
        const _Alerte(
          icon: Icons.hourglass_top_rounded,
          color: AppTheme.primaryColor,
          titre: 'Dossier en cours de vérification',
          texte: 'Vous recevrez des demandes dès qu\'il sera validé.',
        ),
      );
    }

    return liste;
  }
}

// ----------------------------------------------------------------------------
// Widgets
// ----------------------------------------------------------------------------

class _RondBouton extends StatelessWidget {
  const _RondBouton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Badge(
        isLabelVisible: badge != null,
        label: badge == null ? null : Text(badge!),
        child: Material(
          color: scheme.surface,
          elevation: 5,
          shadowColor: Colors.black45,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 54,
              height: 54,
              child: Icon(icon, size: 28, color: scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

class _PastilleGains extends StatelessWidget {
  const _PastilleGains({required this.montant, required this.onTap});

  final int montant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Gains du jour : ${TravelFee.fcfa(montant)}. Ouvrir le détail',
      child: Material(
        color: AppColors.navy,
        elevation: 5,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'AUJOURD\'HUI',
                    style: TextStyle(
                      color: AppColors.navyOnDark,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    TravelFee.fcfa(montant),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.valeur,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String valeur;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Column(
        children: [
          Icon(icon, size: 26, color: context.readable(color)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              valeur,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: TextStyle(fontSize: 13, color: context.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Alerte extends StatelessWidget {
  const _Alerte({
    required this.icon,
    required this.color,
    required this.titre,
    required this.texte,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String titre;
  final String texte;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = context.readable(color);
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              Icon(icon, color: fg, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      texte,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right_rounded, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
