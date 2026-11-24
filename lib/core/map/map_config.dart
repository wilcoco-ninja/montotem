import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Réglages communs à toutes les cartes de l'application (monde entier).
class MapConfig {
  MapConfig._();

  /// Serveur de tuiles. Par défaut OpenStreetMap (dev / faible trafic).
  /// En production avec beaucoup d'utilisateurs, utilisez un fournisseur
  /// prévu pour cela (MapTiler, Stadia, Thunderforest…) sans changer le code :
  ///   flutter run --dart-define=TILE_URL=https://.../{z}/{x}/{y}.png
  static const String tileUrl = String.fromEnvironment(
    'TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  static const String userAgent = 'bj.totem.app';
  static const String attribution = '© OpenStreetMap contributors';

  /// Pas de limite géographique : l'utilisateur peut être n'importe où.
  static const double minZoom = 2;
  static const double maxZoom = 19;

  /// Vue d'ensemble affichée tant qu'aucune position n'est connue.
  static const LatLng worldCenter = LatLng(20, 0);
  static const double worldZoom = 2.6;

  /// Zoom de départ quand la position de l'utilisateur est connue.
  static const double cityZoom = 14;

  static bool _warmed = false;

  /// Agrandit le cache d'images de Flutter (les tuiles y sont stockées) :
  /// les zones déjà vues se réaffichent instantanément au retour arrière.
  static void warmUp() {
    if (_warmed) return;
    _warmed = true;
    final cache = PaintingBinding.instance.imageCache;
    if (cache.maximumSizeBytes < 200 << 20) {
      cache.maximumSizeBytes = 200 << 20; // 200 Mo
    }
    if (cache.maximumSize < 2000) cache.maximumSize = 2000;
  }

  /// Toutes les interactions : zoom (pincer, double tap, molette), glisser,
  /// ET rotation à deux doigts dans tous les sens.
  static InteractionOptions get interaction => const InteractionOptions(
    flags: InteractiveFlag.all,
    // Seuil bas : la rotation se déclenche vite, sans geste exagéré.
    rotationThreshold: 8,
  );

  static MapOptions options({
    required LatLng center,
    required double zoom,
    VoidCallback? onMapReady,
    void Function(TapPosition, LatLng)? onTap,
  }) {
    return MapOptions(
      initialCenter: center,
      initialZoom: zoom,
      minZoom: minZoom,
      maxZoom: maxZoom,
      interactionOptions: interaction,
      backgroundColor: const Color(0xFFE8EEF3),
      onMapReady: onMapReady,
      onTap: onTap,
    );
  }

  /// Couche de tuiles réglée pour la fluidité :
  /// - tuiles voisines préchargées dans le sens du déplacement (panBuffer),
  /// - anciennes tuiles gardées en mémoire (keepBuffer) : retour arrière sans
  ///   écran blanc,
  /// - apparition en fondu (pas de « clignotement »).
  static TileLayer tileLayer() => TileLayer(
    urlTemplate: tileUrl,
    userAgentPackageName: userAgent,
    maxNativeZoom: 19,
    maxZoom: 22,
    keepBuffer: 4,
    panBuffer: 2,
    tileDisplay: const TileDisplay.fadeIn(
      duration: Duration(milliseconds: 160),
    ),
    evictErrorTileStrategy: EvictErrorTileStrategy.notVisibleRespectMargin,
  );
}
