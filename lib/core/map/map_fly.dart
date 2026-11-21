import 'package:flutter/animation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Déplacement animé de la caméra (vol en douceur vers une position).
class MapFly {
  MapFly._();

  static AnimationController? _active;

  /// À appeler dans dispose() de l'écran qui a lancé le vol.
  static void cancel() {
    _active?.dispose();
    _active = null;
  }

  static void to(
    TickerProvider vsync,
    MapController controller,
    LatLng destination,
    double zoom, {
    Duration duration = const Duration(milliseconds: 750),
  }) {
    final MapCamera cam;
    try {
      cam = controller.camera;
    } catch (_) {
      // Carte pas encore prête : déplacement direct impossible, on ignore.
      return;
    }

    _active?.dispose();
    final ctrl = AnimationController(vsync: vsync, duration: duration);
    _active = ctrl;

    final lat =
        Tween<double>(begin: cam.center.latitude, end: destination.latitude);
    final lng =
        Tween<double>(begin: cam.center.longitude, end: destination.longitude);
    final z = Tween<double>(begin: cam.zoom, end: zoom);
    final curve = CurvedAnimation(parent: ctrl, curve: Curves.easeInOutCubic);

    ctrl.addListener(() {
      controller.move(
        LatLng(lat.evaluate(curve), lng.evaluate(curve)),
        z.evaluate(curve),
      );
    });
    ctrl.addStatusListener((s) {
      if (s == AnimationStatus.completed || s == AnimationStatus.dismissed) {
        if (identical(_active, ctrl)) _active = null;
        ctrl.dispose();
      }
    });
    ctrl.forward();
  }
}
