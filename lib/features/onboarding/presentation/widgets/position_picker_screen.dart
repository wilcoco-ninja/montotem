import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/widgets/app_button.dart';

class PositionPickerScreen extends StatefulWidget {
  const PositionPickerScreen({super.key, this.positionInitiale});

  final LatLng? positionInitiale;

  @override
  State<PositionPickerScreen> createState() => _PositionPickerScreenState();
}

class _PositionPickerScreenState extends State<PositionPickerScreen> {
  late LatLng _pointSelectionne;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    // Position par défaut (Cotonou, Bénin) si aucune position initiale
    _pointSelectionne = widget.positionInitiale ?? const LatLng(6.3654, 2.4183);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Placer votre garage'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_rounded, size: 28),
            onPressed: () => Navigator.pop(context, _pointSelectionne),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _pointSelectionne,
              initialZoom: 15.0,
              onTap: (_, point) {
                setState(() => _pointSelectionne = point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.montotem.app',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _pointSelectionne,
                    width: 50,
                    height: 50,
                    child: const Icon(
                      Icons.location_pin,
                      color: AppTheme.primaryColor,
                      size: 45,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: AppButton(
              label: 'Valider cette position',
              icon: Icons.check_circle_rounded,
              onPressed: () => Navigator.pop(context, _pointSelectionne),
            ),
          ),
        ],
      ),
    );
  }
}
