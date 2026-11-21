
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:montotem/core/theme/app_colors.dart';

/// Surface de frappe minimale des boutons SOS (dp).
const double _sosMinTap = 52;

RoundedRectangleBorder get _sosShape =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

/// Bouton SOS pour les barres d'application (Ã¢â€°Â¥ 52 dp, texte 19 px gras :
/// blanc sur #D32F2F = 4,98:1, AAA Ã‚Â« gros texte Ã‚Â»).
class SosAppBarButton extends StatelessWidget {
  const SosAppBarButton({super.key});

  @override
  Widget build(BuildContext context) {
    // La barre d'application a une hauteur fixe : on borne l'agrandissement
    // du texte de CE bouton pour qu'il ne dÃƒÂ©borde jamais.
    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1,
      maxScaleFactor: 1.2,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Semantics(
          button: true,
          label: 'Urgence SOS. Ouvrir les secours',
          excludeSemantics: true,
          onTap: () => context.push('/sos'),
          child: FilledButton.icon(
            onPressed: () => context.push('/sos'),
            icon: const Icon(Icons.emergency_rounded, size: 24),
            label: const Text('SOS'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.emergency,
              foregroundColor: Colors.white,
              minimumSize: const Size(96, _sosMinTap),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: _sosShape,
              elevation: 2,
              textStyle: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Grande banniÃƒÂ¨re SOS pour les pages d'accueil.
/// Fond rouge profond : tout le texte blanc atteint 7,85:1 (AAA).
class SosBanner extends StatelessWidget {
  const SosBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return Semantics(
      button: true,
      label:
          'Urgence vitale. Accident, pompiers, police, ambulance. Ouvrir le SOS',
      excludeSemantics: true,
      onTap: () => context.push('/sos'),
      child: Material(
        color: AppColors.emergencyStrong,
        elevation: 4,
        shadowColor: AppColors.emergencyStrong.withValues(alpha: 0.5),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: () => context.push('/sos'),
          child: const Padding(
            padding: EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(Icons.emergency_rounded, color: Colors.white, size: 44),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Urgence vitale ?',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900)),
                      SizedBox(height: 2),
                      Text(
                          'Accident, pompiers, police, ambulance : appuyez ici',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              height: 1.3)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: Colors.white, size: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lien SOS pour les ÃƒÂ©crans de connexion et d'inscription (Ã¢â€°Â¥ 52 dp,
/// rouge profond AAA : 7,25:1 sur fond clair).
class SosLink extends StatelessWidget {
  const SosLink({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TextButton.icon(
      onPressed: () => context.push('/sos'),
      icon: const Icon(Icons.emergency_rounded, size: 24),
      label: const Text('Urgence ? SOS'),
      style: TextButton.styleFrom(
        foregroundColor:
            dark ? AppColors.emergencyTextDark : AppColors.emergencyStrong,
        minimumSize: const Size(64, _sosMinTap),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
      ),
    );
  }
}

/// SOS OMNIPRÃƒâ€°SENT : pastille rouge flottante, visible sur TOUS les ÃƒÂ©crans
/// (accueil, carte, connexion, profil, adminÃ¢â‚¬Â¦) et accessible en 1 seul geste.
///
/// - se masque toute seule sur /sos et /emergency (inutile d'y ÃƒÂªtre) ;
/// - se masque quand le clavier est ouvert ;
/// - se dÃƒÂ©place verticalement au glisser (pour ne rien cacher d'important) ;
/// - ne dÃƒÂ©pend PAS du contexte GoRouter (placÃƒÂ©e au-dessus du Navigator,
///   dans `MaterialApp.router(builder: Ã¢â‚¬Â¦)`) : la navigation passe par [onSos].
class SosOverlay extends StatefulWidget {
  const SosOverlay({
    super.key,
    required this.child,
    required this.routerListenable,
    required this.currentPath,
    required this.onSos,
    this.hiddenPrefixes = const ['/sos', '/emergency'],
  });

  final Widget child;

  /// Ex. `AppRouter.router.routerDelegate` (notifie ÃƒÂ  chaque navigation).
  final Listenable routerListenable;

  /// Ex. `() => AppRouter.router.routerDelegate.currentConfiguration.uri.path`
  final String Function() currentPath;

  /// Ex. `() => AppRouter.router.push('/sos')`
  final VoidCallback onSos;

  final List<String> hiddenPrefixes;

  @override
  State<SosOverlay> createState() => _SosOverlayState();
}

class _SosOverlayState extends State<SosOverlay> {
  /// Position verticale, en fraction de la hauteur de l'ÃƒÂ©cran.
  double _pos = 0.42;

  static const double _size = 64;

  bool _masque(String path) =>
      widget.hiddenPrefixes.any((p) => path == p || path.startsWith('$p/'));

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: AnimatedBuilder(
            animation: widget.routerListenable,
            builder: (context, _) {
              String path;
              try {
                path = widget.currentPath();
              } catch (_) {
                path = '/';
              }
              final clavier = MediaQuery.viewInsetsOf(context).bottom > 0;
              if (_masque(path) || clavier) return const SizedBox.shrink();

              return LayoutBuilder(
                builder: (context, c) {
                  final safe = MediaQuery.paddingOf(context);
                  final minTop = safe.top + 72;
                  final maxTop = (c.maxHeight - safe.bottom - 168)
                      .clamp(minTop, double.infinity)
                      .toDouble();
                  final top =
                      (c.maxHeight * _pos).clamp(minTop, maxTop).toDouble();

                  return Stack(
                    children: [
                      Positioned(
                        right: 10,
                        top: top,
                        child: _SosFab(
                          onTap: widget.onSos,
                          onDrag: (dy) => setState(() {
                            _pos = (_pos + dy / c.maxHeight).clamp(0.12, 0.88);
                          }),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SosFab extends StatelessWidget {
  const _SosFab({required this.onTap, required this.onDrag});

  final VoidCallback onTap;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    // Taille de texte figÃƒÂ©e : le cercle de 64 dp doit toujours contenir Ã‚Â« SOS Ã‚Â».
    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1,
      maxScaleFactor: 1,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
        child: Semantics(
          button: true,
          label: 'Urgence SOS. Ouvrir les secours',
          excludeSemantics: true,
          onTap: onTap,
          child: Material(
            color: AppColors.emergency,
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.5),
            shape: const CircleBorder(
              side: BorderSide(color: Colors.white, width: 3),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                HapticFeedback.mediumImpact();
                onTap();
              },
              child: const SizedBox(
                width: _SosOverlayState._size,
                height: _SosOverlayState._size,
                child: Center(
                  child: Text(
                    'SOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
