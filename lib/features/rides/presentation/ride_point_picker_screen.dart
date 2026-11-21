
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:montotem/core/constants/app_constants.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/features/auth/data/location_service.dart';

/// Choix d'un point sur la carte (dÃƒÂ©part ou destination d'une course).
/// Retourne la position choisie (LatLng).
class RidePointPickerScreen extends StatefulWidget {
  const RidePointPickerScreen({
    super.key,
    required this.titre,
    required this.consigne,
    this.positionInitiale,
    this.couleur = AppTheme.errorColor,
  });

  final String titre;
  final String consigne;
  final LatLng? positionInitiale;
  final Color couleur;

  @override
  State<RidePointPickerScreen> createState() => _RidePointPickerScreenState();
}

class _RidePointPickerScreenState extends State<RidePointPickerScreen> {
  final LocationService _location = LocationService();
  final MapController _map = MapController();

  late LatLng _position;
  bool _mapPrete = false;
  bool _recherche = false;

  @override
  void initState() {
    super.initState();
    _position = widget.positionInitiale ??
        const LatLng(
            AppConstants.initialLatitude, AppConstants.initialLongitude);
    if (widget.positionInitiale == null) _centrerSurMoi(silencieux: true);
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _centrerSurMoi({bool silencieux = false}) async {
    setState(() => _recherche = true);
    try {
      final p = await _location.getCurrentLocation();
      if (!mounted) return;
      final pt = LatLng(p.latitude, p.longitude);
      setState(() => _position = pt);
      if (_mapPrete) _map.move(pt, AppConstants.defaultZoom);
    } catch (_) {
      if (mounted && !silencieux) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Impossible de rÃƒÂ©cupÃƒÂ©rer votre position GPS.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _recherche = false);
    }
  }

  void _zoom(double delta) {
    final z = (_map.camera.zoom + delta).clamp(5.0, 18.0).toDouble();
    _map.move(_map.camera.center, z);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(widget.titre)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _position,
              initialZoom: AppConstants.defaultZoom,
              minZoom: 5,
              maxZoom: 18,
              onMapReady: () {
                _mapPrete = true;
                _map.move(_position, AppConstants.defaultZoom);
              },
              onTap: (_, point) => setState(() => _position = point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'bj.totem.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _position,
                    width: 56,
                    height: 56,
                    alignment: Alignment.topCenter,
                    child: Icon(Icons.location_on,
                        size: 52, color: widget.couleur),
                  ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('Ã‚Â© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              color: scheme.surface,
              elevation: 4,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.touch_app_outlined,
                        color: scheme.primary, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.consigne,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 18,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'rpp_plus',
                  tooltip: 'Zoom avant',
                  onPressed: () => _zoom(1),
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'rpp_moins',
                  tooltip: 'Zoom arriÃƒÂ¨re',
                  onPressed: () => _zoom(-1),
                  child: const Icon(Icons.remove),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'rpp_moi',
                  tooltip: 'Ma position',
                  onPressed: _recherche ? null : () => _centrerSurMoi(),
                  child: _recherche
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AppButton(
            label: 'Confirmer cette position',
            icon: Icons.check_circle_outline,
            onPressed: () => Navigator.pop(context, _position),
          ),
        ),
      ),
    );
  }
}
