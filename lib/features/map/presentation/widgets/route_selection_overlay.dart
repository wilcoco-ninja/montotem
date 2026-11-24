import 'package:flutter/material.dart';

import 'package:montotem/core/services/routing_service.dart';
import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/theme/app_theme.dart';

/// Choix d'itinÃƒÂ©raire avec alternatives (affichÃƒÂ© dans un bottom sheet).
class RouteSelectionOverlay extends StatelessWidget {
  const RouteSelectionOverlay({
    super.key,
    required this.routes,
    required this.selectedIndex,
    required this.onRouteSelected,
    required this.originName,
    required this.destinationName,
    required this.onClose,
  });

  final List<RouteResult> routes;
  final int selectedIndex;
  final ValueChanged<int> onRouteSelected;
  final String originName;
  final String destinationName;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final choisie = routes[selectedIndex.clamp(0, routes.length - 1)];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.directions_rounded, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ItinÃƒÂ©raires disponibles',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '$originName Ã¢â€ â€™ $destinationName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Fermer',
                    onPressed: onClose,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < routes.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RouteOption(
                            route: routes[i],
                            index: i,
                            selected: i == selectedIndex,
                            best: i == 0,
                            onTap: () => onRouteSelected(i),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _InfoItem(
                      icon: Icons.route_rounded,
                      value: choisie.summary,
                      label: 'Distance',
                    ),
                    _InfoItem(
                      icon: Icons.directions_car_outlined,
                      value: choisie.formattedDuration,
                      label: 'Voiture',
                    ),
                    _InfoItem(
                      icon: Icons.two_wheeler_outlined,
                      value: RouteResult.formatDuration(choisie.motorcycleTime),
                      label: 'Moto (estimÃƒÂ©)',
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

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 13.5, color: context.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _RouteOption extends StatelessWidget {
  const _RouteOption({
    required this.route,
    required this.index,
    required this.selected,
    required this.best,
    required this.onTap,
  });

  final RouteResult route;
  final int index;
  final bool selected;
  final bool best;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final accent = theme.colorScheme.primary;
    final radius = BorderRadius.circular(AppTheme.radiusMd);

    return InkWell(
      borderRadius: radius,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.08) : null,
          borderRadius: radius,
          border: Border.all(
            color: selected ? accent : onSurface.withValues(alpha: 0.2),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? accent : onSurface.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: Colors.white,
                    )
                  : Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: onSurface.withValues(alpha: 0.8),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        route.formattedDuration,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: selected ? accent : onSurface,
                        ),
                      ),
                      if (best)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.successColor.withValues(
                              alpha: 0.14,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Le plus rapide',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: context.readable(AppTheme.successColor),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    route.summary,
                    style: TextStyle(
                      fontSize: 15,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.navigation_rounded,
              size: 22,
              color: selected ? accent : onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
