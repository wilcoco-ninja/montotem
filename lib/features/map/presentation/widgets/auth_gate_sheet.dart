
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';

/// Les actions qui nÃƒÂ©cessitent un compte.
enum GatedAction {
  contacter,
  appeler,
  rendezVous,

  /// Voir les infos d'un prestataire ou d'un service prestataire.
  voirInfos,

  /// Commander une course en zÃƒÂ©midjan ou en kloboto.
  course,

  /// Demander un dÃƒÂ©pannage express.
  depannage,
}

extension on GatedAction {
  String get titre => switch (this) {
        GatedAction.contacter => 'Pour contacter ce rÃƒÂ©parateur',
        GatedAction.appeler => 'Pour appeler ce rÃƒÂ©parateur',
        GatedAction.rendezVous => 'Pour prendre rendez-vous',
        GatedAction.voirInfos => 'Pour voir les infos du prestataire',
        GatedAction.course => 'Pour commander votre course',
        GatedAction.depannage => 'Pour demander un dÃƒÂ©pannage',
      };
}

/// ExÃƒÂ©cute [onAllowed] si l'utilisateur est connectÃƒÂ© ; sinon ouvre la
/// bottom sheet d'inscription rapide (le visiteur garde sa carte en arriÃƒÂ¨re-plan).
Future<void> requireAuth(
  BuildContext context, {
  required GatedAction action,
  required VoidCallback onAllowed,
  String? prestataireNom,
}) async {
  if (Supabase.instance.client.auth.currentSession != null) {
    onAllowed();
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) =>
        AuthGateSheet(action: action, prestataireNom: prestataireNom),
  );
}

class AuthGateSheet extends StatelessWidget {
  const AuthGateSheet({super.key, required this.action, this.prestataireNom});

  final GatedAction action;
  final String? prestataireNom;

  void _aller(BuildContext context, String route) {
    final router = GoRouter.of(context);
    Navigator.pop(context);
    router.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bolt_rounded,
                    size: 32, color: AppTheme.primaryColor),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              action.titre,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            if (prestataireNom != null) ...[
              const SizedBox(height: 4),
              Text(
                prestataireNom!,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: onSurface.withValues(alpha: 0.6)),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Connectez-vous ou crÃƒÂ©ez votre compte en 30 secondes : un numÃƒÂ©ro '
              'de tÃƒÂ©lÃƒÂ©phone et un code SMS, rien de plus.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: onSurface.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 22),
            AppButton(
              label: 'Continuer avec mon numÃƒÂ©ro',
              icon: Icons.phone_iphone_rounded,
              onPressed: () => _aller(context, '/register/quick?role=client'),
            ),
            const SizedBox(height: 4),
            AppButton(
              label: 'Connexion avec mot de passe',
              variant: AppButtonVariant.text,
              onPressed: () => _aller(context, '/login'),
            ),
            AppButton(
              label: 'Continuer ÃƒÂ  explorer',
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
