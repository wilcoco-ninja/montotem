import 'package:flutter/material.dart';

import 'package:montotem/core/utils/responsive.dart';

class AdaptiveDestination {
  const AdaptiveDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.showBadge = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool showBadge;
}

Widget _destinationIcon(IconData data, bool badge) =>
    badge ? Badge(smallSize: 10, child: Icon(data)) : Icon(data);

/// Téléphone : barre de navigation basse.
/// Tablette : rail latéral (étendu avec libellés dès 1024 dp).
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.body,
    this.floatingActionButton,
    this.maxContentWidth = 1100,
  }) : assert(destinations.length >= 2);

  final List<AdaptiveDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final Widget? floatingActionButton;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final size = context.screenSize;

    if (size == ScreenSize.compact) {
      return Scaffold(
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: _destinationIcon(d.icon, d.showBadge),
                selectedIcon: _destinationIcon(d.selectedIcon, d.showBadge),
                label: d.label,
              ),
          ],
        ),
      );
    }

    final extended = size == ScreenSize.expanded;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Row(
          children: [
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      extended: extended,
                      minExtendedWidth: 232,
                      labelType: extended
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      selectedIndex: currentIndex,
                      onDestinationSelected: onDestinationSelected,
                      backgroundColor: scheme.surface,
                      indicatorColor: scheme.primary.withValues(alpha: 0.14),
                      selectedIconTheme: IconThemeData(color: scheme.onSurface),
                      unselectedIconTheme: IconThemeData(
                        color: scheme.onSurfaceVariant,
                      ),
                      selectedLabelTextStyle: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                      unselectedLabelTextStyle: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      leading: extended
                          ? Padding(
                              padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
                              child: Text(
                                'MONTOTEM',
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2.4,
                                ),
                              ),
                            )
                          : const SizedBox(height: 8),
                      destinations: [
                        for (final d in destinations)
                          NavigationRailDestination(
                            icon: _destinationIcon(d.icon, d.showBadge),
                            selectedIcon: _destinationIcon(
                              d.selectedIcon,
                              d.showBadge,
                            ),
                            label: Text(d.label),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            VerticalDivider(
              width: 1,
              color: scheme.onSurface.withValues(alpha: 0.12),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxContentWidth),
                  child: body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
