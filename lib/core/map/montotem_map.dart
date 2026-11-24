import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/features/tracking/domain/prestataire_model.dart';
import 'package:montotem/core/map/cluster_layer.dart';
import 'package:montotem/core/map/heading_service.dart';
import 'package:montotem/core/map/live_weather_chip.dart';
import 'package:montotem/core/map/map_config.dart';
import 'package:montotem/core/map/map_controls.dart';

/// Carte unique de l'application : même moteur pour l'accueil et le mode
/// visiteur. Monde entier, zoom/rotation libres, boussole réelle, météo
/// réelle, marqueurs regroupés, point bleu avec direction.
class MontotemMap extends StatefulWidget {
  const MontotemMap({
    super.key,
    required this.controller,
    required this.prestataires,
    required this.onProviderTap,
    required this.onLocate,
    this.user,
    this.userAccuracyM,
    this.locating = false,
    this.route = const [],
    this.onViewportIdle,
    this.initialCenter,
    this.initialZoom,
    this.controlsPadding = const EdgeInsets.all(12),
    this.showWeather = true,
    this.weatherAlignment = Alignment.topLeft,
    this.weatherPadding = const EdgeInsets.all(12),
  });

  final MapController controller;

  /// Nouvelle liste = nouveaux marqueurs (comparaison par identité).
  final List<Prestataire> prestataires;
  final void Function(Prestataire) onProviderTap;
  final VoidCallback onLocate;

  /// Position de l'utilisateur (null tant qu'inconnue : vue du monde).
  final LatLng? user;
  final double? userAccuracyM;
  final bool locating;
  final List<LatLng> route;

  /// Appelée ~0,4 s après la fin de chaque déplacement/zoom : c'est ici qu'on
  /// charge les prestataires de la zone visible.
  final void Function(LatLngBounds visible, double zoom, LatLng center)?
  onViewportIdle;

  final LatLng? initialCenter;
  final double? initialZoom;
  final EdgeInsets controlsPadding;
  final bool showWeather;
  final Alignment weatherAlignment;
  final EdgeInsets weatherPadding;

  @override
  State<MontotemMap> createState() => _MontotemMapState();
}

class _MontotemMapState extends State<MontotemMap> {
  StreamSubscription<MapEvent>? _events;
  Timer? _idle;
  LatLng? _viewCenter;
  double _zoom = MapConfig.worldZoom;

  @override
  void initState() {
    super.initState();
    MapConfig.warmUp();
    _zoom =
        widget.initialZoom ??
        (widget.user != null ? MapConfig.cityZoom : MapConfig.worldZoom);
  }

  @override
  void dispose() {
    _idle?.cancel();
    _events?.cancel();
    super.dispose();
  }

  void _onReady() {
    _events = widget.controller.mapEventStream.listen((e) {
      _idle?.cancel();
      _idle = Timer(
        const Duration(milliseconds: 400),
        () => _emitIdle(e.camera),
      );
    });
    // Premier chargement sans attendre un geste.
    _emitIdle(widget.controller.camera);
  }

  void _emitIdle(MapCamera cam) {
    if (!mounted) return;
    final moved =
        _viewCenter == null ||
        (_viewCenter!.latitude - cam.center.latitude).abs() > 0.02 ||
        (_viewCenter!.longitude - cam.center.longitude).abs() > 0.02 ||
        (_zoom - cam.zoom).abs() > 0.5;
    if (moved) {
      setState(() {
        _viewCenter = cam.center;
        _zoom = cam.zoom;
      });
    }
    widget.onViewportIdle?.call(cam.visibleBounds, cam.zoom, cam.center);
  }

  // ── Marqueurs ───────────────────────────────────────────────────────────

  Marker _providerMarker(Prestataire p, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = p.disponible ? scheme.primary : scheme.outline;
    return Marker(
      key: ValueKey('p_${p.id}'),
      point: LatLng(p.latitude, p.longitude),
      width: 46,
      height: 46,
      rotate: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onProviderTap(p),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: scheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.navy.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(iconePourMetier(p.metier), size: 20, color: color),
            ),
            if (p.disponible)
              Positioned(
                right: 1,
                top: 1,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: scheme.secondary,
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.surface, width: 1.6),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = widget.user;
    final center = widget.initialCenter ?? user ?? MapConfig.worldCenter;
    final weatherAt = user ?? _viewCenter;
    final weatherOk =
        widget.showWeather &&
        weatherAt != null &&
        (user != null || _zoom >= 6); // inutile à l'échelle du monde

    return Stack(
      children: [
        FlutterMap(
          mapController: widget.controller,
          options: MapConfig.options(
            center: center,
            zoom: _zoom,
            onMapReady: _onReady,
          ),
          children: [
            MapConfig.tileLayer(),
            if (widget.route.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: widget.route,
                    color: scheme.primary,
                    strokeWidth: 5,
                    borderColor: scheme.surface,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            if (user != null &&
                widget.userAccuracyM != null &&
                widget.userAccuracyM! >= 25 &&
                widget.userAccuracyM! <= 2000)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: user,
                    radius: widget.userAccuracyM!,
                    useRadiusInMeter: true,
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderColor: scheme.primary.withValues(alpha: 0.3),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
            ClusterLayer<Prestataire>(
              items: widget.prestataires,
              pointOf: (p) => LatLng(p.latitude, p.longitude),
              markerBuilder: (p) => _providerMarker(p, context),
            ),
            if (user != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: user,
                    width: 76,
                    height: 76,
                    rotate: true,
                    child: const _UserDot(),
                  ),
                ],
              ),
            MapControls(
              onLocate: widget.onLocate,
              locating: widget.locating,
              padding: widget.controlsPadding,
            ),
            const RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [TextSourceAttribution(MapConfig.attribution)],
            ),
          ],
        ),
        if (weatherOk)
          Align(
            alignment: widget.weatherAlignment,
            child: Padding(
              padding: widget.weatherPadding,
              child: LiveWeatherChip(position: weatherAt),
            ),
          ),
      ],
    );
  }
}

/// Point bleu de l'utilisateur + faisceau indiquant la direction réelle du
/// téléphone (boussole). Sans capteur : simple point bleu.
class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stream = HeadingService.instance.stream;
    final rotationDeg = MapCamera.of(context).rotation;

    Widget dot(double? heading) => Stack(
      alignment: Alignment.center,
      children: [
        if (heading != null)
          Transform.rotate(
            angle: (heading + rotationDeg) * math.pi / 180,
            child: CustomPaint(
              size: const Size(76, 76),
              painter: _BeamPainter(),
            ),
          ),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: scheme.primary,
            shape: BoxShape.circle,
            border: Border.all(color: scheme.surface, width: 3),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.45),
                blurRadius: 10,
              ),
            ],
          ),
        ),
      ],
    );

    if (stream == null) return dot(null);
    return StreamBuilder<double>(
      stream: stream,
      initialData: HeadingService.instance.last,
      builder: (_, snap) => dot(snap.data),
    );
  }
}

class _BeamPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF1E88E5).withValues(alpha: 0.55),
          const Color(0xFF1E88E5).withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    // Secteur de 60° centré sur le haut (0° = devant le téléphone).
    canvas.drawArc(rect, -math.pi / 2 - math.pi / 6, math.pi / 3, true, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
