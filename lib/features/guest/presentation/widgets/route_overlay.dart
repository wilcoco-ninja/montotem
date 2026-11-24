import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:montotem/core/services/routing_service.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/widgets/app_ui.dart';

/// Overlay d'itinÃƒÂ©raire simple utilisable directement sur la carte.
class RouteOverlay extends StatelessWidget {
  const RouteOverlay({
    super.key,
    required this.route,
    required this.originName,
    required this.destinationName,
    this.onClose,
  });

  final RouteResult route;
  final String originName;
  final String destinationName;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: SoftCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(Icons.directions_rounded, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ItinÃƒÂ©raire en cours',
                        style: TextStyle(
                          fontSize: 12,
                          color: onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      Text(
                        '$originName Ã¢â€ â€™ $destinationName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Fermer',
                    onPressed: onClose,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusPill(
                  label: route.summary,
                  color: AppTheme.primaryColor,
                  icon: Icons.route_rounded,
                ),
                StatusPill(
                  label: route.formattedDuration,
                  color: AppTheme.secondaryDark,
                  icon: Icons.schedule_rounded,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

PolylineLayer createPolylineLayer(List<LatLng> points) {
  return PolylineLayer(
    polylines: [
      Polyline(
        points: points,
        color: AppTheme.primaryColor,
        strokeWidth: 5,
        borderColor: Colors.white,
        borderStrokeWidth: 2,
      ),
    ],
  );
}
