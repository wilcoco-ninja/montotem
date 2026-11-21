
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/core/widgets/auth_layout.dart';
import 'package:montotem/features/auth/data/auth_service.dart';

/// Ãƒâ€°cran de debug, neutralisÃƒÂ© hors mode debug.
class DebugLoginScreen extends StatelessWidget {
  const DebugLoginScreen({super.key});

  Future<void> _loginAndNavigate(
    BuildContext context,
    String route,
    String email,
  ) async {
    if (!kDebugMode) return;
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: 'TestPassword123!',
      );
      if (context.mounted) context.go(route);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ãƒâ€°chec de la connexion debug : $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const Scaffold(
        body: Center(child: Text('Ãƒâ€°cran dÃƒÂ©sactivÃƒÂ© en production.')),
      );
    }

    return AuthShell(
      title: 'Navigation rapide',
      subtitle: 'Mode dÃƒÂ©veloppement uniquement',
      icon: Icons.bug_report_outlined,
      onBack: () => context.go('/login'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthInfoBanner(
            title: 'Mode dÃƒÂ©veloppement',
            message: 'Connexion directe avec des comptes de test.',
            icon: Icons.warning_amber_rounded,
            color: AppTheme.errorColor,
          ),
          const SizedBox(height: 18),
          _DebugNavButton(
            icon: Icons.person_outline_rounded,
            label: 'Interface Client',
            description: 'Accueil, matching, demandes',
            color: AppTheme.primaryColor,
            onTap: () => _loginAndNavigate(
              context,
              '/home',
              'client_test@example.com',
            ),
          ),
          const SizedBox(height: 12),
          _DebugNavButton(
            icon: Icons.build_outlined,
            label: 'Interface Prestataire',
            description: 'Demandes, profil',
            color: AppTheme.secondaryDark,
            onTap: () => _loginAndNavigate(
              context,
              '/provider/home',
              'provider_test@example.com',
            ),
          ),
          const SizedBox(height: 12),
          _DebugNavButton(
            icon: Icons.admin_panel_settings_outlined,
            label: 'Interface Admin',
            description: 'Dashboard, validation',
            color: Colors.deepPurple,
            onTap: () => _loginAndNavigate(
              context,
              '/admin/dashboard',
              'admin_test@example.com',
            ),
          ),
          const SizedBox(height: 22),
          AppButton(
            label: 'RÃƒÂ©initialiser la session',
            icon: Icons.logout_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: () async {
              final auth = AuthService();
              await auth.signOutAdmin();
              await auth.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}

class _DebugNavButton extends StatelessWidget {
  const _DebugNavButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return SoftCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: color),
        ],
      ),
    );
  }
}
