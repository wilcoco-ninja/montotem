
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/travel_fee.dart';
import '../../../core/widgets/app_ui.dart';
import '../../requests/data/mission_service.dart';
import '../../requests/domain/mission_model.dart';
import '../../wallet/data/wallet_service.dart';
import '../../wallet/domain/wallet_model.dart';
import '../data/provider_earnings_service.dart';
import 'provider_routes.dart';
import 'widgets/provider_wallet_card.dart';

enum _Fenetre {
  sept(7, '7 jours'),
  trente(30, '30 jours'),
  quatreVingtDix(90, '90 jours');

  const _Fenetre(this.jours, this.libelle);
  final int jours;
  final String libelle;
}

/// Onglet Gains : encaissÃƒÂ©, commission et net exacts (courses + dÃƒÂ©pannages),
/// interventions et mouvements du portefeuille.
class ProviderEarningsScreen extends StatefulWidget {
  const ProviderEarningsScreen({super.key});

  @override
  State<ProviderEarningsScreen> createState() => _ProviderEarningsScreenState();
}

class _ProviderEarningsScreenState extends State<ProviderEarningsScreen> {
  static const _moisCourts = [
    'janv.',
    'fÃƒÂ©vr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'aoÃƒÂ»t',
    'sept.',
    'oct.',
    'nov.',
    'dÃƒÂ©c.',
  ];
  static const _jours = [
    'lun.',
    'mar.',
    'mer.',
    'jeu.',
    'ven.',
    'sam.',
    'dim.'
  ];
  static const _lettres = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  final MissionService _missionService = MissionService();
  final WalletService _walletService = WalletService();
  final ProviderEarningsService _earnings = ProviderEarningsService();
  RealtimeChannel? _canalMissions;
  RealtimeChannel? _canalWallet;

  List<Mission> _missions = [];
  WalletSnapshot? _wallet;
  EarningsSummary? _resume;
  String? _erreurResume;
  bool _chargementResume = false;
  int _seq = 0;

  _Fenetre _fenetre = _Fenetre.sept;
  int _offset = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _charger();
    _canalMissions = _missionService.ecouterMesMissions(() {
      if (mounted) _charger(silencieux: true);
    });
    _canalWallet = _walletService.ecouter(() {
      if (mounted) _charger(silencieux: true);
    });
  }

  @override
  void dispose() {
    final m = _canalMissions;
    if (m != null) _missionService.arreter(m);
    final w = _canalWallet;
    if (w != null) _walletService.arreter(w);
    super.dispose();
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ DonnÃƒÂ©es Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    _chargerResume(silencieux: true);

    try {
      final uid = _missionService.currentUserId;
      final liste = await _missionService.mesMissions();
      if (!mounted) return;
      setState(() {
        _missions = liste.where((m) => m.providerId == uid).toList();
        _error = null;
      });
    } on MissionException catch (e) {
      if (mounted && _missions.isEmpty) setState(() => _error = e.message);
    }
    try {
      final s = await _walletService.charger();
      if (mounted) setState(() => _wallet = s);
    } on WalletException {
      // Wallet indisponible : les gains restent affichÃƒÂ©s.
    }
    if (mounted) setState(() => _loading = false);
  }

  int get _maxOffset => 365 ~/ _fenetre.jours - 1;

  Future<void> _chargerResume({bool silencieux = false}) async {
    final seq = ++_seq;
    if (!silencieux) {
      setState(() {
        _chargementResume = true;
        _erreurResume = null;
      });
    }
    try {
      final jours = (_fenetre.jours * (_offset + 1)).clamp(1, 365).toInt();
      final r = await _earnings.resume(jours);
      if (!mounted || seq != _seq) return;
      setState(() {
        _resume = r;
        _erreurResume = null;
        _chargementResume = false;
      });
    } on EarningsException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _erreurResume = e.message;
        _chargementResume = false;
      });
    }
  }

  void _changerFenetre(_Fenetre f) {
    if (f == _fenetre) return;
    setState(() {
      _fenetre = f;
      _offset = 0;
    });
    _chargerResume();
  }

  void _decaler(int delta) {
    final nouveau = _offset + delta;
    if (nouveau < 0 || nouveau > _maxOffset) return;
    setState(() => _offset = nouveau);
    _chargerResume();
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Calculs Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  /// Jours de la fenÃƒÂªtre affichÃƒÂ©e, du plus ancien au plus rÃƒÂ©cent.
  List<EarningsDay> get _jours_ {
    final r = _resume;
    if (r == null) return const [];
    final n = _fenetre.jours;
    final fin = r.series.length - n * _offset;
    if (fin <= 0) return const [];
    final debut = fin - n < 0 ? 0 : fin - n;
    return r.series.sublist(debut, fin);
  }

  DateTime? get _debut => _jours_.isEmpty ? null : _jours_.first.date;

  DateTime? get _fin =>
      _jours_.isEmpty ? null : _jours_.last.date.add(const Duration(days: 1));

  bool _dans(DateTime t) {
    final d = _debut;
    final f = _fin;
    if (d == null || f == null) return false;
    return !t.isBefore(d) && t.isBefore(f);
  }

  String _jourCourt(DateTime d) =>
      '${_jours[d.weekday - 1]} ${d.day} ${_moisCourts[d.month - 1]}';

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';

  String get _libelleFenetre {
    final j = _jours_;
    if (j.isEmpty) return 'Ã¢â‚¬â€';
    final a = j.first.date;
    final b = j.last.date;
    if (a.month == b.month) {
      return '${a.day} Ã¢â‚¬â€œ ${b.day} ${_moisCourts[b.month - 1]}';
    }
    return '${a.day} ${_moisCourts[a.month - 1]} Ã¢â‚¬â€œ '
        '${b.day} ${_moisCourts[b.month - 1]}';
  }

  List<_Barre> _barres() {
    final j = _jours_;
    final aujourdhui = DateTime.now();
    return [
      for (var i = 0; i < j.length; i++)
        _Barre(
          titre: _jourCourt(j[i].date),
          libelle: switch (_fenetre) {
            _Fenetre.sept => _lettres[j[i].date.weekday - 1],
            _Fenetre.trente => (j[i].date.day == 1 || j[i].date.day % 5 == 0)
                ? '${j[i].date.day}'
                : '',
            _Fenetre.quatreVingtDix =>
              (j[i].date.day == 1 || j[i].date.day == 15)
                  ? '${j[i].date.day}'
                  : '',
          },
          valeur: j[i].gross,
          accent: _offset == 0 &&
              j[i].date.day == aujourdhui.day &&
              j[i].date.month == aujourdhui.month,
        ),
    ];
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ UI Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: _body());
  }

  Widget _body() {
    if (_loading && _missions.isEmpty && _resume == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _missions.isEmpty && _resume == null) {
      return Center(
        child: SingleChildScrollView(
          child: ErrorState(message: _error!, onRetry: () => _charger()),
        ),
      );
    }

    final jours = _jours_;
    final brut = jours.fold<int>(0, (a, d) => a + d.gross);
    final commission = jours.fold<int>(0, (a, d) => a + d.commission);
    final net = brut - commission;

    final ms = _missions.where((m) => _dans(m.createdAt)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final tx = (_wallet?.transactions ?? const <WalletTransaction>[])
        .where((t) => _dans(t.createdAt))
        .toList();
    final terminees =
        ms.where((m) => m.status == MissionStatus.completed).length;
    final r = _resume;
    final gutter = context.gutter;

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _entete(brut, commission, net),
          ContentWidth(
            maxWidth: 800,
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProviderWalletCard(
                    snap: _wallet,
                    onTap: () => context.push(ProviderRoutes.wallet),
                  ),
                  if (_erreurResume != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: SoftCard(
                        onTap: () => _chargerResume(),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_off_rounded),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '$_erreurResume Touchez pour rÃƒÂ©essayer.',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SectionTitle('EncaissÃƒÂ© par jour'),
                  SoftCard(
                    child: _chargementResume && r == null
                        ? const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : _Graphique(barres: _barres()),
                  ),
                  const SectionTitle('DÃƒÂ©tail'),
                  SoftCard(
                    child: Column(
                      children: [
                        InfoRow(
                          icon: Icons.payments_rounded,
                          label: 'EncaissÃƒÂ©',
                          value: TravelFee.fcfa(brut),
                        ),
                        InfoRow(
                          icon: Icons.percent_rounded,
                          label: 'Commission MonTotem',
                          value: TravelFee.fcfa(commission),
                        ),
                        InfoRow(
                          icon: Icons.savings_rounded,
                          label: 'Net estimÃƒÂ©',
                          value: formaterFcfaSigne(net),
                        ),
                        InfoRow(
                          icon: Icons.task_alt_rounded,
                          label: 'DÃƒÂ©pannages terminÃƒÂ©s',
                          value: '$terminees',
                        ),
                        if (_offset == 0 && r != null) ...[
                          InfoRow(
                            icon: Icons.two_wheeler_rounded,
                            label: 'Courses en espÃƒÂ¨ces (${r.ridesCashCount})',
                            value: TravelFee.fcfa(r.ridesCashFcfa),
                          ),
                          InfoRow(
                            icon: Icons.phone_android_rounded,
                            label: 'Courses Mobile Money (${r.ridesMomoCount})',
                            value: TravelFee.fcfa(r.ridesMomoFcfa),
                          ),
                          InfoRow(
                            icon: Icons.route_rounded,
                            label: 'Frais de dÃƒÂ©placement',
                            value: TravelFee.fcfa(r.travelGrossFcfa),
                          ),
                          InfoRow(
                            icon: Icons.build_circle_outlined,
                            label: 'RÃƒÂ©parations',
                            value: TravelFee.fcfa(r.repairGrossFcfa),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (ms.isEmpty && tx.isEmpty && brut == 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 28),
                      child: EmptyState(
                        icon: Icons.payments_outlined,
                        title: 'Aucun gain sur cette pÃƒÂ©riode',
                        message: 'Vos interventions payÃƒÂ©es apparaÃƒÂ®tront ici.',
                      ),
                    ),
                  if (ms.isNotEmpty) ...[
                    const SectionTitle('Interventions'),
                    for (final m in ms.take(30)) _ligneMission(m),
                  ],
                  if (tx.isNotEmpty) ...[
                    const SectionTitle('Mouvements du portefeuille'),
                    for (final t in tx.take(30)) _ligneTx(t),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _entete(int brut, int commission, int net) {
    final gutter = context.gutter;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mes gains',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      for (final f in _Fenetre.values) ...[
                        if (f != _Fenetre.values.first)
                          const SizedBox(width: 8),
                        Expanded(child: _pastille(f)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        iconSize: 30,
                        color: Colors.white,
                        disabledColor: Colors.white24,
                        tooltip: 'PÃƒÂ©riode prÃƒÂ©cÃƒÂ©dente',
                        icon: const Icon(Icons.chevron_left_rounded),
                        onPressed:
                            _offset >= _maxOffset ? null : () => _decaler(1),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            _libelleFenetre,
                            style: const TextStyle(
                              color: AppColors.navyOnDark,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        iconSize: 30,
                        color: Colors.white,
                        disabledColor: Colors.white24,
                        tooltip: 'PÃƒÂ©riode suivante',
                        icon: const Icon(Icons.chevron_right_rounded),
                        onPressed: _offset == 0 ? null : () => _decaler(-1),
                      ),
                    ],
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      TravelFee.fcfa(brut),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 44,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    'Commission ${TravelFee.fcfa(commission)} Ã‚Â· '
                    'Net ${formaterFcfaSigne(net)}',
                    style: const TextStyle(
                      color: AppColors.navyOnDark,
                      fontSize: 16,
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

  Widget _pastille(_Fenetre f) {
    final choisi = f == _fenetre;
    return Semantics(
      button: true,
      selected: choisi,
      label: 'PÃƒÂ©riode : ${f.libelle}',
      excludeSemantics: true,
      child: Material(
        color: choisi ? Colors.white : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => _changerFenetre(f),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            child: Text(
              f.libelle,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: choisi ? AppColors.navy : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ligneMission(Mission m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        onTap: () async {
          await context.push('/provider/mission/${m.id}');
          if (mounted) _charger(silencieux: true);
        },
        child: Row(
          children: [
            Icon(m.status.icone,
                color: context.readable(m.status.couleur), size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.problem,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  Text('${_jourCourt(m.createdAt)} Ã‚Â· ${_hm(m.createdAt)}',
                      style: TextStyle(
                          fontSize: 14, color: context.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(TravelFee.fcfa(m.paidFcfa),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: context.readable(AppTheme.successColor))),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  Widget _ligneTx(WalletTransaction t) {
    final credit = t.estCredit;
    final couleur = credit ? AppTheme.successColor : AppTheme.errorColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: couleur.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                credit
                    ? Icons.add_card_rounded
                    : Icons.remove_circle_outline_rounded,
                color: context.readable(couleur),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.libelle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w800)),
                  Text('${_jourCourt(t.createdAt)} Ã‚Â· ${_hm(t.createdAt)}',
                      style: TextStyle(
                          fontSize: 13.5, color: context.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${credit ? '+' : ''}${formaterFcfaSigne(t.amountFcfa)}',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: context.readable(couleur)),
                ),
                Text('Solde ${formaterFcfaSigne(t.balanceAfter)}',
                    style:
                        TextStyle(fontSize: 13, color: context.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Barre {
  const _Barre({
    required this.titre,
    required this.libelle,
    required this.valeur,
    this.accent = false,
  });

  final String titre;
  final String libelle;
  final int valeur;
  final bool accent;
}

/// Histogramme : valeurs affichÃƒÂ©es seulement pour 7 barres ou moins.
class _Graphique extends StatelessWidget {
  const _Graphique({required this.barres});

  final List<_Barre> barres;

  static String _court(int v) {
    if (v <= 0) return '';
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    }
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    if (barres.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Aucune donnÃƒÂ©e.', style: TextStyle(fontSize: 15)),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final maxVal = barres.fold<int>(1, (a, b) => b.valeur > a ? b.valeur : a);
    final peu = barres.length <= 7;

    return SizedBox(
      height: 170,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final b in barres)
            Expanded(
              child: Tooltip(
                message: '${b.titre} : ${TravelFee.fcfa(b.valeur)}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: 16,
                      child: ((peu || b.accent) && b.valeur > 0)
                          ? FittedBox(
                              child: Text(
                                _court(b.valeur),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: context.textSecondary,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: peu ? 5 : 0.5),
                      height: (b.valeur / maxVal * 100)
                          .clamp(3.0, 100.0)
                          .toDouble(),
                      decoration: BoxDecoration(
                        color: b.valeur == 0
                            ? scheme.onSurface.withValues(alpha: 0.10)
                            : (b.accent
                                ? AppTheme.successColor
                                : scheme.primary.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(peu ? 6 : 1),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 18,
                      child: b.libelle.isEmpty
                          ? null
                          : FittedBox(
                              child: Text(
                                b.libelle,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w800),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
