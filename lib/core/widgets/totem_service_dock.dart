
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/totem_icons.dart';

/// Barre de services MonTotem ÃƒÂ  poser sur l'accueil client (au-dessus ou
/// sous la carte) : ZÃƒÂ©midjan, Kloboto, DÃƒÂ©pannage, Remorquage, SOS.
///
/// Exemple dans `home_screen.dart` :
/// ```dart
/// TotemServiceDock(
///   onZemidjan: () => context.push('/ride/request?kind=zemidjan'),
///   onKloboto: () => context.push('/ride/request?kind=tricycle_fret'),
///   onDepannage: () => context.push('/matching'),
///   onRemorquage: () => context.push('/matching'),
///   onSos: () => context.push('/sos'),
/// )
/// ```
/// Adaptez les chemins ÃƒÂ  vos routes de courses.
class TotemServiceDock extends StatelessWidget {
  const TotemServiceDock({
    super.key,
    required this.onZemidjan,
    required this.onKloboto,
    required this.onDepannage,
    required this.onRemorquage,
    required this.onSos,
  });

  final VoidCallback onZemidjan;
  final VoidCallback onKloboto;
  final VoidCallback onDepannage;
  final VoidCallback onRemorquage;
  final VoidCallback onSos;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1,
      maxScaleFactor: 1.3,
      child: SizedBox(
        height: 104,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            _Tuile(
              glyphe: TotemGlyph.zemidjan,
              libelle: 'ZÃƒÂ©midjan',
              accent: scheme.secondary,
              onTap: onZemidjan,
            ),
            _Tuile(
              glyphe: TotemGlyph.kloboto,
              libelle: 'Kloboto',
              accent: scheme.secondary,
              onTap: onKloboto,
            ),
            _Tuile(
              glyphe: TotemGlyph.depannage,
              libelle: 'DÃƒÂ©pannage',
              accent: scheme.secondary,
              onTap: onDepannage,
            ),
            _Tuile(
              glyphe: TotemGlyph.remorquage,
              libelle: 'Remorquage',
              accent: scheme.secondary,
              onTap: onRemorquage,
            ),
            _Tuile(
              glyphe: TotemGlyph.sos,
              libelle: 'SOS',
              accent: AppColors.emergency,
              fond: AppColors.emergencyStrong,
              texte: AppColors.navyOnDark,
              onTap: onSos,
            ),
          ],
        ),
      ),
    );
  }
}

class _Tuile extends StatelessWidget {
  const _Tuile({
    required this.glyphe,
    required this.libelle,
    required this.accent,
    required this.onTap,
    this.fond,
    this.texte,
  });

  final TotemGlyph glyphe;
  final String libelle;
  final Color accent;
  final VoidCallback onTap;
  final Color? fond;
  final Color? texte;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = texte ?? scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      child: Semantics(
        button: true,
        label: libelle,
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          color: fond ?? scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: fond ?? scheme.outline),
          ),
          child: InkWell(
            customBorder:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: SizedBox(
              width: 92,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TotemIcon(glyphe, size: 44, color: fg, accent: accent),
                  const SizedBox(height: 6),
                  Text(
                    libelle,
                    maxLines: 1,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13.5,
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
