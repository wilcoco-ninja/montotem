import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import 'package:montotem/core/constants/app_constants.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/requests/domain/mission_model.dart';
import 'package:montotem/features/tracking/domain/prestataire_model.dart';
import 'package:montotem/features/admin/data/admin_control_service.dart';
import 'package:montotem/features/admin/data/admin_service.dart';

class AdminTrackingScreen extends StatefulWidget {
  const AdminTrackingScreen({super.key});

  @override
  State<AdminTrackingScreen> createState() => _AdminTrackingScreenState();
}

class _AdminTrackingScreenState extends State<AdminTrackingScreen>
    with WidgetsBindingObserver {
  final AdminService _adminService = AdminService();
  final AdminControlService _control = AdminControlService();
  final MapController _mapController = MapController();

  RealtimeChannel? _canalMissions;
  RealtimeChannel? _canalPrestataires;
  Timer? _antiRebond;

  // Lu au moment du toucher : jamais de version périmée dans les marqueurs.
  Map<String, Prestataire> _prestataires = {};
  Map<String, MissionStatus> _etats = {};
  Map<String, LatLng> _positionsLive = {};
  List<Marker> _markers = const [];

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _charger();
    _canalMissions = _control.ecouter(
      'missions',
      _planifierRecharge,
      nom: 'admin-track-missions',
    );
    _canalPrestataires = _control.ecouter(
      'providers',
      _planifierRecharge,
      nom: 'admin-track-providers',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _antiRebond?.cancel();
    final m = _canalMissions;
    if (m != null) _control.arreter(m);
    final p = _canalPrestataires;
    if (p != null) _control.arreter(p);
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Au retour au premier plan, on se resynchronise (la connexion
    // Realtime a pu être suspendue par le système).
    if (state == AppLifecycleState.resumed) {
      _charger(silencieux: true);
    }
  }

  /// Regroupe les rafales d'évènements (une position toutes les 8 s par
  /// mission active) en un seul rechargement.
  void _planifierRecharge() {
    _antiRebond?.cancel();
    _antiRebond = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) _charger(silencieux: true);
    });
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final res = await Future.wait<Object?>([
        _adminService.obtenirPrestataires(),
        _control.missions(),
      ]);
      if (!mounted) return;

      final prestataires = res[0] as List<Prestataire>;
      final missions = res[1] as List<Map<String, dynamic>>;

      final etats = <String, MissionStatus>{};
      final live = <String, LatLng>{};
      for (final m in missions) {
        final statut = MissionStatus.fromValue(m['status'] as String?);
        if (!statut.actif) continue;
        final id = '${m['provider_id']}';
        etats.putIfAbsent(id, () => statut);
        final lat = (m['provider_lat'] as num?)?.toDouble();
        final lng = (m['provider_lng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          live.putIfAbsent(id, () => LatLng(lat, lng));
        }
      }

      setState(() {
        _prestataires = {for (final p in prestataires) p.id: p};
        _etats = etats;
        _positionsLive = live;
        _markers = _construireMarkers(prestataires, etats, live);
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      if (!silencieux) {
        setState(() {
          _errorMessage = 'Impossible de charger les positions.';
          _isLoading = false;
        });
      }
    }
  }

  List<Marker> _construireMarkers(
    List<Prestataire> prestataires,
    Map<String, MissionStatus> etats,
    Map<String, LatLng> live,
  ) {
    return prestataires.map((p) {
      final point = live[p.id] ?? LatLng(p.latitude, p.longitude);
      return Marker(
        point: point,
        width: 44,
        height: 44,
        key: ValueKey('marker_${p.id}'),
        child: GestureDetector(
          onTap: () {
            final courant = _prestataires[p.id];
            if (courant != null) _afficherDetail(courant);
          },
          child: _StatutMarker(couleur: _couleurStatut(p, etats[p.id])),
        ),
      );
    }).toList();
  }

  Color _couleurStatut(Prestataire p, MissionStatus? etat) {
    if (etat != null) {
      return switch (etat) {
        MissionStatus.accepted => Colors.blue,
        MissionStatus.arrived => Colors.orange,
        MissionStatus.working => Colors.deepOrange,
        _ => p.disponible ? Colors.teal : Colors.grey,
      };
    }
    return p.disponible ? Colors.teal : Colors.grey;
  }

  String _libelleStatut(Prestataire p, MissionStatus? etat) {
    if (etat != null) {
      return switch (etat) {
        MissionStatus.accepted => 'En route vers le client',
        MissionStatus.arrived => 'Sur place chez le client',
        MissionStatus.working => 'Réparation en cours',
        _ => p.disponible ? 'Disponible' : 'Hors ligne',
      };
    }
    return p.disponible ? 'Disponible' : 'Hors ligne';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suivi des prestataires'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
            onPressed: _isLoading ? null : () => _charger(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(
                AppConstants.initialLatitude,
                AppConstants.initialLongitude,
              ),
              initialZoom: AppConstants.defaultZoom,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'bj.totem.app',
              ),
              MarkerLayer(markers: _markers),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          if (_isLoading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 3),
            ),
          Positioned(
            top: 12,
            left: 12,
            child: StatusPillOnMap(
              label:
                  '${_prestataires.length} prestataire(s) · '
                  '${_etats.length} en mission · '
                  '${_positionsLive.length} suivi(s) en direct',
            ),
          ),
          if (_errorMessage != null)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black45,
                child: Center(
                  child: ContentWidth(
                    maxWidth: 420,
                    child: SoftCard(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: ErrorState(
                        message: _errorMessage!,
                        onRetry: () => _charger(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const Positioned(left: 12, bottom: 12, child: _Legende()),
        ],
      ),
    );
  }

  void _afficherDetail(Prestataire p) {
    final etat = _etats[p.id];
    final couleur = _couleurStatut(p, etat);
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.nomAffiche,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  StatusPill(
                    label: p.verifie ? 'Vérifié' : 'Non vérifié',
                    color: p.verifie ? scheme.secondary : scheme.tertiary,
                    icon: p.verifie
                        ? Icons.verified_rounded
                        : Icons.error_outline_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                p.metier,
                style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 14),
              StatusPill(label: _libelleStatut(p, etat), color: couleur),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(
                    label: '${p.noteMoyenne.toStringAsFixed(1)} / 5',
                    color: Colors.amber.shade800,
                    icon: Icons.star_rounded,
                  ),
                  StatusPill(
                    label: '${p.clientsSatisfaits}',
                    color: scheme.secondary,
                    icon: Icons.thumb_up_outlined,
                  ),
                  StatusPill(
                    label: '${p.clientsInsatisfaits}',
                    color: scheme.error,
                    icon: Icons.thumb_down_outlined,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatutMarker extends StatelessWidget {
  const _StatutMarker({required this.couleur});
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.location_on,
      size: 40,
      color: couleur,
      shadows: const [Shadow(blurRadius: 4, color: Colors.black38)],
    );
  }
}

/// Pastille flottante sur la carte.
class StatusPillOnMap extends StatelessWidget {
  const StatusPillOnMap({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Legende extends StatelessWidget {
  const _Legende();

  @override
  Widget build(BuildContext context) {
    const entries = <String, Color>{
      'Disponible': Colors.teal,
      'En route': Colors.blue,
      'Sur place': Colors.orange,
      'En travail': Colors.deepOrange,
      'Hors ligne': Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: entries.entries
            .map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 10, color: e.value),
                    const SizedBox(width: 8),
                    Text(e.key, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
