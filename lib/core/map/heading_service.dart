import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';

/// Cap réel du téléphone (capteur magnétique), lissé.
///
/// - Un seul abonnement matériel partagé par tous les widgets.
/// - Le capteur n'est écouté que tant qu'un widget en a besoin (batterie).
/// - [stream] vaut null si l'appareil n'a pas de boussole (web, émulateur) :
///   les widgets masquent alors simplement la boussole.
class HeadingService {
  HeadingService._();
  static final HeadingService instance = HeadingService._();

  static const double _smoothing = 0.25; // 0..1 : plus bas = plus stable
  static const double _minChange = 1.5; // degrés avant d'émettre

  late final StreamController<double> _ctrl =
      StreamController<double>.broadcast(
    onListen: _start,
    onCancel: _stop,
  );
  StreamSubscription<CompassEvent>? _sub;
  double? _smooth;
  double? _emitted;

  /// Dernier cap connu (0–360, 0 = nord), ou null.
  double? last;

  Stream<double>? get stream => isSupported ? _ctrl.stream : null;

  bool get isSupported {
    if (kIsWeb) return false;
    try {
      return FlutterCompass.events != null;
    } catch (_) {
      return false;
    }
  }

  void _start() {
    if (!isSupported) return;
    _sub = FlutterCompass.events!.listen(
      (e) {
        final raw = e.heading;
        if (raw == null) return;
        final target = ((raw % 360) + 360) % 360;
        final s = _smooth;
        if (s == null) {
          _smooth = target;
        } else {
          _smooth = (s + _shortest(s, target) * _smoothing + 360) % 360;
        }
        final out = _smooth!;
        final prev = _emitted;
        if (prev == null || _shortest(prev, out).abs() >= _minChange) {
          _emitted = out;
          last = out;
          if (!_ctrl.isClosed) _ctrl.add(out);
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    _smooth = null;
    _emitted = null;
  }

  /// Écart signé le plus court de [from] vers [to], dans [-180, 180].
  static double _shortest(double from, double to) {
    var d = to - from;
    while (d > 180) {
      d -= 360;
    }
    while (d < -180) {
      d += 360;
    }
    return d;
  }

  /// « N », « NE »… pour un cap en degrés.
  static String cardinal(double deg) {
    const pts = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
    return pts[((deg % 360) / 45).round() % 8];
  }
}
