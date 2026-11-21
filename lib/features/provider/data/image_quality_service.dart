import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Résultat du contrôle de qualité d'une photo.
class PhotoCheck {
  const PhotoCheck({
    required this.ok,
    required this.problemes,
    this.metrics = const <String, dynamic>{},
    this.visageControle = true,
  });

  final bool ok;
  final List<String> problemes;
  final Map<String, dynamic> metrics;

  /// false quand la détection de visage n'a pas pu tourner (web, erreur ML Kit).
  final bool visageControle;
}

class VerifiedPhoto {
  const VerifiedPhoto({required this.bytes, required this.check});
  final Uint8List bytes;
  final PhotoCheck check;
}

/// Calculs d'image lourds, exécutés hors du thread d'interface.
Map<String, double> _mesures(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return const {'ok': 0};
  final oriented = img.bakeOrientation(decoded);
  final w = oriented.width;
  final h = oriented.height;
  final small = w > 480 ? img.copyResize(oriented, width: 480) : oriented;
  final sw = small.width;
  final sh = small.height;

  final lum = Float64List(sw * sh);
  var sum = 0.0;
  var glare = 0;
  for (var y = 0; y < sh; y++) {
    for (var x = 0; x < sw; x++) {
      final l = small.getPixel(x, y).luminance.toDouble();
      lum[y * sw + x] = l;
      sum += l;
      if (l >= 252) glare++;
    }
  }
  final total = sw * sh;

  // Variance du laplacien : plus elle est basse, plus l'image est floue.
  var lsum = 0.0;
  var lsq = 0.0;
  var n = 0;
  for (var y = 1; y < sh - 1; y++) {
    for (var x = 1; x < sw - 1; x++) {
      final c = y * sw + x;
      final v =
          4 * lum[c] - lum[c - 1] - lum[c + 1] - lum[c - sw] - lum[c + sw];
      lsum += v;
      lsq += v * v;
      n++;
    }
  }
  final mean = n == 0 ? 0.0 : lsum / n;
  final variance = n == 0 ? 0.0 : lsq / n - mean * mean;

  return {
    'ok': 1,
    'width': w.toDouble(),
    'height': h.toDouble(),
    'brightness': sum / total,
    'sharpness': variance,
    'glare': glare / total,
  };
}

class ImageQualityService {
  // Seuils à calibrer sur des photos réelles.
  static const double _netteteSelfie = 45;
  static const double _netteteDocument = 90;
  static const double _netteteLieu = 35;
  static const double _reflet = 0.12;

  Future<List<Face>> _visages(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/idcheck_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes, flush: true);
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.15,
      ),
    );
    try {
      return await detector.processImage(InputImage.fromFilePath(file.path));
    } finally {
      await detector.close();
      if (await file.exists()) await file.delete();
    }
  }

  List<String> _problemesBase(
    Map<String, double> m, {
    required double minCote,
    required double nettete,
    required double minLum,
    required double maxLum,
  }) {
    final p = <String>[];
    if (math.min(m['width']!, m['height']!) < minCote) {
      p.add('Photo trop petite. Reprenez-la avec l\'appareil photo.');
    }
    if (m['sharpness']! < nettete) {
      p.add('Photo floue. Tenez le téléphone bien droit et immobile, '
          'puis reprenez la photo.');
    }
    if (m['brightness']! < minLum) {
      p.add('Photo trop sombre. Placez-vous face à la lumière du jour.');
    } else if (m['brightness']! > maxLum) {
      p.add('Photo trop claire. Évitez le soleil direct sur l\'appareil.');
    }
    return p;
  }

  Map<String, dynamic> _metrics(Map<String, double> m) => {
        'width': m['width']!.round(),
        'height': m['height']!.round(),
        'brightness': m['brightness']!.round(),
        'sharpness': m['sharpness']!.round(),
      };

  /// Photo du visage : un seul visage, entier, de face, yeux ouverts.
  Future<PhotoCheck> analyserSelfie(Uint8List bytes) async {
    final m = await compute(_mesures, bytes);
    if (m['ok'] != 1) {
      return const PhotoCheck(
          ok: false, problemes: ['Photo illisible. Reprenez-la.']);
    }
    final w = m['width']!;
    final h = m['height']!;
    final problemes = _problemesBase(m,
        minCote: 600, nettete: _netteteSelfie, minLum: 70, maxLum: 210);
    final metrics = _metrics(m);
    var controle = false;

    if (!kIsWeb) {
      try {
        final faces = await _visages(bytes);
        controle = true;
        metrics['faces'] = faces.length;
        if (faces.isEmpty) {
          problemes.add('Aucun visage détecté. Votre visage doit être entier '
              'et face à l\'appareil.');
        } else if (faces.length > 1) {
          problemes.add('Une seule personne doit apparaître sur la photo.');
        } else {
          final f = faces.first;
          final box = f.boundingBox;
          final ratio = box.width * box.height / (w * h);
          metrics['face_ratio'] = double.parse(ratio.toStringAsFixed(3));
          if (ratio < 0.10) {
            problemes
                .add('Rapprochez-vous : votre visage doit remplir le cadre.');
          }
          final coupe = box.left < w * 0.01 ||
              box.top < h * 0.01 ||
              box.right > w * 0.99 ||
              box.bottom > h * 0.99;
          if (coupe) {
            problemes
                .add('Votre visage est coupé. Reculez un peu et centrez-vous.');
          }
          final yaw = f.headEulerAngleY ?? 0;
          final roll = f.headEulerAngleZ ?? 0;
          if (yaw.abs() > 20 || roll.abs() > 20) {
            problemes
                .add('Regardez droit vers l\'appareil, sans pencher la tête.');
          }
          final yeux = math.min(
            f.leftEyeOpenProbability ?? 1,
            f.rightEyeOpenProbability ?? 1,
          );
          if (yeux < 0.3) problemes.add('Ouvrez bien les yeux.');
        }
      } catch (_) {
        controle = false;
      }
    }

    metrics['face_checked'] = controle;
    return PhotoCheck(
      ok: problemes.isEmpty,
      problemes: problemes,
      metrics: metrics,
      visageControle: controle,
    );
  }

  /// Pièce d'identité : lisible, nette, sans reflet. Le visage sur le recto
  /// est mesuré à titre indicatif pour l'admin (non bloquant).
  Future<PhotoCheck> analyserDocument(
    Uint8List bytes, {
    required bool recto,
  }) async {
    final m = await compute(_mesures, bytes);
    if (m['ok'] != 1) {
      return const PhotoCheck(
          ok: false, problemes: ['Photo illisible. Reprenez-la.']);
    }
    final problemes = _problemesBase(m,
        minCote: 720, nettete: _netteteDocument, minLum: 70, maxLum: 220);
    if (m['glare']! > _reflet) {
      problemes.add('Reflet sur le document. Inclinez légèrement le document '
          'ou changez d\'endroit.');
    }
    final metrics = _metrics(m);
    metrics['glare'] = double.parse(m['glare']!.toStringAsFixed(3));

    if (recto && !kIsWeb) {
      try {
        metrics['faces'] = (await _visages(bytes)).length;
      } catch (_) {}
    }
    return PhotoCheck(
        ok: problemes.isEmpty, problemes: problemes, metrics: metrics);
  }

  /// Photo du garage : nette et correctement éclairée.
  Future<PhotoCheck> analyserLieu(Uint8List bytes) async {
    final m = await compute(_mesures, bytes);
    if (m['ok'] != 1) {
      return const PhotoCheck(
          ok: false, problemes: ['Photo illisible. Reprenez-la.']);
    }
    final problemes = _problemesBase(m,
        minCote: 600, nettete: _netteteLieu, minLum: 50, maxLum: 225);
    return PhotoCheck(
        ok: problemes.isEmpty, problemes: problemes, metrics: _metrics(m));
  }
}
