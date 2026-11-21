
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/map/heading_service.dart';
import 'package:montotem/core/map/map_config.dart';

/// Colonne de commandes : zoom +/Ã¢Ë†â€™, boussole rÃƒÂ©elle, Ã‚Â« ma position Ã‚Â».
///
/// Ãƒâ‚¬ placer DANS les `children` du FlutterMap (elle lit la camÃƒÂ©ra de la carte).
/// Rotation : ÃƒÂ  deux doigts sur la carte, dans tous les sens.
class MapControls extends StatefulWidget {
  const MapControls({
    super.key,
    required this.onLocate,
    this.locating = false,
    this.padding = const EdgeInsets.all(12),
    this.alignment = Alignment.bottomRight,
  });

  final VoidCallback onLocate;
  final bool locating;
  final EdgeInsets padding;
  final Alignment alignment;

  @override
  State<MapControls> createState() => _MapControlsState();
}

class _MapControlsState extends State<MapControls>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  StreamSubscription<double>? _headingSub;
  bool _follow = false;
  double? _heading;
  DateTime _lastRotate = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    // Le cap s'affiche en permanence sous la boussole (si le capteur existe).
    _heading = HeadingService.instance.last;
    _headingSub = HeadingService.instance.stream?.listen(_onHeading);
  }

  @override
  void dispose() {
    _headingSub?.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _onHeading(double h) {
    if (!mounted) return;
    setState(() => _heading = h);
    if (!_follow) return;
    // Mode Ã‚Â« suivre ma direction Ã‚Â» : l'avant du tÃƒÂ©lÃƒÂ©phone pointe vers le haut.
    final now = DateTime.now();
    if (now.difference(_lastRotate).inMilliseconds < 80) return;
    _lastRotate = now;
    MapController.of(context).rotate(-h);
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Animations Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  void _animate(void Function(double t) step) {
    void listener() => step(Curves.easeOutCubic.transform(_anim.value));
    _anim
      ..stop()
      ..reset()
      ..addListener(listener);
    _anim.forward().whenCompleteOrCancel(() => _anim.removeListener(listener));
  }

  void _zoomBy(double delta) {
    final controller = MapController.of(context);
    final cam = controller.camera;
    final from = cam.zoom;
    final to =
        (from + delta).clamp(MapConfig.minZoom, MapConfig.maxZoom).toDouble();
    if (to == from) return;
    final center = cam.center;
    _animate((t) => controller.move(center, from + (to - from) * t));
  }

  void _resetNorth() {
    final controller = MapController.of(context);
    var from = controller.camera.rotation % 360;
    if (from > 180) from -= 360;
    if (from == 0) return;
    _animate((t) => controller.rotate(from * (1 - t)));
  }

  void _onCompassTap(double rotation) {
    final r = rotation % 360;
    final tilted = r > 1 && r < 359;
    if (_follow || tilted) {
      setState(() => _follow = false);
      _resetNorth();
      return;
    }
    if (HeadingService.instance.stream == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Boussole indisponible sur cet appareil.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() => _follow = true);
    final h = _heading;
    if (h != null) MapController.of(context).rotate(-h);
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final rotation = camera.rotation;
    final atMin = camera.zoom <= MapConfig.minZoom + 0.01;
    final atMax = camera.zoom >= MapConfig.maxZoom - 0.01;

    return Align(
      alignment: widget.alignment,
      child: Padding(
        padding: widget.padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoundButton(
              tooltip: 'Zoom avant',
              onTap: atMax ? null : () => _zoomBy(1),
              child: const Icon(Icons.add_rounded),
            ),
            const SizedBox(height: 8),
            _RoundButton(
              tooltip: 'Zoom arriÃƒÂ¨re',
              onTap: atMin ? null : () => _zoomBy(-1),
              child: const Icon(Icons.remove_rounded),
            ),
            const SizedBox(height: 8),
            _RoundButton(
              tooltip: _follow
                  ? 'ArrÃƒÂªter de suivre ma direction'
                  : 'Boussole : touchez pour suivre votre direction '
                      '(ou remettre le nord en haut)',
              highlighted: _follow,
              onTap: () => _onCompassTap(rotation),
              child: Transform.rotate(
                angle: camera.rotationRad,
                child: CustomPaint(
                  size: const Size(26, 26),
                  painter: _NeedlePainter(),
                ),
              ),
            ),
            if (_heading != null) ...[
              const SizedBox(height: 4),
              _HeadingLabel(heading: _heading!),
            ],
            const SizedBox(height: 8),
            _RoundButton(
              tooltip: 'Ma position',
              onTap: widget.locating ? null : widget.onLocate,
              child: widget.locating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : const Icon(Icons.my_location_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.child,
    required this.onTap,
    required this.tooltip,
    this.highlighted = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String tooltip;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: highlighted ? scheme.primary : scheme.surface,
        elevation: 3,
        shadowColor: AppColors.navy.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: IconTheme(
              data: IconThemeData(
                color: highlighted
                    ? scheme.onPrimary
                    : onTap == null
                        ? scheme.onSurface.withValues(alpha: 0.3)
                        : scheme.onSurface,
                size: 24,
              ),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeadingLabel extends StatelessWidget {
  const _HeadingLabel({required this.heading});
  final double heading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.26), blurRadius: 4)
        ],
      ),
      child: Text(
        '${HeadingService.cardinal(heading)} ${heading.round()}Ã‚Â°',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Aiguille de boussole : pointe rouge = nord, queue grise = sud.
class _NeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final h = size.height / 2;
    final w = size.width * 0.2;

    final north = Path()
      ..moveTo(c.dx, c.dy - h)
      ..lineTo(c.dx + w, c.dy)
      ..lineTo(c.dx - w, c.dy)
      ..close();
    final south = Path()
      ..moveTo(c.dx, c.dy + h)
      ..lineTo(c.dx + w, c.dy)
      ..lineTo(c.dx - w, c.dy)
      ..close();

    canvas.drawPath(south, Paint()..color = AppColors.textTertiaryLight);
    canvas.drawPath(north, Paint()..color = AppColors.emergency);
    canvas.drawCircle(c, 2.2, Paint()..color = AppColors.surfaceLight);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
