import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

const String _userAgent = 'MonTotem/1.0 (bj.totem.app)';
const String _urlTuiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

final Uint8List _transparent = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Cache disque des tuiles de carte (plafonné à ~150 Mo).
class TileDiskCache {
  TileDiskCache._();
  static final TileDiskCache instance = TileDiskCache._();

  Directory? _dir;

  Future<Directory?> _dossier() async {
    if (kIsWeb) return null;
    if (_dir != null) return _dir;
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/tiles_osm');
      if (!await d.exists()) await d.create(recursive: true);
      _dir = d;
      unawaited(_nettoyer(d));
      return d;
    } catch (_) {
      return null;
    }
  }

  Future<void> _nettoyer(Directory d) async {
    try {
      const plafond = 150 * 1024 * 1024;
      const cible = 120 * 1024 * 1024;
      final fichiers = <File>[];
      var total = 0;
      await for (final e in d.list()) {
        if (e is File) {
          fichiers.add(e);
          total += await e.length();
        }
      }
      if (total <= plafond) return;
      fichiers
          .sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      for (final f in fichiers) {
        if (total <= cible) break;
        total -= await f.length();
        await f.delete();
      }
    } catch (_) {}
  }

  Future<File?> _fichier(String cle) async {
    final d = await _dossier();
    return d == null ? null : File('${d.path}/$cle.png');
  }

  Future<Uint8List?> lire(String cle) async {
    try {
      final f = await _fichier(cle);
      if (f == null || !await f.exists()) return null;
      final b = await f.readAsBytes();
      return b.isEmpty ? null : b;
    } catch (_) {
      return null;
    }
  }

  Future<bool> existe(String cle) async {
    try {
      final f = await _fichier(cle);
      return f != null && await f.exists();
    } catch (_) {
      return false;
    }
  }

  Future<void> ecrire(String cle, Uint8List octets) async {
    try {
      final f = await _fichier(cle);
      await f?.writeAsBytes(octets, flush: true);
    } catch (_) {}
  }

  /// Précharge les tuiles autour d'une position (zooms 13 à 16, ~3 km, ~200
  /// tuiles). Volontairement limité : la politique d'OpenStreetMap interdit les
  /// téléchargements massifs. Les tuiles déjà présentes sont ignorées.
  Future<void> prechargerAutour(LatLng centre, {double rayonKm = 3}) async {
    if (kIsWeb) return;
    final client = http.Client();
    try {
      for (final z in const [13, 14, 15, 16]) {
        final n = math.pow(2, z).toDouble();
        final latRad = centre.latitude * math.pi / 180;
        final cx = ((centre.longitude + 180) / 360 * n).floor();
        final cy =
            ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
                    2 *
                    n)
                .floor();
        final tuileKm = 40075 * math.cos(latRad) / n;
        final r = (rayonKm / tuileKm).ceil();
        for (var dx = -r; dx <= r; dx++) {
          for (var dy = -r; dy <= r; dy++) {
            final x = cx + dx;
            final y = cy + dy;
            final cle = '${z}_${x}_$y';
            if (await existe(cle)) continue;
            final url = _urlTuiles
                .replaceFirst('{z}', '$z')
                .replaceFirst('{x}', '$x')
                .replaceFirst('{y}', '$y');
            try {
              final res = await client.get(Uri.parse(url), headers: {
                'User-Agent': _userAgent
              }).timeout(const Duration(seconds: 10));
              if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
                await ecrire(cle, res.bodyBytes);
              }
            } catch (_) {
              return; // Plus de réseau : on s'arrête sans insister.
            }
            await Future<void>.delayed(const Duration(milliseconds: 80));
          }
        }
      }
    } finally {
      client.close();
    }
  }
}

/// Fournisseur de tuiles : lit le disque d'abord, télécharge sinon, et
/// enregistre. Sans réseau, les tuiles déjà vues s'affichent toujours.
class CachedTileProvider extends TileProvider {
  CachedTileProvider() : super(headers: const {'User-Agent': _userAgent});

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _CachedTileImage(
      url: getTileUrl(coordinates, options),
      cle: '${coordinates.z}_${coordinates.x}_${coordinates.y}',
      headers: headers,
    );
  }
}

@immutable
class _CachedTileImage extends ImageProvider<_CachedTileImage> {
  const _CachedTileImage({
    required this.url,
    required this.cle,
    required this.headers,
  });

  final String url;
  final String cle;
  final Map<String, String> headers;

  @override
  Future<_CachedTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_CachedTileImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _charger(decode),
      scale: 1,
      debugLabel: key.cle,
    );
  }

  Future<ui.Codec> _charger(ImageDecoderCallback decode) async {
    Uint8List? octets = await TileDiskCache.instance.lire(cle);
    if (octets == null) {
      try {
        final res = await http
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 12));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          octets = res.bodyBytes;
          unawaited(TileDiskCache.instance.ecrire(cle, octets));
        }
      } catch (_) {}
    }
    final buffer =
        await ui.ImmutableBuffer.fromUint8List(octets ?? _transparent);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is _CachedTileImage && other.cle == cle && other.url == url;

  @override
  int get hashCode => Object.hash(cle, url);
}
