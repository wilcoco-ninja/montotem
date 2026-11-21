
import 'package:flutter/material.dart';

import 'package:montotem/core/flavor/app_flavor.dart';
import 'package:montotem/core/theme/app_space.dart';
import 'package:montotem/core/theme/totem_icons.dart';

/// Ãƒâ€°cran d'accueil affichÃƒÂ© pendant le chargement initial.
/// Le design change selon l'app (client / driver / pro).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final flavor = AppFlavor.current;
    final (bg, fg, glyph, titre, sousTitre) = switch (flavor) {
      AppFlavor.client => (
          SpaceColors.clientBg,
          SpaceColors.clientPrimary,
          TotemGlyph.mark,
          'MonTotem',
          'Un dÃƒÂ©panneur, pas loin de vous',
        ),
      AppFlavor.driver => (
          SpaceColors.driverBg,
          SpaceColors.driverAccent,
          TotemGlyph.zemidjan,
          'MonTotem Driver',
          'Vos courses, votre route',
        ),
      AppFlavor.pro => (
          SpaceColors.proBg,
          SpaceColors.proAccent,
          TotemGlyph.depannage,
          'MonTotem Pro',
          'Votre atelier, vos clients',
        ),
    };

    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TotemIcon(glyph, size: 120, color: fg, accent: fg),
            const SizedBox(height: 24),
            Text(
              titre,
              style: TextStyle(
                color: fg,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              sousTitre,
              style: TextStyle(
                color: fg.withValues(alpha: 0.75),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
