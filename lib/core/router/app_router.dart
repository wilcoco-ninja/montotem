import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Admin ──────────────────────────────────────────────────────────────
import 'package:montotem/features/admin/presentation/admin_control_tower_screen.dart';
import 'package:montotem/features/admin/presentation/admin_finance_screen.dart';
import 'package:montotem/features/admin/presentation/admin_dashboard_screen.dart';
import 'package:montotem/features/admin/presentation/admin_leaderboard_screen.dart';
import 'package:montotem/features/admin/presentation/admin_notifications_screen.dart';
import 'package:montotem/features/admin/presentation/admin_revenue_screen.dart';
import 'package:montotem/features/admin/presentation/admin_providers_screen.dart';
import 'package:montotem/features/admin/presentation/admin_settings_screen.dart';
import 'package:montotem/features/admin/presentation/admin_tracking_screen.dart';
import 'package:montotem/features/admin/presentation/admin_users_screen.dart';
import 'package:montotem/features/admin/presentation/admin_reports_screen.dart';
import 'package:montotem/features/admin/presentation/admin_rides_screen.dart';
import 'package:montotem/features/admin/presentation/admin_roles_screen.dart';
import 'package:montotem/features/admin/presentation/admin_topups_screen.dart';

// ── Auth & Onboarding ──────────────────────────────────────────────────
import 'package:montotem/features/auth/presentation/admin_login_screen.dart';
import 'package:montotem/features/auth/presentation/client_auth_screen.dart';
import 'package:montotem/features/auth/presentation/client_registration_screen.dart';
import 'package:montotem/features/auth/presentation/debug_login_screen.dart';
import 'package:montotem/features/auth/presentation/otp_verify_screen.dart';
import 'package:montotem/features/auth/presentation/password_setup_screen.dart';
import 'package:montotem/features/auth/presentation/phone_entry_screen.dart';
import 'package:montotem/features/auth/presentation/pro_login_screen.dart';
import 'package:montotem/features/auth/presentation/quick_name_screen.dart';
import 'package:montotem/features/auth/presentation/quick_signup_screen.dart';
import 'package:montotem/features/auth/presentation/role_selection_screen.dart';

// ── Urgence & SOS ──────────────────────────────────────────────────────
import 'package:montotem/features/emergency/data/emergency_places_repository.dart';
import 'package:montotem/features/emergency/domain/emergency_models.dart';
import 'package:montotem/features/emergency/presentation/emergency_route_screen.dart';
import 'package:montotem/features/emergency/presentation/emergency_services_screen.dart';
import 'package:montotem/features/emergency/presentation/sos_screen.dart';

// ── Client & Carte ─────────────────────────────────────────────────────
import 'package:montotem/features/map/presentation/matching_screen.dart';
import 'package:montotem/features/map/presentation/map_home_screen.dart';
import 'package:montotem/features/home/presentation/client_profile_screen.dart';

import 'package:montotem/features/payment/presentation/payment_screen.dart';
import 'package:montotem/features/requests/presentation/client_request_detail_screen.dart';
import 'package:montotem/features/requests/presentation/mes_demandes_screen.dart';
import 'package:montotem/features/requests/presentation/nouvelle_demande_screen.dart';

// ── Prestataire ────────────────────────────────────────────────────────
import 'package:montotem/features/provider/presentation/provider_catalog_screen.dart';
import 'package:montotem/features/provider/presentation/provider_identity_screen.dart';
import 'package:montotem/features/provider/presentation/provider_mission_screen.dart';
import 'package:montotem/features/provider/presentation/provider_registration_screen.dart';
import 'package:montotem/features/provider/presentation/provider_skills_screen.dart';
import 'package:montotem/features/provider/presentation/provider_shell.dart';
import 'package:montotem/features/rides/presentation/provider_ride_screen.dart';
import 'package:montotem/features/rides/presentation/provider_rides_screen.dart';
import 'package:montotem/features/rides/presentation/ride_request_screen.dart';
import 'package:montotem/features/rides/domain/ride_model.dart';
import 'package:montotem/features/wallet/presentation/provider_wallet_screen.dart';
import 'package:montotem/features/tracking/domain/prestataire_model.dart';

// ── Extensions Totem ───────────────────────────────────────────────────
import 'totem_routes.dart';

class AppRouter {
  AppRouter._();

  static bool? _adminCache;
  static String? _roleCache;
  static final _AuthRefresh _refresh = _AuthRefresh();

  static const List<String> _publics = [
    '/',
    '/explore',
    '/welcome',
    '/join',
    '/login',
    '/pro',
    '/pro/login',
    '/pro/register',
    '/forgot-password',
    // Route debug reservee au build development (jamais en release).
    if (!kReleaseMode) '/debug',
    '/admin/login',
    '/sos',
    '/emergency',
    '/survie',
  ];

  static bool _estPublic(String path) {
    if (_publics.contains(path)) return true;
    if (path.startsWith('/register')) return true;
    if (path.startsWith('/emergency/')) return true;
    return false;
  }

  static Future<String?> _redirectGuard(
    BuildContext context,
    GoRouterState state,
  ) async {
    final loc = state.matchedLocation;
    final session = Supabase.instance.client.auth.currentSession;

    // 1. Racine '/' : la carte s'ouvre pour tout le monde (comme Google Maps).
    //    Seuls les prestataires / admins web sont aiguillés vers leur espace.
    if (loc == '/explore') return '/';
    if (loc == '/') {
      if (session == null) return null;
      final dest = await _aiguillerApresConnexion();
      return dest == '/home' ? null : dest;
    }

    if (_estPublic(loc)) return null;

    if (session == null) {
      if (loc.startsWith('/admin')) return '/admin/login';
      if (loc.startsWith('/provider')) return '/pro/login';
      return '/login';
    }

    if (loc.startsWith('/admin') && !await _estAdmin()) {
      return '/home';
    }

    if (loc.startsWith('/provider')) {
      final role = await _role();
      if (role != null && role != 'provider') return '/home';
    } else if (_estEcranClient(loc)) {
      final role = await _role();
      if (role == 'provider') return '/provider/home';
    }

    return null;
  }

  static const List<String> _ecransClient = [
    '/home',
    '/matching',
    '/nouvelle-demande',
    '/mes-demandes',
    '/account',
    '/ride/new',
  ];

  static bool _estEcranClient(String path) =>
      _ecransClient.any((p) => path == p || path.startsWith('$p/'));

  static Future<String?> _role() async {
    if (_roleCache != null) return _roleCache;
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return null;
      final row = await client
          .from('profiles')
          .select('role')
          .eq('id', uid)
          .maybeSingle();
      _roleCache = row?['role']?.toString();
      return _roleCache;
    } catch (_) {
      return null;
    }
  }

  static Future<String> _aiguillerApresConnexion() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      // '/home' redirige vers '/' : on évite la boucle '/explore' → '/'.
      if (uid == null) return '/home';

      final row = await client
          .from('profiles')
          .select('role, inscription_complete')
          .eq('id', uid)
          .maybeSingle();

      if (row == null || row['inscription_complete'] != true) {
        return '/register/role';
      }

      final role = row['role']?.toString();
      return switch (role) {
        'provider' => '/provider/home',
        'admin' => kIsWeb ? '/admin/dashboard' : '/home',
        _ => '/home',
      };
    } catch (_) {
      return '/home';
    }
  }

  static Future<bool> _estAdmin() async {
    if (_adminCache != null) return _adminCache!;
    try {
      final result = await Supabase.instance.client.rpc('is_admin');
      _adminCache = result == true;
      return _adminCache!;
    } catch (_) {
      return false;
    }
  }

  static final GoRouter router = GoRouter(
    initialLocation: '/',
    refreshListenable: _refresh,
    redirect: _redirectGuard,
    errorBuilder: (context, state) =>
        _PageIntrouvable(chemin: state.uri.toString()),
    routes: [
      GoRoute(path: '/', builder: (_, __) => const MapHomeScreen()),
      GoRoute(path: '/explore', redirect: (_, __) => '/'),
      GoRoute(path: '/welcome', redirect: (_, __) => '/login'),
      GoRoute(path: '/login', builder: (_, __) => const ClientAuthScreen()),

      GoRoute(path: '/pro', redirect: (_, __) => '/pro/login'),
      GoRoute(path: '/pro/login', builder: (_, __) => const ProLoginScreen()),
      GoRoute(
        path: '/pro/register',
        redirect: (_, __) => '/register/signup?role=provider',
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (_, __) => const PasswordSetupScreen(isReset: true),
      ),
      // Ecran debug : uniquement en development, absent des builds release.
      if (!kReleaseMode)
        GoRoute(path: '/debug', builder: (_, __) => const DebugLoginScreen()),
      GoRoute(
        path: '/admin/login',
        builder: (_, __) => const AdminLoginScreen(),
      ),

      GoRoute(path: '/join', builder: (_, __) => const RoleSelectionScreen()),
      GoRoute(
        path: '/register/role',
        builder: (_, __) => const RoleSelectionScreen(),
      ),
      GoRoute(
        path: '/register/quick',
        builder: (_, __) => const ClientAuthScreen(),
      ),
      GoRoute(
        path: '/register/quick/name',
        builder: (_, __) => const QuickNameScreen(),
      ),
      GoRoute(
        path: '/register/phone',
        builder: (_, s) =>
            PhoneEntryScreen(role: s.uri.queryParameters['role']),
      ),
      GoRoute(
        path: '/register/verify-phone',
        builder: (_, s) => OtpVerifyScreen(
          // Sur le web, `extra` est perdu au rechargement : repli sur le paramètre d'URL.
          phone: s.extra as String? ?? s.uri.queryParameters['phone'] ?? '',
          role: s.uri.queryParameters['role'],
        ),
      ),
      GoRoute(
        path: '/register/signup',
        builder: (_, s) =>
            QuickSignupScreen(role: s.uri.queryParameters['role']),
      ),
      GoRoute(
        path: '/register/password',
        builder: (_, __) => const PasswordSetupScreen(),
      ),
      GoRoute(
        path: '/register/client',
        builder: (_, __) => const ClientRegistrationScreen(),
      ),

      // ── Routes personnalisées / étendues (totemRoutes) ───────────────
      ...totemRoutes,

      GoRoute(
        path: '/register/provider/classic',
        builder: (_, __) => const ProviderRegistrationScreen(),
      ),

      GoRoute(
        path: '/sos',
        builder: (_, s) {
          final t = s.uri.queryParameters['type'];
          final type = EmergencyType.values
              .where((e) => e.name == t)
              .firstOrNull;
          return SosScreen(initialType: type);
        },
      ),
      GoRoute(
        path: '/emergency',
        builder: (_, __) => const EmergencyServicesScreen(),
      ),
      GoRoute(
        path: '/emergency/route',
        builder: (_, s) {
          final lieu = s.extra;
          if (lieu is! EmergencyPlace) return const EmergencyServicesScreen();
          return EmergencyRouteScreen(lieu: lieu);
        },
      ),

      // Après connexion, le client revient sur la carte.
      GoRoute(path: '/home', redirect: (_, __) => '/'),
      GoRoute(
        path: '/account',
        builder: (_, __) => const ClientProfileScreen(),
      ),
      GoRoute(path: '/matching', builder: (_, __) => const MatchingScreen()),
      GoRoute(
        path: '/ride/new',
        builder: (_, s) => RideRequestScreen(
          kind: s.uri.queryParameters['kind'] == 'tricycle_fret'
              ? RideKind.tricycleFret
              : RideKind.zemidjan,
        ),
      ),
      GoRoute(
        path: '/nouvelle-demande',
        builder: (_, s) {
          final p = s.extra;
          if (p is! Prestataire) return const MatchingScreen();
          return NouvelleDemandeScreen(prestataire: p);
        },
      ),
      GoRoute(
        path: '/mes-demandes',
        builder: (_, __) => const MesDemandesScreen(),
      ),
      GoRoute(
        path: '/mes-demandes/:id',
        builder: (_, s) =>
            ClientRequestDetailScreen(requestId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/payment', builder: (_, __) => const PaymentScreen()),

      GoRoute(
        path: '/provider/home',
        builder: (_, __) => const ProviderShell(),
      ),
      GoRoute(
        path: '/provider/earnings',
        builder: (_, __) => const ProviderShell(initialTab: 1),
      ),
      GoRoute(
        path: '/provider/catalog',
        builder: (_, __) => const ProviderCatalogScreen(),
      ),
      GoRoute(
        path: '/provider/profile',
        builder: (_, __) => const ProviderShell(initialTab: 2),
      ),
      GoRoute(
        path: '/provider/identity',
        builder: (_, __) => const ProviderIdentityScreen(),
      ),
      GoRoute(
        path: '/provider/mission/:id',
        builder: (_, s) =>
            ProviderMissionScreen(missionId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/provider/competences',
        builder: (_, __) => const ProviderSkillsScreen(),
      ),
      GoRoute(
        path: '/provider/wallet',
        builder: (_, __) => const ProviderWalletScreen(),
      ),
      GoRoute(
        path: '/provider/rides',
        builder: (_, __) => const ProviderRidesScreen(),
      ),
      GoRoute(
        path: '/provider/rides/:id',
        builder: (_, s) => ProviderRideScreen(rideId: s.pathParameters['id']!),
      ),

      // ── Routes Administrateur ────────────────────────────────────────
      GoRoute(
        path: '/admin/dashboard',
        builder: (_, __) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/admin/control',
        builder: (_, s) => AdminControlTowerScreen(
          initialTab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/admin/users',
        builder: (_, __) => const AdminUsersScreen(),
      ),
      GoRoute(
        path: '/admin/providers',
        builder: (_, __) => const AdminProvidersScreen(),
      ),
      GoRoute(
        path: '/admin/revenue',
        builder: (_, __) => const AdminRevenueScreen(),
      ),
      GoRoute(
        path: '/admin/tracking',
        builder: (_, __) => const AdminTrackingScreen(),
      ),
      GoRoute(
        path: '/admin/leaderboard',
        builder: (_, __) => const AdminLeaderboardScreen(),
      ),
      GoRoute(
        path: '/admin/notifications',
        builder: (_, __) => const AdminNotificationsScreen(),
      ),
      GoRoute(
        path: '/admin/settings',
        builder: (_, __) => const AdminSettingsScreen(),
      ),
      GoRoute(
        path: '/admin/reports',
        builder: (_, __) => const AdminReportsScreen(),
      ),
      GoRoute(
        path: '/admin/rides',
        builder: (_, __) => const AdminRidesScreen(),
      ),
      GoRoute(
        path: '/admin/roles',
        builder: (_, __) => const AdminRolesScreen(),
      ),
      GoRoute(
        path: '/admin/topups',
        builder: (_, __) => const AdminTopupsScreen(),
      ),
      GoRoute(
        path: '/admin/finance',
        builder: (_, __) => const AdminFinanceScreen(),
      ),
    ],
  );
}

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      AppRouter._adminCache = null;
      AppRouter._roleCache = null;
      notifyListeners();
    });
  }

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

class _PageIntrouvable extends StatelessWidget {
  const _PageIntrouvable({required this.chemin});

  final String chemin;

  @override
  Widget build(BuildContext context) {
    const double size = 64;
    return Scaffold(
      appBar: AppBar(title: const Text('Page introuvable')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_rounded, size: size),
              const SizedBox(height: 16),
              Text(
                "Cette page n'existe pas :\n$chemin",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.home_rounded),
                label: const Text("Retour à l'accueil"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final GoRouter appRouter = AppRouter.router;
