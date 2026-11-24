import 'package:flutter/material.dart';

import 'package:montotem/core/services/routing_service.dart';
import 'package:montotem/core/theme/app_theme.dart';

/// SÃƒÂ©lection d'itinÃƒÂ©raire avec alternatives (affichÃƒÂ© dans un bottom sheet).
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
    final onSurface = theme.colorScheme.onSurface;
    final accent = theme.colorScheme.primary;
    final selectedRoute = routes[selectedIndex];

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
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
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
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '$originName Ã¢â€ â€™ $destinationName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: onSurface.withValues(alpha: 0.6),
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
                    children: routes.asMap().entries.map((entry) {
                      final index = entry.key;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _RouteOption(
                          route: entry.value,
                          index: index,
                          isSelected: index == selectedIndex,
                          isBest: index == 0,
                          onTap: () => onRouteSelected(index),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: onSurface.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _InfoItem(
                      icon: Icons.route_rounded,
                      value: selectedRoute.summary,
                      label: 'Distance',
                    ),
                    _InfoItem(
                      icon: Icons.directions_car_outlined,
                      value: selectedRoute.formattedDuration,
                      label: 'Voiture',
                    ),
                    _InfoItem(
                      icon: Icons.two_wheeler_outlined,
                      value: RouteResult.formatDuration(
                        selectedRoute.motorcycleTime,
                      ),
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
    final theme = Theme.of(context);
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
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
    required this.isSelected,
    required this.isBest,
    required this.onTap,
  });

  final RouteResult route;
  final int index;
  final bool isSelected;
  final bool isBest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final accent = theme.colorScheme.primary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(
            color: isSelected ? accent : onSurface.withValues(alpha: 0.12),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? accent : onSurface.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Colors.white,
                    )
                  : Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: onSurface.withValues(alpha: 0.6),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        route.formattedDuration,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isSelected ? accent : onSurface,
                        ),
                      ),
                      if (isBest) ...[
                        const SizedBox(width: 8),
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
                          child: const Text(
                            'Le plus rapide',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.secondaryDark,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    route.summary,
                    style: TextStyle(
                      fontSize: 13,
                      color: onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.navigation_rounded,
              size: 20,
              color: isSelected ? accent : onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
