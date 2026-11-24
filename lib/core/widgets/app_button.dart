import 'package:flutter/material.dart';

import 'package:montotem/core/theme/app_colors.dart';

enum AppButtonVariant { primary, secondary, danger, text }

/// Bouton unifié MONTOTEM : icône, état de chargement, variantes.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.variant = AppButtonVariant.primary,
    this.expand = true,
    this.semanticsLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final AppButtonVariant variant;
  final bool expand;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? action = loading ? null : onPressed;
    final scheme = Theme.of(context).colorScheme;

    final Color spinnerColor = switch (variant) {
      AppButtonVariant.primary => scheme.onPrimary,
      AppButtonVariant.danger => Colors.white,
      _ => scheme.primary,
    };

    final Widget child = loading
        ? SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: spinnerColor,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    final Widget button = switch (variant) {
      AppButtonVariant.primary => FilledButton(onPressed: action, child: child),
      AppButtonVariant.secondary => OutlinedButton(
        onPressed: action,
        child: child,
      ),
      AppButtonVariant.text => TextButton(onPressed: action, child: child),
      // ✅ Contraste AAA dans les 3 espaces (clair/sombre) :
      //    on utilise scheme.error qui suit le thème de l'espace.
      AppButtonVariant.danger => FilledButton(
        onPressed: action,
        style: FilledButton.styleFrom(
          backgroundColor: context.readable(scheme.error),
          foregroundColor: Colors.white,
          disabledBackgroundColor: scheme.error.withValues(alpha: 0.3),
        ),
        child: child,
      ),
    };

    final Widget sized = expand
        ? SizedBox(width: double.infinity, child: button)
        : button;

    if (semanticsLabel == null) return sized;
    return Semantics(
      button: true,
      enabled: action != null,
      onTap: action,
      label: semanticsLabel,
      excludeSemantics: true,
      child: sized,
    );
  }
}
