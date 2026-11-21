
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/totem_icons.dart';

/// DEUX PORTES Ã¢â‚¬â€ premiÃƒÂ¨re question aprÃƒÂ¨s le code SMS d'un futur prestataire.
///
/// Un conducteur de moto et un garagiste n'ont ni le mÃƒÂªme mÃƒÂ©tier, ni les
/// mÃƒÂªmes habitudes, ni le mÃƒÂªme formulaire : on les sÃƒÂ©pare dÃƒÂ¨s la premiÃƒÂ¨re
/// seconde, avec deux univers visuels distincts.
///
///   porte 1 Ã‚Â· CONDUCTEUR  Ã¢â€ â€™ /register/transport
///        ZÃƒÂ©midjan ou Tricycle Kloboto. Univers Ã‚Â« Cockpit Ã‚Â» : asphalte noir,
///        jaune safran, boutons biseautÃƒÂ©s, route de progression.
///
///   porte 2 Ã‚Â· DÃƒâ€°PANNEUR   Ã¢â€ â€™ /register/provider/depannage
///        MÃƒÂ©canicien, vulcanisateur, ÃƒÂ©lectricien, station, garage.
///        Univers Ã‚Â« Atelier Ã‚Â» : l'inscription en ÃƒÂ©tapes dÃƒÂ©jÃƒÂ  existante.
class ProviderKindChoiceScreen extends StatelessWidget {
  const ProviderKindChoiceScreen({super.key});

  static const Color _atelier = Color(0xFFFF8A1F);
  static const Color _onAtelier = Color(0xFF1A1206); // 7,9:1

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = Theme.of(context).colorScheme.onSurface;
    final soft = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Retour',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/welcome'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                Row(
                  children: [
                    const TotemIcon(TotemGlyph.mark, size: 40),
                    const SizedBox(width: 12),
                    Text(
                      'MONTOTEM Ã‚Â· PRO',
                      style: TextStyle(
                        fontSize: 13.5,
                        letterSpacing: 2.4,
                        fontWeight: FontWeight.w900,
                        color: dark ? AppColors.brandYellow : AppColors.navy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Quel est\nvotre mÃƒÂ©tier ?',
                  style: TextStyle(
                    fontSize: 36,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Deux inscriptions diffÃƒÂ©rentes, pensÃƒÂ©es pour chaque mÃƒÂ©tier.',
                  style: TextStyle(fontSize: 16, height: 1.4, color: soft),
                ),
                const SizedBox(height: 24),

                // Ã¢â€â‚¬Ã¢â€â‚¬ Porte 1 : Conducteur Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                _Porte(
                  fond: const Color(0xFF0D0F12),
                  bord: AppColors.brandYellow,
                  titre: 'JE CONDUIS',
                  sous:
                      'ZÃƒÂ©midjan ou Tricycle Kloboto.\nRecevez des courses autour de vous.',
                  couleurTitre: AppColors.brandYellow,
                  couleurTexte: const Color(0xFFF5F7FA),
                  biseaute: true,
                  icones: const [
                    TotemIcon(TotemGlyph.zemidjan,
                        size: 66,
                        color: Color(0xFFF5F7FA),
                        accent: AppColors.brandYellow),
                    TotemIcon(TotemGlyph.kloboto,
                        size: 66,
                        color: Color(0xFFF5F7FA),
                        accent: AppColors.success),
                  ],
                  etiquette: '4 ÃƒÂ©tapes Ã‚Â· 3 minutes',
                  onTap: () => context.go('/register/transport'),
                ),
                const SizedBox(height: 16),

                // Ã¢â€â‚¬Ã¢â€â‚¬ Porte 2 : DÃƒÂ©panneur Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                _Porte(
                  fond: _atelier,
                  bord: _atelier,
                  titre: 'JE DÃƒâ€°PANNE',
                  sous:
                      'MÃƒÂ©canicien, vulcanisateur, ÃƒÂ©lectricien, station, garage.\n'
                      'Recevez des demandes de dÃƒÂ©pannage.',
                  couleurTitre: _onAtelier,
                  couleurTexte: _onAtelier,
                  biseaute: false,
                  icones: const [
                    TotemIcon(TotemGlyph.depannage,
                        size: 66, color: _onAtelier, accent: _onAtelier),
                  ],
                  etiquette: 'Atelier Ã‚Â· prestations Ã‚Â· dÃƒÂ©placement',
                  onTap: () => context.go('/register/provider/depannage'),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: soft),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dans les deux cas, votre identitÃƒÂ© est vÃƒÂ©rifiÃƒÂ©e avant '
                        'les premiÃƒÂ¨res missions.',
                        style:
                            TextStyle(fontSize: 14, height: 1.35, color: soft),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Porte extends StatelessWidget {
  const _Porte({
    required this.fond,
    required this.bord,
    required this.titre,
    required this.sous,
    required this.couleurTitre,
    required this.couleurTexte,
    required this.biseaute,
    required this.icones,
    required this.etiquette,
    required this.onTap,
  });

  final Color fond;
  final Color bord;
  final String titre;
  final String sous;
  final Color couleurTitre;
  final Color couleurTexte;
  final bool biseaute;
  final List<Widget> icones;
  final String etiquette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ShapeBorder forme = biseaute
        ? BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(26),
            side: BorderSide(color: bord, width: 2.4),
          )
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(26));

    return Semantics(
      button: true,
      label: '$titre. $sous',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: fond,
        shape: forme,
        child: InkWell(
          customBorder: forme,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final i in icones) ...[i, const SizedBox(width: 10)],
                    const Spacer(),
                    Icon(Icons.arrow_forward_rounded,
                        color: couleurTitre, size: 34),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  titre,
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    color: couleurTitre,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  sous,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    color: couleurTexte,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  etiquette.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: couleurTexte.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
