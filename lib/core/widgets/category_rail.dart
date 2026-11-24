import 'package:flutter/material.dart';

import 'package:montotem/core/theme/app_colors.dart';

class Categorie {
  const Categorie(this.cle, this.label, this.icone);
  final String? cle;
  final String label;
  final IconData icone;
}

const kCategories = [
  Categorie(null, 'Tous', Icons.apps_rounded),
  Categorie('zemidjan', 'ZÃƒÂ©midjan', Icons.two_wheeler_rounded),
  Categorie('mecanicien', 'MÃƒÂ©canicien', Icons.build_rounded),
  Categorie('vulcanisateur', 'Pneus', Icons.tire_repair_rounded),
  Categorie(
    'electricien',
    'Ãƒâ€°lectricien',
    Icons.electrical_services_rounded,
  ),
  Categorie('station', 'Essence', Icons.local_gas_station_rounded),
  Categorie('garage', 'Garage', Icons.garage_rounded),
];

/// MÃƒÂªme logique que MatchingScreen : dÃƒÂ©duit la catÃƒÂ©gorie du texte du mÃƒÂ©tier.
bool metierCorrespond(String metier, String? cle) {
  if (cle == null) return true;
  final m = metier.toLowerCase();
  return switch (cle) {
    'zemidjan' => m.contains('zemidjan') || m.contains('zÃƒÂ©midjan'),
    'vulcanisateur' => m.contains('vulcanis') || m.contains('pneu'),
    'electricien' => m.contains('ÃƒÂ©lectric') || m.contains('electric'),
    'station' => m.contains('essence') || m.contains('station'),
    'garage' => m.contains('garage'),
    _ => m.contains('mÃƒÂ©canic') || m.contains('mecanic'),
  };
}

class CategoryRail extends StatelessWidget {
  const CategoryRail({
    super.key,
    required this.selection,
    required this.onChanged,
  });

  final String? selection;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = AppColors.brandYellow;
    // Texte sur jaune : navy (AAA 11,2:1).
    final onAccent = AppColors.navy;
    // Fond et texte "off" : dÃƒÂ©rivÃƒÂ©s du thÃƒÂ¨me de l'espace.
    final offBg = scheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final offFg = scheme.onSurface;
    final radius = theme.cardTheme.shape is RoundedRectangleBorder
        ? (theme.cardTheme.shape as RoundedRectangleBorder).borderRadius
              .resolve(TextDirection.ltr)
              .topLeft
              .x
        : 16.0;

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: kCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final c = kCategories[i];
          final on = c.cle == selection;
          return Semantics(
            button: true,
            selected: on,
            label: c.label,
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: () => onChanged(c.cle),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 84,
                decoration: BoxDecoration(
                  color: on ? accent : offBg,
                  borderRadius: BorderRadius.circular(radius),
                  border: on
                      ? null
                      : Border.all(
                          color: scheme.outline.withValues(alpha: 0.35),
                        ),
                  boxShadow: on
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.45),
                            blurRadius: 16,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(c.icone, size: 30, color: on ? onAccent : offFg),
                    const SizedBox(height: 6),
                    Text(
                      c.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: on ? onAccent : offFg,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
