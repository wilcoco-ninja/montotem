import 'package:flutter/widgets.dart';

enum ScreenSize { compact, medium, expanded }

/// Points de rupture : téléphone (< 600), tablette (600–1023), ordinateur (≥ 1024).
class Responsive {
  Responsive._();

  static const double mediumBreakpoint = 600;
  static const double expandedBreakpoint = 1024;

  static ScreenSize fromWidth(double width) {
    if (width >= expandedBreakpoint) return ScreenSize.expanded;
    if (width >= mediumBreakpoint) return ScreenSize.medium;
    return ScreenSize.compact;
  }

  static ScreenSize of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static bool isCompact(BuildContext context) =>
      of(context) == ScreenSize.compact;

  static double pagePadding(BuildContext context) => switch (of(context)) {
        ScreenSize.compact => 20,
        ScreenSize.medium => 28,
        ScreenSize.expanded => 32,
      };

  /// Nombre de colonnes d'une grille de cartes selon la taille d'écran.
  static int columns(
    BuildContext context, {
    int compact = 1,
    int medium = 2,
    int expanded = 3,
  }) =>
      switch (of(context)) {
        ScreenSize.compact => compact,
        ScreenSize.medium => medium,
        ScreenSize.expanded => expanded,
      };
}

/// Extension pratique sur BuildContext pour un accès fluide au responsive (`context.gutter`, `context.isCompact`).
extension ResponsiveContext on BuildContext {
  ScreenSize get screenSize => Responsive.of(this);
  bool get isCompactScreen => Responsive.isCompact(this);
  bool get isCompact => Responsive.isCompact(this);
  double get gutter => Responsive.pagePadding(this);
}

/// Grille adaptative pour disposer automatiquement les éléments selon la largeur d'écran.
class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 280,
    this.maxColumns,
    this.spacing = 12,
    this.runSpacing = 12,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int? maxColumns;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int cols = (width / minItemWidth).floor();
        if (cols < 1) cols = 1;
        if (maxColumns != null && cols > maxColumns!) {
          cols = maxColumns!;
        }

        if (cols <= 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: runSpacing),
                children[i],
              ],
            ],
          );
        }

        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final child in children)
              SizedBox(
                width: (width - (spacing * (cols - 1))) / cols,
                child: child,
              ),
          ],
        );
      },
    );
  }
}
