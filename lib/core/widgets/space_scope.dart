import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:montotem/core/theme/app_space.dart';
import 'package:montotem/core/theme/space_theme.dart';

/// Espace courant (client / prestataire / admin) pour les widgets en dessous.
class SpaceScope extends InheritedWidget {
  const SpaceScope({super.key, required this.space, required super.child});

  final AppSpace space;

  /// Client par défaut si aucun espace n'est déclaré au-dessus.
  static AppSpace of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SpaceScope>()?.space ??
      AppSpace.client;

  @override
  bool updateShouldNotify(SpaceScope oldWidget) => oldWidget.space != space;
}

Uri _currentUri(GoRouter router) {
  try {
    return router.routerDelegate.currentConfiguration.uri;
  } catch (_) {
    return Uri();
  }
}

/// Applique le thème de l'espace correspondant à la route affichée.
/// À placer autour du Navigator, dans `MaterialApp.router(builder: ...)`.
class SpaceThemed extends StatelessWidget {
  const SpaceThemed({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final platform = MediaQuery.platformBrightnessOf(context);
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) {
        final space = AppSpaces.fromUri(_currentUri(router));
        return SpaceScope(
          space: space,
          child: Theme(data: SpaceTheme.of(space, platform), child: child),
        );
      },
    );
  }
}

/// Fond plein écran qui suit l'espace (évite une bande de l'ancienne couleur
/// sur les très grands écrans). Le paramètre [color] est conservé pour rester
/// compatible avec l'ancien `ColoredBox` de `main.dart` ; il est ignoré.
class SpaceBackdrop extends StatelessWidget {
  const SpaceBackdrop({
    super.key,
    required this.router,
    required this.color,
    required this.child,
  });

  final GoRouter router;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final platform = MediaQuery.platformBrightnessOf(context);
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) {
        final space = AppSpaces.fromUri(_currentUri(router));
        return ColoredBox(
          color: SpaceTheme.of(space, platform).scaffoldBackgroundColor,
          child: child,
        );
      },
    );
  }
}
