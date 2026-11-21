
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../power/power_mode_controller.dart';
import '../services/distress_service.dart';
import '../theme/totem_icons.dart';
import '../theme/app_colors.dart';

/// Enveloppe de TOUTE l'application (placÃƒÂ©e dans `MaterialApp.builder`).
///
/// Quand le tÃƒÂ©lÃƒÂ©phone est hors ligne ou que la batterie est faible, un
/// bandeau reste collÃƒÂ© en haut de chaque ÃƒÂ©cran, avec deux actions qui
/// marchent SANS internet :
///   1. Ã‚Â« SMS position Ã‚Â» : GPS + batterie dans un SMS prÃƒÂªt ÃƒÂ  envoyer ;
///   2. Ã‚Â« Kit Ã‚Â» : conseils de survie en panne (ÃƒÂ©cran 100 % hors ligne).
///
/// Le bandeau n'apparaÃƒÂ®t que s'il y a quelque chose ÃƒÂ  dire : en temps
/// normal, l'application est exactement comme avant.
class SurvivalShell extends StatelessWidget {
  const SurvivalShell({
    super.key,
    required this.child,
    required this.onOpenKit,
  });

  final Widget child;

  /// Ex. `() => AppRouter.router.push('/survie')` (le bandeau est au-dessus
  /// du Navigator : il n'a pas accÃƒÂ¨s au contexte GoRouter).
  final VoidCallback onOpenKit;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PowerModeController>();
    final visible = p.horsLigne || p.alerte != PowerLevel.normal;

    return Column(
      children: [
        if (visible) _Bandeau(power: p, onOpenKit: onOpenKit),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            // Le bandeau gÃƒÂ¨re dÃƒÂ©jÃƒÂ  l'encoche : on ÃƒÂ©vite le double dÃƒÂ©calage.
            removeTop: visible,
            child: child,
          ),
        ),
      ],
    );
  }
}

class _Bandeau extends StatelessWidget {
  const _Bandeau({required this.power, required this.onOpenKit});

  final PowerModeController power;
  final VoidCallback onOpenKit;

  @override
  Widget build(BuildContext context) {
    final critique = power.alerte == PowerLevel.critical;
    final bas = power.alerte == PowerLevel.low;
    final hors = power.horsLigne;

    // Couleurs : toutes Ã¢â€°Â¥ 7:1 (texte).
    final Color fond;
    final Color texte;
    if (critique) {
      fond = AppColors.emergencyStrong;
      texte = AppColors.navyOnDark;
    } else if (bas) {
      fond = AppColors.brandYellow;
      texte = AppColors.navy;
    } else {
      fond = AppColors.proSurface;
      texte = AppColors.proInk;
    }

    final String titre;
    final String detail;
    if (critique && hors) {
      titre = 'Batterie ${power.niveau} % Ã‚Â· sans internet';
      detail = 'Envoyez votre position par SMS maintenant.';
    } else if (critique) {
      titre = 'Batterie critique : ${power.niveau} %';
      detail = 'Envoyez votre position par SMS avant l\'extinction.';
    } else if (bas && hors) {
      titre = 'Batterie ${power.niveau} % Ã‚Â· sans internet';
      detail =
          'Ãƒâ€°conomie d\'ÃƒÂ©nergie activÃƒÂ©e. SMS et appels restent possibles.';
    } else if (bas) {
      titre = 'Batterie faible : ${power.niveau} %';
      detail = power.ecoActive
          ? 'Ãƒâ€°conomie d\'ÃƒÂ©nergie activÃƒÂ©e : ÃƒÂ©cran noir, animations coupÃƒÂ©es.'
          : 'Pensez ÃƒÂ  envoyer votre position si vous ÃƒÂªtes en difficultÃƒÂ©.';
    } else {
      titre = 'Pas d\'internet';
      detail = 'SMS et appels fonctionnent encore. Ouvrez le kit de survie.';
    }

    final Widget icone = hors && !critique && !bas
        ? TotemIcon(TotemGlyph.horsLigne,
            size: 30, color: texte, accent: AppColors.brandYellow)
        : TotemIcon(
            TotemGlyph.batterie,
            size: 34,
            color: texte,
            accent: texte,
            level: power.niveau / 100,
          );

    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1,
      maxScaleFactor: 1.3,
      child: Material(
        color: fond,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(
              children: [
                Semantics(excludeSemantics: true, child: icone),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        titre,
                        style: TextStyle(
                          color: texte,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                      Text(
                        detail,
                        style: TextStyle(
                          color: texte,
                          fontSize: 13.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _Action(
                  libelle: 'SMS position',
                  icone: Icons.sms_rounded,
                  fond: texte,
                  texte: fond,
                  onTap: () => DistressService.envoyerDetresse(context, power),
                ),
                const SizedBox(width: 6),
                _Action(
                  libelle: 'Kit',
                  icone: Icons.health_and_safety_rounded,
                  fond: texte.withValues(alpha: 0.18),
                  texte: texte,
                  onTap: onOpenKit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.libelle,
    required this.icone,
    required this.fond,
    required this.texte,
    required this.onTap,
  });

  final String libelle;
  final IconData icone;
  final Color fond;
  final Color texte;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: libelle,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: fond,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icone, color: texte, size: 22),
                  Text(
                    libelle,
                    maxLines: 1,
                    style: TextStyle(
                      color: texte,
                      fontSize: 11.5,
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
