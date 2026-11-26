import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:montotem/core/theme/app_colors.dart';

/// Bandeau proposé au client pendant l'attente d'une course ou d'un
/// dépannage : un robinet vers les coffres d'étoiles pour lire des blagues
/// et répondre à des devinettes pendant que le pro arrive ou travaille.
/// Légèrement animé (respiration) pour attirer l'œil sans gêner.
class FunWaitingBanner extends StatefulWidget {
  const FunWaitingBanner({super.key});

  @override
  State<FunWaitingBanner> createState() => _FunWaitingBannerState();
}

class _FunWaitingBannerState extends State<FunWaitingBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pouls = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
    lowerBound: 0.98,
    upperBound: 1.02,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pouls.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ScaleTransition(
      scale: _pouls,
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: AppColors.amber.withValues(alpha: 0.16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: AppColors.amber.withValues(alpha: 0.55)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/coffres'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const Text('🎭', style: TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Patientez en riant',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        "Blagues et devinettes dans vos coffres d'étoiles",
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
