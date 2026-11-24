import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/theme/app_space.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/utils/responsive.dart';
import 'package:montotem/core/widgets/space_decor.dart';

/// Structure commune des ÃƒÂ©crans d'authentification, avec UNE mise en page par
/// espace (l'espace vient de la route) :
///
///  - client      : fond ivoire, titre XXL, formulaire posÃƒÂ© sur la page
///                  (aucune carte), ondes indigo ; ÃƒÂ©cran large = hero indigo ;
///  - prestataire : fond sombre Ã‚Â« plan d'atelier Ã‚Â», bandeau PRO, formulaire
///                  dans un panneau ÃƒÂ  filet orange ;
///  - admin       : console sobre, rail sombre ÃƒÂ  gauche, carte compacte.
///
/// L'API (title, subtitle, icon, child, onBack, footer) est inchangÃƒÂ©e : tous
/// les ÃƒÂ©crans existants prennent automatiquement le bon visage.
class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.onBack,
    this.footer,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final VoidCallback? onBack;
  final Widget? footer;

  static const double _wideBreakpoint = 900;

  // Helper to detect space from current route
  static AppSpace _detectSpace(BuildContext context) {
    try {
      final router = GoRouter.of(context);
      final uri = router.routerDelegate.currentConfiguration.uri;
      // Simple heuristic based on path - same logic as AppSpaces.fromUri
      final p = uri.path;
      if (p == '/admin' || p.startsWith('/admin/')) return AppSpace.admin;
      if (p == '/provider' || p.startsWith('/provider/')) {
        return AppSpace.provider;
      }
      if (p == '/pro' || p.startsWith('/pro/')) return AppSpace.provider;
      if (p.startsWith('/register/provider')) return AppSpace.provider;
      if (p.startsWith('/register/transport')) return AppSpace.provider;
      if (p.startsWith('/register') &&
          uri.queryParameters['role'] == 'provider') {
        return AppSpace.provider;
      }
      return AppSpace.client;
    } catch (_) {
      return AppSpace.client;
    }
  }

  @override
  Widget build(BuildContext context) {
    final space = _detectSpace(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >= _wideBreakpoint &&
              constraints.maxHeight >= 560;
          return switch (space) {
            AppSpace.client => _ClientLayout(shell: this, wide: wide),
            AppSpace.provider => _ProviderLayout(shell: this, wide: wide),
            AppSpace.driver => _ProviderLayout(shell: this, wide: wide),
            AppSpace.admin => _AdminLayout(shell: this, wide: wide),
          };
        },
      ),
    );
  }
}

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// Briques communes
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

Widget _scrollColumn(
  BuildContext context, {
  required List<Widget> children,
  required double maxWidth,
  bool center = false,
}) {
  final pad = Responsive.pagePadding(context);
  final column = ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
  final body = SingleChildScrollView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: EdgeInsets.fromLTRB(pad, 12, pad, 32),
    child: Center(child: column),
  );
  return SafeArea(child: center ? Center(child: body) : body);
}

class _Back extends StatelessWidget {
  const _Back({
    required this.onPressed,
    required this.color,
    required this.shape,
  });

  final VoidCallback? onPressed;
  final Color color;
  final OutlinedBorder shape;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        onPressed: onPressed,
        tooltip: 'Retour',
        iconSize: 24,
        icon: const Icon(Icons.arrow_back_rounded),
        style: IconButton.styleFrom(
          foregroundColor: color,
          shape: shape,
          side: BorderSide(color: color.withValues(alpha: 0.35), width: 1.4),
          minimumSize: const Size(48, 48),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({
    required this.leading,
    required this.text,
    required this.color,
  });

  final Widget leading;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 40, child: leading),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// CLIENT
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

class _ClientLayout extends StatelessWidget {
  const _ClientLayout({required this.shell, required this.wide});

  final AuthShell shell;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = scheme.onSurface;
    final soft = scheme.onSurfaceVariant;
    final primary = scheme.primary;

    final form = _scrollColumn(
      context,
      center: wide,
      maxWidth: 460,
      children: [
        if (shell.onBack != null)
          _Back(
            onPressed: shell.onBack,
            color: ink,
            shape: const CircleBorder(),
          )
        else
          const SizedBox(height: 48),
        const SizedBox(height: 22),
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(shell.icon, size: 28, color: primary),
        ),
        const SizedBox(height: 18),
        Text(
          shell.title,
          style: TextStyle(
            color: ink,
            fontSize: 34,
            fontWeight: FontWeight.w900,
            height: 1.08,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          shell.subtitle,
          style: TextStyle(color: soft, fontSize: 16.5, height: 1.45),
        ),
        const SizedBox(height: 28),
        shell.child,
        if (shell.footer != null) ...[
          const SizedBox(height: 24),
          shell.footer!,
        ],
      ],
    );

    if (wide) {
      return Row(
        children: [
          Expanded(flex: 6, child: form),
          const Expanded(flex: 5, child: _ClientHero()),
        ],
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: RipplePainter(
                color: primary.withValues(alpha: 0.16),
                center: const Offset(1.0, 0.0),
                rings: 5,
                gap: 52,
              ),
            ),
          ),
        ),
        form,
      ],
    );
  }
}

class _ClientHero extends StatelessWidget {
  const _ClientHero();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.primary;
    final fg = scheme.onPrimary;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: ColoredBox(
          color: bg,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: RipplePainter(
                    color: fg.withValues(alpha: 0.22),
                    center: const Offset(0.82, 0.18),
                    rings: 9,
                    gap: 64,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wordmark(color: fg, size: 26),
                    const SizedBox(height: 22),
                    Text(
                      'Un dÃƒÂ©panneur,\nÃƒÂ  portÃƒÂ©e de main.',
                      style: TextStyle(
                        color: fg,
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        height: 1.08,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _Point(
                      leading: Icon(Icons.sell_outlined, color: fg, size: 26),
                      text: 'Prix affichÃƒÂ©s d\'avance, sans nÃƒÂ©gociation',
                      color: fg,
                    ),
                    _Point(
                      leading: Icon(
                        Icons.verified_outlined,
                        color: fg,
                        size: 26,
                      ),
                      text: 'Prestataires vÃƒÂ©rifiÃƒÂ©s prÃƒÂ¨s de vous',
                      color: fg,
                    ),
                    _Point(
                      leading: Icon(
                        Icons.phone_android_outlined,
                        color: fg,
                        size: 26,
                      ),
                      text: 'Paiement Mobile Money sÃƒÂ©curisÃƒÂ©',
                      color: fg,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// PRESTATAIRE
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: primary, width: 1.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'PRO',
        style: TextStyle(
          color: primary,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.5,
        ),
      ),
    );
  }
}

class _ProviderLayout extends StatelessWidget {
  const _ProviderLayout({required this.shell, required this.wide});

  final AuthShell shell;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = scheme.onSurface;
    final soft = scheme.onSurfaceVariant;
    final primary = scheme.primary;

    final panel = Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: 4, color: primary),
            Padding(padding: const EdgeInsets.all(20), child: shell.child),
          ],
        ),
      ),
    );

    final form = _scrollColumn(
      context,
      center: wide,
      maxWidth: 480,
      children: [
        Row(
          children: [
            if (shell.onBack != null)
              _Back(
                onPressed: shell.onBack,
                color: ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              )
            else
              const SizedBox(height: 48),
            const Spacer(),
            Wordmark(color: ink, accent: primary, size: 22),
            const SizedBox(width: 12),
            const _ProBadge(),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Icon(shell.icon, color: primary, size: 26),
            const SizedBox(width: 10),
            Container(width: 36, height: 3, color: primary),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          shell.title,
          style: TextStyle(
            color: ink,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            height: 1.1,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          shell.subtitle,
          style: TextStyle(color: soft, fontSize: 15.5, height: 1.45),
        ),
        const SizedBox(height: 24),
        panel,
        if (shell.footer != null) ...[
          const SizedBox(height: 22),
          shell.footer!,
        ],
      ],
    );

    final grid = GridPainter(color: scheme.outline.withValues(alpha: 0.45));

    if (wide) {
      return Row(
        children: [
          Expanded(
            flex: 5,
            child: ColoredBox(
              color: const Color(0xFF0A0D11),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: GridPainter(
                        color: scheme.outline.withValues(alpha: 0.35),
                        step: 40,
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(48),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Wordmark(color: ink, accent: primary, size: 26),
                              const SizedBox(width: 14),
                              const _ProBadge(),
                            ],
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Votre atelier,\nvos clients.',
                            style: TextStyle(
                              color: ink,
                              fontSize: 42,
                              fontWeight: FontWeight.w900,
                              height: 1.08,
                              letterSpacing: -1,
                            ),
                          ),
                          const SizedBox(height: 32),
                          for (final e in const [
                            (
                              '01',
                              'Vos prestations, vos prix : affichÃƒÂ©s au client',
                            ),
                            (
                              '02',
                              'Des missions prÃƒÂ¨s de vous, sans nÃƒÂ©gociation',
                            ),
                            (
                              '03',
                              'Frais de dÃƒÂ©placement payÃƒÂ©s avant votre dÃƒÂ©part',
                            ),
                          ])
                            _Point(
                              leading: Text(
                                e.$1,
                                style: TextStyle(
                                  color: primary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              text: e.$2,
                              color: ink,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(flex: 6, child: form),
        ],
      );
    }

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 280,
          child: IgnorePointer(child: CustomPaint(painter: grid)),
        ),
        form,
      ],
    );
  }
}

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// ADMIN
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

class _AdminLayout extends StatelessWidget {
  const _AdminLayout({required this.shell, required this.wide});

  final AuthShell shell;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = scheme.onSurface;
    final soft = scheme.onSurfaceVariant;
    final primary = scheme.primary;

    final card = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(shell.icon, size: 22, color: primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  shell.title,
                  style: TextStyle(
                    color: ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            shell.subtitle,
            style: TextStyle(color: soft, fontSize: 14.5, height: 1.45),
          ),
          const SizedBox(height: 20),
          Divider(color: scheme.outline),
          const SizedBox(height: 20),
          shell.child,
        ],
      ),
    );

    final form = _scrollColumn(
      context,
      center: true,
      maxWidth: 440,
      children: [
        if (!wide)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 20,
                    color: AppColors.navyOnDark,
                  ),
                ),
                const SizedBox(width: 10),
                Wordmark(color: ink, accent: primary, size: 20),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'CONSOLE',
                    style: TextStyle(
                      color: primary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        card,
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_clock_outlined, size: 16, color: soft),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'AccÃƒÂ¨s rÃƒÂ©servÃƒÂ© ÃƒÂ  l\'ÃƒÂ©quipe. Chaque connexion est journalisÃƒÂ©e.',
                style: TextStyle(color: soft, fontSize: 12.5, height: 1.4),
              ),
            ),
          ],
        ),
        if (shell.onBack != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: shell.onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Quitter la console'),
            ),
          ),
        ],
        if (shell.footer != null) ...[
          const SizedBox(height: 10),
          shell.footer!,
        ],
      ],
    );

    if (!wide) return form;

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: ColoredBox(
            color: AppColors.navy,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(44),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          color: AppColors.navyOnDark,
                          size: 26,
                        ),
                        const SizedBox(width: 12),
                        Wordmark(color: AppColors.navyOnDark, size: 24),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Console\nd\'administration',
                          style: TextStyle(
                            color: AppColors.navyOnDark,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 24),
                        for (final t in const [
                          'Validation des prestataires',
                          'Suivi des missions et des paiements',
                          'Connexions journalisÃƒÂ©es',
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_rounded,
                                  color: Color(0xFF7FD6C2),
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  t,
                                  style: const TextStyle(
                                    color: Color(0xFFD5E4E8),
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const Text(
                      'Espace non rÃƒÂ©fÃƒÂ©rencÃƒÂ© Ã‚Â· web uniquement',
                      style: TextStyle(
                        color: Color(0xFF8FB0B8),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(flex: 6, child: form),
      ],
    );
  }
}

// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â
// Bandeaux et en-tÃƒÂªtes rÃƒÂ©utilisÃƒÂ©s par tous les ÃƒÂ©crans (API inchangÃƒÂ©e)
// Ã¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢ÂÃ¢â€¢Â

/// Bandeau d'erreur discret et lisible.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = scheme.error;
    final fg = AppColors.ensureContrast(error, scheme.surface, min: 7.5);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: error.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: fg, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: fg,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bandeau d'information (ex. Ã‚Â« compte sÃƒÂ©curisÃƒÂ© Ã‚Â»).
class AuthInfoBanner extends StatelessWidget {
  const AuthInfoBanner({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.verified_user_outlined,
    this.color = AppColors.success,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fg = context.readable(color);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: fg, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.4,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// En-tÃƒÂªte de section ÃƒÂ  l'intÃƒÂ©rieur d'un formulaire.
class AuthSectionHeader extends StatelessWidget {
  const AuthSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// SÃƒÂ©parateur Ã‚Â« ou Ã‚Â» entre deux actions.
class AuthDividerLabel extends StatelessWidget {
  const AuthDividerLabel({super.key, this.label = 'ou'});
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Expanded(child: Divider(color: color.withValues(alpha: 0.12))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.6),
            ),
          ),
        ),
        Expanded(child: Divider(color: color.withValues(alpha: 0.12))),
      ],
    );
  }
}

/// RÃƒÂ¨gles de mot de passe avec validation visuelle en temps rÃƒÂ©el.
class PasswordRules extends StatelessWidget {
  const PasswordRules({super.key, required this.password});
  final String password;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _Rule(label: '8+ caractÃƒÂ¨res', ok: password.length >= 8),
        _Rule(label: '1 majuscule', ok: RegExp(r'[A-Z]').hasMatch(password)),
        _Rule(label: '1 chiffre', ok: RegExp(r'[0-9]').hasMatch(password)),
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule({required this.label, required this.ok});
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.onSurface;
    final okColor = theme.brightness == Brightness.dark
        ? AppColors.success
        : AppColors.successText;
    final color = ok ? okColor : base.withValues(alpha: 0.6);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Icon(
            ok ? Icons.check_circle_rounded : Icons.circle_outlined,
            key: ValueKey(ok),
            size: 15,
            color: color,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: ok ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
