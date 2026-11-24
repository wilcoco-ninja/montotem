import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Marqueurs regroupÃƒÂ©s (clusters) rapides, pour des milliers de points.
///
/// Par rapport ÃƒÂ  l'ancienne MarkerClusterLayer :
///  - regroupement par grille : O(n) au lieu de O(nÃ‚Â²) ;
///  - calculÃƒÂ© une seule fois par niveau de zoom entier (le panoramique ne
///    recalcule rien) ;
///  - seuls les marqueurs visibles ÃƒÂ  l'ÃƒÂ©cran (+ marge) sont construits ;
///  - toucher un groupe zoome pour montrer exactement ses membres.
///
/// Ãƒâ‚¬ placer dans les `children` du FlutterMap.
class ClusterLayer<T> extends StatefulWidget {
  const ClusterLayer({
    super.key,
    required this.items,
    required this.pointOf,
    required this.markerBuilder,
    this.radiusPx = 58,
    this.noClusterFromZoom = 16,
  });

  /// Passez une NOUVELLE liste quand les donnÃƒÂ©es changent (comparaison par
  /// identitÃƒÂ©) ; gardez la mÃƒÂªme instance sinon.
  final List<T> items;
  final LatLng Function(T item) pointOf;

  /// Marqueur d'un point isolÃƒÂ© (mettez `rotate: true` pour qu'il reste droit).
  final Marker Function(T item) markerBuilder;

  final double radiusPx;
  final int noClusterFromZoom;

  @override
  State<ClusterLayer<T>> createState() => _ClusterLayerState<T>();
}

class _Cluster<T> {
  _Cluster(T first, LatLng p)
    : members = [first],
      _sumLat = p.latitude,
      _sumLng = p.longitude;

  final List<T> members;
  double _sumLat;
  double _sumLng;

  void add(T item, LatLng p) {
    members.add(item);
    _sumLat += p.latitude;
    _sumLng += p.longitude;
  }

  LatLng get center =>
      LatLng(_sumLat / members.length, _sumLng / members.length);
}

class _ClusterLayerState<T> extends State<ClusterLayer<T>> {
  List<T>? _builtFor;
  int _builtZoom = -999;
  List<_Cluster<T>> _clusters = const [];

  /// Projection Web Mercator en pixels au niveau de zoom entier [z].
  (double, double) _project(LatLng p, int z) {
    final scale = 256.0 * (1 << z);
    final x = (p.longitude + 180) / 360 * scale;
    final s = math.sin(p.latitude * math.pi / 180).clamp(-0.9999, 0.9999);
    final y = (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * scale;
    return (x, y);
  }

  void _rebuildIfNeeded(int z) {
    if (identical(_builtFor, widget.items) && _builtZoom == z) return;
    _builtFor = widget.items;
    _builtZoom = z;

    if (z >= widget.noClusterFromZoom) {
      _clusters = [
        for (final it in widget.items) _Cluster<T>(it, widget.pointOf(it)),
      ];
      return;
    }

    final cells = <int, _Cluster<T>>{};
    for (final it in widget.items) {
      final p = widget.pointOf(it);
      final (x, y) = _project(p, z);
      final key = (x ~/ widget.radiusPx) * 4194304 + (y ~/ widget.radiusPx);
      final c = cells[key];
      if (c == null) {
        cells[key] = _Cluster<T>(it, p);
      } else {
        c.add(it, p);
      }
    }
    _clusters = cells.values.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    _rebuildIfNeeded(camera.zoom.floor());

    // Zone visible agrandie de 25 % : pas de marqueur qui Ã‚Â« apparaÃƒÂ®t Ã‚Â» au bord.
    final b = camera.visibleBounds;
    final padLat = (b.north - b.south) * 0.25;
    final padLng = (b.east - b.west) * 0.25;
    final south = b.south - padLat, north = b.north + padLat;
    final west = b.west - padLng, east = b.east + padLng;

    final markers = <Marker>[];
    for (final c in _clusters) {
      final center = c.center;
      if (center.latitude < south ||
          center.latitude > north ||
          center.longitude < west ||
          center.longitude > east) {
        continue;
      }
      if (c.members.length == 1) {
        markers.add(widget.markerBuilder(c.members.first));
      } else {
        markers.add(_clusterMarker(c));
      }
    }
    return MarkerLayer(markers: markers);
  }

  Marker _clusterMarker(_Cluster<T> c) {
    final count = c.members.length;
    final size = count < 10
        ? 44.0
        : count < 100
        ? 52.0
        : 60.0;
    final label = count >= 1000
        ? '${(count / 1000).toStringAsFixed(1)}k'
        : '$count';

    return Marker(
      key: ValueKey('cl_${c.center.latitude}_${c.center.longitude}_$count'),
      point: c.center,
      width: size,
      height: size,
      rotate: true,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return GestureDetector(
            onTap: () {
              final pts = [for (final m in c.members) widget.pointOf(m)];
              MapController.of(context).fitCamera(
                CameraFit.coordinates(
                  coordinates: pts,
                  padding: const EdgeInsets.all(72),
                  maxZoom: 18,
                ),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  color: scheme.surface,
                  fontSize: count < 10 ? 16 : 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
