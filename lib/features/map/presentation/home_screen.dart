
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/widgets/app_ui.dart' show ContentWidth;
import '../../../core/widgets/client_ui.dart';
import '../../auth/data/auth_service.dart';
import '../../map/presentation/guest_map_screen.dart';
import '../../requests/data/mission_service.dart';
import '../../requests/domain/mission_model.dart';
import '../../requests/presentation/mes_demandes_screen.dart';
import '../../home/presentation/client_profile_screen.dart';

/// Espace client MONTOTEM : Accueil Ã‚Â· Carte Ã‚Â· ActivitÃƒÂ© Ã‚Â· Compte.
///
/// Accueil = une recherche (Ã‚Â« OÃƒÂ¹ allez-vous ? Ã‚Â»), quatre services, un rail
/// de vÃƒÂ©hicules pour le dÃƒÂ©pannage. Rien d'autre.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MissionService _missions = MissionService();
  final AuthService _auth = AuthService();
  final ValueNotifier<String?> _vehicleSignal = ValueNotifier<String?>(null);
  RealtimeChannel? _canal;

  int _tab = 0;
  bool _mapVisited = false;
  String? _vehiculeInitial;
  String? _prenom;
  Mission? _active;

  @override
  void initState() {
    super.initState();
    _chargerNom();
    _chargerMissions();
    _canal = _missions.ecouterMesMissions(() {
      if (mounted) _chargerMissions();
    });
  }

  @override
  void dispose() {
    _vehicleSignal.dispose();
    final c = _canal;
    if (c != null) _missions.arreter(c);
    super.dispose();
  }

  Future<void> _chargerNom() async {
    try {
      final user = await _auth.fetchCurrentUser();
      if (mounted) setState(() => _prenom = user?.firstName);
    } catch (_) {
      // Le message d'accueil reste gÃƒÂ©nÃƒÂ©rique.
    }
  }

  Future<void> _chargerMissions() async {
    try {
      final uid = _missions.currentUserId;
      final liste = await _missions.mesMissions();
      final actives = liste
          .where((m) =>
              m.clientId == uid &&
              (m.status.actif || m.status == MissionStatus.pending))
          .toList();
      if (mounted) {
        setState(() => _active = actives.isEmpty ? null : actives.first);
      }
    } on MissionException {
      // Affichage prÃƒÂ©cÃƒÂ©dent conservÃƒÂ©.
    }
  }

  void _allerA(int i) => setState(() {
        _tab = i;
        if (i == 1) _mapVisited = true;
      });

  void _ouvrirCarte([String? vehicle]) {
    final dejaCree = _mapVisited;
    setState(() {
      _mapVisited = true;
      _tab = 1;
      if (!dejaCree) _vehiculeInitial = vehicle;
    });
    if (dejaCree && vehicle != null) {
      _vehicleSignal.value = vehicle;
      _vehicleSignal.value = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 0);
      },
      child: ClientShell(
        index: _tab,
        onSelect: _allerA,
        items: [
          const ClientNavItem(
            label: 'Accueil',
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
          ),
          const ClientNavItem(
            label: 'Carte',
            icon: Icons.map_outlined,
            selectedIcon: Icons.map_rounded,
          ),
          ClientNavItem(
            label: 'ActivitÃƒÂ©',
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long_rounded,
            showBadge: _active != null,
          ),
          const ClientNavItem(
            label: 'Compte',
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
          ),
        ],
        body: IndexedStack(
          index: _tab,
          children: [
            _HomeTab(
              prenom: _prenom,
              active: _active,
              onOpenMap: _ouvrirCarte,
              onOpenTab: _allerA,
              onRefresh: _chargerMissions,
            ),
            _mapVisited
                ? GuestMapScreen(
                    initialVehicle: _vehiculeInitial,
                    vehicleSignal: _vehicleSignal,
                  )
                : const SizedBox.shrink(),
            const MesDemandesScreen(embedded: true),
            const ClientProfileScreen(),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Onglet Accueil
// ----------------------------------------------------------------------------

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.prenom,
    required this.active,
    required this.onOpenMap,
    required this.onOpenTab,
    required this.onRefresh,
  });

  final String? prenom;
  final Mission? active;
  final void Function([String? vehicle]) onOpenMap;
  final ValueChanged<int> onOpenTab;
  final Future<void> Function() onRefresh;

  static const _vehicules = [
    ('moto', 'Moto', Icons.two_wheeler_rounded),
    ('voiture', 'Auto', Icons.directions_car_rounded),
    ('camion', 'Camion', Icons.local_shipping_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nom = prenom?.trim() ?? '';
    final gutter = context.gutter;
    final mission = active;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (Theme.of(context).brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              ContentWidth(
                maxWidth: 640,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Ã¢â€â‚¬Ã¢â€â‚¬ En-tÃƒÂªte : salutation + avatar Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nom.isEmpty ? 'Bonjour' : 'Bonjour, $nom',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.6,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'OÃƒÂ¹ allons-nous aujourd\'hui ?',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: context.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          ClientAvatar(
                            name: nom,
                            radius: 24,
                            onTap: () => onOpenTab(3),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Ã¢â€â‚¬Ã¢â€â‚¬ Recherche Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                      ClientSearchPill(
                        label: 'OÃƒÂ¹ allez-vous ?',
                        onTap: () => context.push('/ride/new'),
                      ),

                      // Ã¢â€â‚¬Ã¢â€â‚¬ Demande en cours Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                      if (mission != null) ...[
                        const SizedBox(height: 16),
                        _CarteEnCours(
                          mission: mission,
                          onTap: () =>
                              context.push('/mes-demandes/${mission.id}'),
                        ),
                      ],

                      // Ã¢â€â‚¬Ã¢â€â‚¬ Services Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                      const ClientSectionTitle('Services'),
                      LayoutBuilder(
                        builder: (context, c) {
                          const gap = 12.0;
                          final w = (c.maxWidth - gap) / 2;
                          final tuiles = <Widget>[
                            ClientServiceTile(
                              icon: Icons.two_wheeler_rounded,
                              label: 'ZÃƒÂ©midjan',
                              subtitle: 'Moto-taxi, prix fixe',
                              color: scheme.primary,
                              onTap: () =>
                                  context.push('/ride/new?kind=zemidjan'),
                            ),
                            ClientServiceTile(
                              icon: Icons.local_shipping_rounded,
                              label: 'Tricycle Fret',
                              subtitle: 'Colis et marchandises',
                              color: const Color(0xFF00796B),
                              onTap: () =>
                                  context.push('/ride/new?kind=tricycle_fret'),
                            ),
                            ClientServiceTile(
                              icon: Icons.build_circle_rounded,
                              label: 'DÃƒÂ©pannage',
                              subtitle: 'Un pro vient ÃƒÂ  vous',
                              color: AppColors.gold,
                              onTap: () => onOpenMap(),
                            ),
                            ClientServiceTile(
                              icon: Icons.local_hospital_rounded,
                              label: 'Urgences',
                              subtitle: 'NumÃƒÂ©ros et secours',
                              color: AppColors.emergencyStrong,
                              onTap: () => context.push('/emergency'),
                            ),
                          ];
                          return Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              for (final t in tuiles)
                                SizedBox(width: w, child: t),
                            ],
                          );
                        },
                      ),

                      // Ã¢â€â‚¬Ã¢â€â‚¬ DÃƒÂ©pannage : rail de vÃƒÂ©hicules Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                      const ClientSectionTitle('Quel vÃƒÂ©hicule est en panne ?'),
                      Row(
                        children: [
                          for (var i = 0; i < _vehicules.length; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(
                              child: _VehiculeBouton(
                                icon: _vehicules[i].$3,
                                label: _vehicules[i].$2,
                                onTap: () => onOpenMap(_vehicules[i].$1),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
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

class _CarteEnCours extends StatelessWidget {
  const _CarteEnCours({required this.mission, required this.onTap});

  final Mission mission;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onPrimary;
    return ClientCard(
      color: scheme.primary,
      borderColor: scheme.primary,
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(mission.status.icone, color: fg, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Demande en cours',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: fg.withValues(alpha: 0.85),
                  ),
                ),
                Text(
                  mission.status.libelle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                Text(
                  '${mission.providerName} Ã‚Â· ${mission.problem}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: fg.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: fg),
        ],
      ),
    );
  }
}

class _VehiculeBouton extends StatelessWidget {
  const _VehiculeBouton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'VÃƒÂ©hicule : $label',
      excludeSemantics: true,
      child: ClientCard(
        onTap: onTap,
        radius: 20,
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Icon(icon, size: 34, color: scheme.onSurface),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
