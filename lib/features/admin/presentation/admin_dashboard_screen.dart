
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import 'package:montotem/core/accessibility/accessibility_controller.dart';
import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/requests/domain/mission_model.dart';
import 'package:montotem/features/admin/data/admin_control_service.dart';
import 'package:montotem/features/admin/data/admin_service.dart';
import 'package:montotem/features/admin/domain/admin_stats_model.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  static const List<String> listeJours = [
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
  ];
  static const List<String> listeMois = [
    'janvier',
    'fÃƒÂ©vrier',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'aoÃƒÂ»t',
    'septembre',
    'octobre',
    'novembre',
    'dÃƒÂ©cembre',
  ];

  final AdminService _adminService = AdminService();
  final AdminControlService _control = AdminControlService();
  RealtimeChannel? _canalNotifs;
  RealtimeChannel? _canalMissions;

  AdminDashboardStats? _stats;
  List<Map<String, dynamic>> _recentes = [];

  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _chargerDonnees();
    _initialiserCanauxTempsReel();
  }

  void _initialiserCanauxTempsReel() {
    try {
      _canalNotifs = _adminService.ecouterNotificationsAdmin(_surNotification);
      _canalMissions = _control.ecouter(
        'missions',
        () {
          if (mounted) _chargerDonnees(silencieux: true);
        },
        nom: 'admin-dash-missions-prod',
      );
    } catch (e) {
      debugPrint("Erreur d'initialisation des canaux temps rÃƒÂ©el : $e");
    }
  }

  @override
  void dispose() {
    if (_canalNotifs != null) _adminService.arreterEcoute(_canalNotifs!);
    if (_canalMissions != null) _control.arreter(_canalMissions!);
    super.dispose();
  }

  String _routePour(String type) => switch (type) {
        'payment_declared' => '/admin/control?tab=2',
        'topup_declared' => '/admin/topups',
        'provider_reported' => '/admin/reports',
        'mission_created' || 'mission_completed' => '/admin/control',
        _ => '/admin/providers',
      };

  void _surNotification(Map<String, dynamic> notif) {
    if (!mounted) return;
    final titre = '${notif['title'] ?? 'Nouvelle notification'}';
    final corps = '${notif['body'] ?? ''}';
    final type = '${notif['type'] ?? ''}';

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titre, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (corps.isNotEmpty)
                Text(corps, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
          ),
          action: SnackBarAction(
            label: 'Voir',
            onPressed: () => context.push(_routePour(type)),
          ),
        ),
      );
    _chargerDonnees(silencieux: true);
  }

  Future<void> _chargerDonnees({bool silencieux = false}) async {
    if (!mounted) return;
    if (!silencieux && _stats == null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else if (silencieux) {
      setState(() => _isRefreshing = true);
    }

    try {
      final results = await Future.wait<Object?>([
        _adminService.obtenirStatistiques(),
        _control.recentes().catchError(
              (_) => <Map<String, dynamic>>[],
            ),
      ]);

      if (!mounted) return;

      final stats = results[0] as AdminDashboardStats;
      final rawList = results[1];
      final List<Map<String, dynamic>> parsedRecentes = [];
      if (rawList is List) {
        for (final e in rawList) {
          if (e is Map) {
            parsedRecentes.add(Map<String, dynamic>.from(e));
          }
        }
      }

      setState(() {
        _stats = stats;
        _recentes = parsedRecentes;
        _isLoading = false;
        _isRefreshing = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erreur de synchronisation. RÃƒÂ©essayez.';
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  String _dateLongue() {
    final d = DateTime.now();
    final t =
        '${listeJours[d.weekday - 1]} ${d.day} ${listeMois[d.month - 1]} ${d.year}';
    return t[0].toUpperCase() + t.substring(1);
  }

  Widget _grille(
    List<Widget> items, {
    int grand = 3,
    int moyen = 2,
    int petit = 1,
  }) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols =
            c.maxWidth >= 1024 ? grand : (c.maxWidth >= 600 ? moyen : petit);
        final w = (c.maxWidth - 14 * (cols - 1)) / cols;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final i in items) SizedBox(width: w, child: i),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _stats == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Administration MonTotem')),
        body: const SkeletonList(count: 6, itemHeight: 100),
      );
    }

    if (_stats == null && _errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Administration MonTotem')),
        body: Center(
          child: SingleChildScrollView(
            child: ErrorState(
              message: _errorMessage!,
              onRetry: () => _chargerDonnees(),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _chargerDonnees(silencieux: true),
        child: _contenu(_stats!),
      ),
    );
  }

  Widget _contenu(AdminDashboardStats s) {
    return ListView(
      padding: EdgeInsets.zero,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _entete(),
        ContentWidth(
          maxWidth: 1280,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isRefreshing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                const SectionTitle('Urgences & Actions requises'),
                _grille(
                  [
                    _ActionCard(
                      icon: Icons.fact_check_outlined,
                      titre: 'Dossiers prestataires',
                      sousTitre: 'IdentitÃƒÂ© et garage ÃƒÂ  examiner',
                      count: s.pendingProviders,
                      color: Theme.of(context).colorScheme.error,
                      onTap: () => context.push('/admin/providers'),
                    ),
                    _ActionCard(
                      icon: Icons.flag_outlined,
                      titre: 'Signalements',
                      sousTitre: 'Plaintes de clients',
                      count: s.openReports,
                      color: Theme.of(context).colorScheme.error,
                      onTap: () => context.push('/admin/reports'),
                    ),
                  ],
                  moyen: 2,
                  grand: 3,
                ),
                const SizedBox(height: 20),
                _heroControle(),
                const SizedBox(height: 12),
                const SectionTitle('MÃƒÂ©triques & Indicateurs clÃƒÂ©s'),
                _grille(
                  [
                    KpiHero(
                      label: 'Revenus (30 jours)',
                      value: TravelFee.fcfa(s.revenue30dFcfa),
                      icon: Icons.trending_up_rounded,
                      onTap: () => context.push('/admin/revenue'),
                    ),
                    KpiHero(
                      label: 'Missions en direct',
                      value: '${s.activeRequests}',
                      icon: Icons.radar_rounded,
                      onTap: () => context.push('/admin/control'),
                    ),
                    KpiHero(
                      label: 'Clients inscrits',
                      value: '${s.totalUsers}',
                      icon: Icons.people_outline_rounded,
                    ),
                    KpiHero(
                      label: 'Prestataires actifs',
                      value: '${s.totalProviders}',
                      icon: Icons.build_outlined,
                      delta: s.pendingProviders > 0
                          ? '${s.pendingProviders} en attente'
                          : null,
                      deltaPositive: false,
                    ),
                    KpiHero(
                      label: 'Missions terminÃƒÂ©es',
                      value: '${s.completedRequests}',
                      icon: Icons.task_alt_rounded,
                    ),
                    KpiHero(
                      label: 'Signalements ouverts',
                      value: '${s.openReports}',
                      icon: Icons.flag_rounded,
                      delta: s.openReports > 0 ? '!' : null,
                      deltaPositive: false,
                      onTap: () => context.push('/admin/reports'),
                    ),
                  ],
                  moyen: 2,
                  grand: 3,
                ),
                const SizedBox(height: 16),
                const SectionTitle("Flux d'activitÃƒÂ© en temps rÃƒÂ©el"),
                if (_recentes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Aucune mission rÃƒÂ©cente en cours.',
                      style: TextStyle(
                        fontSize: 15,
                        color: context.textSecondary,
                      ),
                    ),
                  )
                else
                  ..._recentes.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _carteRecente(m),
                    ),
                  ),
                const SizedBox(height: 16),
                const SectionTitle('Modules de gestion'),
                _grille(
                  [
                    QuickTile(
                      icon: Icons.build_outlined,
                      label: 'Prestataires',
                      color: Theme.of(context).colorScheme.secondary,
                      onTap: () => context.push('/admin/providers'),
                    ),
                    QuickTile(
                      icon: Icons.account_balance_outlined,
                      label: 'Revenus MonTotem',
                      color: Theme.of(context).colorScheme.secondary,
                      onTap: () => context.push('/admin/revenue'),
                    ),
                    QuickTile(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Recharges wallet',
                      color: Theme.of(context).colorScheme.secondary,
                      onTap: () => context.push('/admin/topups'),
                    ),
                    QuickTile(
                      icon: Icons.map_outlined,
                      label: 'Suivi live',
                      color: Colors.teal,
                      onTap: () => context.push('/admin/tracking'),
                    ),
                    QuickTile(
                      icon: Icons.emoji_events_outlined,
                      label: 'Classement',
                      color: AppColors.gold,
                      onTap: () => context.push('/admin/leaderboard'),
                    ),
                    QuickTile(
                      icon: Icons.people_outline_rounded,
                      label: 'Utilisateurs',
                      color: Colors.deepPurple,
                      onTap: () => context.push('/admin/users'),
                    ),
                    QuickTile(
                      icon: Icons.settings_outlined,
                      label: 'ParamÃƒÂ¨tres admin',
                      color: Colors.blueGrey,
                      onTap: () => context.push('/admin/settings'),
                    ),
                    QuickTile(
                      icon: Icons.workspace_premium_outlined,
                      label: "Formules d'abonnement",
                      color: AppColors.gold,
                      onTap: () => context.push('/admin/plans'),
                    ),
                    QuickTile(
                      icon: Icons.admin_panel_settings_outlined,
                      label: 'RÃƒÂ´les & postes',
                      color: Colors.deepPurple,
                      onTap: () => context.push('/admin/roles'),
                    ),
                    QuickTile(
                      icon: Icons.flag_outlined,
                      label: 'Signalements',
                      color: Theme.of(context).colorScheme.error,
                      badge: s.openReports > 0 ? '${s.openReports}' : null,
                      onTap: () => context.push('/admin/reports'),
                    ),
                    QuickTile(
                      icon: Icons.two_wheeler_rounded,
                      label: 'Courses',
                      color: Theme.of(context).colorScheme.error,
                      onTap: () => context.push('/admin/rides'),
                    ),
                  ],
                  moyen: 3,
                  grand: 4,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _entete() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, AppColors.navySoft],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const PulseDot(color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'MON-TOTEM Ã¢â‚¬Â¢ PRODUCTION CONTROL',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.2,
                      ),
                    ),
                  ),
                  IconButton(
                    iconSize: 24,
                    color: Colors.white,
                    tooltip: 'AccessibilitÃƒÂ©',
                    icon: const Icon(Icons.text_increase_rounded),
                    onPressed: () => showAccessibilitySheet(context),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    iconSize: 24,
                    color: Colors.white,
                    tooltip: 'Actualiser',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => _chargerDonnees(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Tableau de bord central',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _dateLongue(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroControle() {
    final radius = BorderRadius.circular(22);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: () => context.push('/admin/control'),
        child: Ink(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E40AF), Color(0xFF2563EB)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ouvrir la Tour de ContrÃƒÂ´le',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Supervision gÃƒÂ©olocalisÃƒÂ©e en direct, gestion financiÃƒÂ¨re et arbitrage',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _carteRecente(Map<String, dynamic> m) {
    final s = MissionStatus.fromValue(m['status'] as String?);

    final Map<String, dynamic> client = m['client'] is Map
        ? Map<String, dynamic>.from(m['client'] as Map)
        : <String, dynamic>{};
    final Map<String, dynamic> prov = m['provider'] is Map
        ? Map<String, dynamic>.from(m['provider'] as Map)
        : <String, dynamic>{};

    final nom =
        '${client['first_name'] ?? ''}${client['last_name'] ?? ''}'.trim();
    final nomClient = nom.isEmpty ? 'Client' : nom;
    final nomProvider = '${prov['business_name'] ?? 'Prestataire'}';
    final total = ((m['travel_fee_fcfa'] as num?)?.toInt() ?? 0) +
        ((m['repair_fee_fcfa'] as num?)?.toInt() ?? 0);

    return SoftCard(
      onTap: () => context.push('/admin/control'),
      child: RailedRow(
        railColor: s.couleur,
        child: Row(
          children: [
            AvatarInline.fromName(
              nomClient,
              color: AppColors.navy,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (s.actif) ...[
                        const PulseDot(color: AppColors.success, size: 6),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          '${m['problem']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusPill(
                        label: s.libelle,
                        color: s.couleur,
                        dense: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$nomClient  Ã¢â€ â€™  $nomProvider',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: context.textSecondary,
                    ),
                  ),
                  if (total > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: MoneyText(
                        total,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
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

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.titre,
    required this.sousTitre,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String titre;
  final String sousTitre;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sousTitre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
