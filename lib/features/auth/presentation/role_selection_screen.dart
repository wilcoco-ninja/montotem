
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/auth_layout.dart';

/// ClÃƒÂ© locale lue par l'inscription prestataire : un Ã‚Â« zem Ã‚Â» arrive avec le
/// mÃƒÂ©tier Ã‚Â« ZÃƒÂ©midjan jaune Ã‚Â» dÃƒÂ©jÃƒÂ  choisi.
const String kSignupMetierKey = 'signup_metier';

enum _Profil { client, prestataire, zem }

/// Ã‚Â« Rejoindre MonTotem Ã‚Â» : le visiteur choisit ce qu'il veut devenir.
///
///  - Client       : je cherche un dÃƒÂ©panneur ;
///  - Prestataire  : mÃƒÂ©canicien, vulcanisateur, ÃƒÂ©lectricien, garage, station ;
///  - Zem          : conducteur de moto-taxi (zÃƒÂ©midjan jaune).
///
/// Servi par /join (visiteur) et /register/role (compte connectÃƒÂ© dont
/// l'inscription n'est pas terminÃƒÂ©e).
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  _Profil? _choix;
  bool _busy = false;

  bool get _connecte => Supabase.instance.client.auth.currentSession != null;

  Future<void> _continuer() async {
    final choix = _choix;
    if (choix == null || _busy) return;
    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (choix == _Profil.zem) {
        await prefs.setString(kSignupMetierKey, 'ZÃƒÂ©midjan jaune');
      } else {
        await prefs.remove(kSignupMetierKey);
      }
    } catch (_) {
      // Sans stockage local, le zem choisira son mÃƒÂ©tier ÃƒÂ  l'ÃƒÂ©tape 2.
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final route = switch ((choix, _connecte)) {
      (_Profil.client, false) => '/register/quick?role=client',
      (_Profil.client, true) => '/register/client',
      (_, false) => '/register/signup?role=provider',
      (_, true) => '/register/provider',
    };
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return AuthShell(
      title: 'Rejoindre\nMonTotem',
      subtitle: 'Que voulez-vous faire ? Touchez votre profil.',
      icon: Icons.waving_hand_outlined,
      onBack: _busy ? null : () => context.go(_connecte ? '/' : '/explore'),
      footer: _connecte
          ? null
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('DÃƒÂ©jÃƒÂ  inscrit ?', style: TextStyle(color: muted)),
                TextButton(
                  onPressed: _busy ? null : () => context.go('/login'),
                  child: const Text(
                    'Se connecter',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CarteProfil(
            icone: Icons.person_search_rounded,
            titre: 'Client',
            texte: 'Je suis en panne : je cherche un dÃƒÂ©panneur prÃƒÂ¨s de moi.',
            choisi: _choix == _Profil.client,
            onTap: () => setState(() => _choix = _Profil.client),
          ),
          const SizedBox(height: 10),
          _CarteProfil(
            icone: Icons.build_circle_outlined,
            titre: 'Prestataire',
            texte: 'MÃƒÂ©canicien, vulcanisateur, ÃƒÂ©lectricien, garage ou '
                'station : je reÃƒÂ§ois des demandes.',
            choisi: _choix == _Profil.prestataire,
            onTap: () => setState(() => _choix = _Profil.prestataire),
          ),
          const SizedBox(height: 10),
          _CarteProfil(
            icone: Icons.two_wheeler_rounded,
            titre: 'Zem',
            texte: 'ZÃƒÂ©midjan jaune : je transporte les clients ÃƒÂ  moto.',
            choisi: _choix == _Profil.zem,
            onTap: () => setState(() => _choix = _Profil.zem),
          ),
          const SizedBox(height: 14),
          Text(
            'Ce choix ne se change pas seul ensuite : contactez le support '
            'si besoin.',
            style: TextStyle(fontSize: 12, height: 1.4, color: muted),
          ),
          const SizedBox(height: 18),
          AppButton(
            label: 'Continuer',
            icon: Icons.arrow_forward_rounded,
            loading: _busy,
            onPressed: _choix == null ? null : _continuer,
          ),
        ],
      ),
    );
  }
}

class _CarteProfil extends StatelessWidget {
  const _CarteProfil({
    required this.icone,
    required this.titre,
    required this.texte,
    required this.choisi,
    required this.onTap,
  });

  final IconData icone;
  final String titre;
  final String texte;
  final bool choisi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final couleur = scheme.primary;

    return Semantics(
      button: true,
      selected: choisi,
      label: '$titre. $texte',
      excludeSemantics: true,
      child: Material(
        color: choisi ? couleur.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: choisi ? couleur : scheme.outline,
                width: choisi ? 2 : 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: couleur.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icone, color: couleur, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titre,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        texte,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  choisi
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: choisi ? couleur : scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
