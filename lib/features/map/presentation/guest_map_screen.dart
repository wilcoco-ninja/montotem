import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_ui.dart';
import '../../../core/widgets/client_ui.dart';
import '../../auth/data/location_service.dart';
import '../../auth/data/matching_service.dart';
import '../../tracking/domain/prestataire_model.dart' hide iconePourMetier;
import '../../map/presentation/widgets/provider_detail_sheet.dart';
import 'widgets/route_overlay.dart';
import 'widgets/route_selection_overlay.dart';

/// Types de véhicules : clé = valeur stockée dans providers.vehicle_types.
const _filtres = <String, ({String label, IconData icon})>{
  'moto': (label: 'Moto', icon: Icons.two_wheeler_rounded),
  'voiture': (label: 'Auto', icon: Icons.directions_car_rounded),
  'camion': (label: 'Camion', icon: Icons.local_shipping_rounded),
};

/// Carte des dépanneurs : carte plein écran, filtres flottants, panneau bas
/// avec les dépanneurs triés par distance, fiche détaillée, itinéraire.
/// Utilisable sans compte (mode invité) comme onglet de l'espace client
/// ([vehicleSignal] permet à l'accueil de choisir le véhicule).
class GuestMapScreen extends StatefulWidget {
  const GuestMapScreen({super.key, this.initialVehicle, this.vehicleSignal});

  final String? initialVehicle;
  final ValueNotifier<String?>? vehicleSignal;

  @override
  State<GuestMapScreen> createState() => _GuestMapScreenState();
}

class _GuestMapScreenState extends State<GuestMapScreen> {
  static const double _rayonKm = 15;
  static const Distance _distance = Distance();

  final MapController _mapController = MapController();
  final ScrollController _liste = ScrollController();
  final RoutingService _routingService = RoutingService();
  final LocationService _locationService = LocationService();
  final MatchingService _matchingService = MatchingService();

  LatLng _userPosition = const LatLng(
    AppConstants.initialLatitude,
    AppConstants.initialLongitude,
  );
  bool _positionReelle = false;
  bool _isMapReady = false;
  bool _isLoading = true;
  bool _routeEnCours = false;
  String? _errorMessage;

  String? _filtre; // null = tous les véhicules
  bool _seulementDisponibles = false;
  String? _selectedId;
  double _largeurCarte = 290;
  double _pasListe = 302;
  List<Prestataire> _tous = [];
  List<Prestataire> _dansRayon = [];
  List<Prestataire> _visibles = [];
  List<LatLng> _routeGeometry = const [];

  /// id prestataire -> types de véhicules (RPC publique provider_vehicle_map).
  Map<String, List<String>> _vehicules = const {};

  bool get _connecte => Supabase.instance.client.auth.currentSession != null;

  @override
  void initState() {
    super.initState();
    final init = widget.initialVehicle;
    if (init != null && _filtres.containsKey(init)) _filtre = init;
    widget.vehicleSignal?.addListener(_surSignal);
    _charger();
  }

  @override
  void dispose() {
    widget.vehicleSignal?.removeListener(_surSignal);
    _mapController.dispose();
    _liste.dispose();
    super.dispose();
  }

  void _surSignal() {
    final v = widget.vehicleSignal?.value;
    if (v == null || !_filtres.containsKey(v) || !mounted) return;
    setState(() {
      _filtre = v;
      _selectedId = null;
      _recalculer();
    });
  }

  // ── Données ──────────────────────────────────────────────────────────────

  Future<void> _charger() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await _localiser();

    try {
      final resultats = await Future.wait([
        _matchingService.obtenirTousLesPrestataires(),
        _chargerVehicules(),
      ]);
      if (!mounted) return;
      setState(() {
        _tous = resultats[0] as List<Prestataire>;
        _vehicules = resultats[1] as Map<String, List<String>>;
        _recalculer();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Impossible de charger les prestataires. Vérifiez votre connexion.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Ne lève jamais : sans cette table, les filtres montrent simplement tout.
  Future<Map<String, List<String>>> _chargerVehicules() async {
    try {
      final data =
          await Supabase.instance.client.rpc('provider_vehicle_map') as List;
      return {
        for (final row in data.whereType<Map>())
          '${row['provider_id']}':
              (row['vehicle_types'] as List?)?.map((e) => '$e').toList() ??
              const <String>[],
      };
    } catch (_) {
      return const {};
    }
  }

  /// Ne lève jamais : en cas d'échec, on garde la position de repli.
  Future<void> _localiser() async {
    try {
      final pos = await _locationService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _userPosition = LatLng(pos.latitude, pos.longitude);
        _positionReelle = true;
        _recalculer();
      });
      if (_isMapReady) {
        _mapController.move(_userPosition, AppConstants.defaultZoom);
      }
    } catch (_) {
      // Permission refusée / GPS coupé : position de repli.
    }
  }

  /// Un prestataire sans type renseigné (ancien dossier) reste visible
  /// sous tous les filtres.
  bool _correspond(Prestataire p, String? type) {
    if (_seulementDisponibles && !p.disponible) return false;
    if (type == null) return true;
    final types = _vehicules[p.id];
    if (types == null || types.isEmpty) return true;
    return types.contains(type);
  }

  int _compte(String type) =>
      _dansRayon.where((p) => _correspond(p, type)).length;

  bool get _filtresActifs => _filtre != null || _seulementDisponibles;

  /// Résultats triés par distance croissante.
  void _recalculer() {
    // Filtre par rayon puis tri par distance croissante (sans dépendance
    // à GeoqueryService).
    final avecDistance = <(Prestataire, double)>[
      for (final p in _tous)
        if (_km(p) <= _rayonKm) (p, _km(p)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    _dansRayon = [for (final e in avecDistance) e.$1];
    _visibles = _dansRayon.where((p) => _correspond(p, _filtre)).toList();
  }

  double _km(Prestataire p) => _distance.as(
    LengthUnit.Kilometer,
    _userPosition,
    LatLng(p.latitude, p.longitude),
  );

  void _choisirFiltre(String type) {
    setState(() {
      _filtre = _filtre == type ? null : type;
      _selectedId = null;
      _recalculer();
    });
  }

  void _basculerDisponibles() {
    setState(() {
      _seulementDisponibles = !_seulementDisponibles;
      _selectedId = null;
      _recalculer();
    });
  }

  void _reinitialiserFiltres() {
    setState(() {
      _filtre = null;
      _seulementDisponibles = false;
      _selectedId = null;
      _recalculer();
    });
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  void _selectionner(Prestataire p) {
    setState(() => _selectedId = p.id);
    if (_isMapReady) {
      _mapController.move(
        LatLng(p.latitude, p.longitude),
        math.max(_mapController.camera.zoom, 15),
      );
    }
    final i = _visibles.indexWhere((x) => x.id == p.id);
    if (i >= 0 && _liste.hasClients) {
      final cible = (i * _pasListe)
          .clamp(0.0, _liste.position.maxScrollExtent)
          .toDouble();
      _liste.animateTo(
        cible,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _ajusterCamera() {
    if (!_isMapReady || _routeGeometry.length < 2) return;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: _routeGeometry,
        padding: const EdgeInsets.fromLTRB(40, 110, 40, 300),
      ),
    );
  }

  Future<void> _showRoute(Prestataire p) async {
    if (_routeEnCours) return;
    setState(() => _routeEnCours = true);
    try {
      // getRoutes ne lève pas : repli sur une ligne droite si OSRM échoue.
      final routes = await _routingService.getRoutes(
        origin: _userPosition,
        destination: LatLng(p.latitude, p.longitude),
      );
      if (!mounted || routes.isEmpty) return;

      setState(() => _routeGeometry = routes.first.geometry);

      int selectionne = 0;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: RouteSelectionOverlay(
              routes: routes,
              selectedIndex: selectionne,
              onRouteSelected: (i) {
                setSheetState(() => selectionne = i);
                setState(() => _routeGeometry = routes[i].geometry);
              },
              originName: _positionReelle ? 'Votre position' : 'Cotonou',
              destinationName: p.nomAffiche,
              onClose: () => Navigator.pop(ctx),
            ),
          ),
        ),
      );
      if (!mounted) return;
      _ajusterCamera();
    } finally {
      if (mounted) setState(() => _routeEnCours = false);
    }
  }

  void _afficherPrestataire(Prestataire p) {
    setState(() => _selectedId = p.id);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => ProviderDetailSheet(
        prestataire: p,
        distanceKm: _km(p),
        onItineraire: () => _showRoute(p),
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  List<Marker> _markers() {
    return [
      Marker(
        point: _userPosition,
        width: 48,
        height: 48,
        child: const _UserDot(),
      ),
      ..._visibles.map((p) {
        final sel = p.id == _selectedId;
        final taille = sel ? 56.0 : 44.0;
        return Marker(
          point: LatLng(p.latitude, p.longitude),
          width: taille,
          height: taille,
          child: GestureDetector(
            onTap: () => sel ? _afficherPrestataire(p) : _selectionner(p),
            child: _ProviderMarker(prestataire: p, selected: sel),
          ),
        );
      }),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    final hauteurListe = (176 * scale).clamp(176.0, 270.0).toDouble();
    _largeurCarte = (MediaQuery.sizeOf(context).width * 0.80)
        .clamp(250.0, 320.0)
        .toDouble();
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) {
          final lateral = c.maxWidth >= 900;
          _pasListe = lateral ? hauteurListe + 12 : _largeurCarte + 12;
          if (!lateral) {
            return _carte(context, hauteurListe: hauteurListe, lateral: false);
          }
          return Row(
            children: [
              SizedBox(
                width: math.min(c.maxWidth * 0.36, 420.0),
                child: _panneauLateral(context, hauteurListe),
              ),
              VerticalDivider(
                width: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              Expanded(
                child: _carte(
                  context,
                  hauteurListe: hauteurListe,
                  lateral: true,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Filtres (chips) ──────────────────────────────────────────────────────

  List<Widget> _chips({required bool elevated}) {
    return [
      for (final e in _filtres.entries)
        ClientChip(
          label: _isLoading
              ? e.value.label
              : '${e.value.label} · ${_compte(e.key)}',
          icon: e.value.icon,
          selected: _filtre == e.key,
          elevated: elevated,
          onTap: () => _choisirFiltre(e.key),
        ),
      ClientChip(
        label: 'Disponibles',
        icon: Icons.bolt_rounded,
        selected: _seulementDisponibles,
        elevated: elevated,
        onTap: _basculerDisponibles,
      ),
    ];
  }

  /// Bouton « compte » des invités : connexion, mot de passe, devenir pro.
  Widget _menuInvite() {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: PopupMenuButton<String>(
        tooltip: 'Compte',
        onSelected: (v) => context.go(v),
        offset: const Offset(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: '/login',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.login_rounded),
              title: Text('Se connecter'),
            ),
          ),
          PopupMenuItem(
            value: '/register/client/email',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.how_to_reg_outlined),
              title: Text('Créer un compte'),
            ),
          ),
        ],
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: scheme.surface,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.person_rounded, color: scheme.onSurface),
        ),
      ),
    );
  }

  // ── Carte plein écran ────────────────────────────────────────────────────

  Widget _carte(
    BuildContext context, {
    required double hauteurListe,
    required bool lateral,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final chips = _chips(elevated: true);
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _userPosition,
            initialZoom: AppConstants.defaultZoom,
            onMapReady: () {
              _isMapReady = true;
              if (_positionReelle) {
                _mapController.move(_userPosition, AppConstants.defaultZoom);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'bj.totem.app',
            ),
            if (_routeGeometry.length >= 2) createPolylineLayer(_routeGeometry),
            MarkerLayer(markers: _markers()),
            const RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [
                TextSourceAttribution('© OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
        if (_isLoading || _routeEnCours)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 3),
          ),

        // Filtres flottants (téléphone) / bouton compte des invités.
        if (!lateral)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          clipBehavior: Clip.none,
                          itemCount: chips.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => chips[i],
                        ),
                      ),
                    ),
                    if (!_connecte) ...[
                      const SizedBox(width: 8),
                      _menuInvite(),
                    ],
                  ],
                ),
              ),
            ),
          ),

        // Bas : localisation, itinéraire, panneau des dépanneurs.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: _routeGeometry.isEmpty
                            ? const SizedBox.shrink()
                            : ClientChip(
                                label: 'Effacer l\'itinéraire',
                                icon: Icons.close_rounded,
                                elevated: true,
                                onTap: () =>
                                    setState(() => _routeGeometry = const []),
                              ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ClientRoundButton(
                      icon: Icons.my_location_rounded,
                      tooltip: 'Ma position',
                      onTap: _isLoading ? null : _charger,
                    ),
                  ],
                ),
              ),
              if (!lateral)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(26),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 18,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: _panneauBas(context, hauteurListe),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _panneauLateral(BuildContext context, double hauteurListe) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Dépanneurs',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              if (!_connecte) _menuInvite(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _chips(elevated: false),
          ),
        ),
        Expanded(child: _panneauBas(context, hauteurListe, lateral: true)),
      ],
    );
  }

  String get _titrePanneau {
    final suffixe = _filtre == null ? '' : ' · ${_filtres[_filtre]!.label}';
    final n = _visibles.length;
    return '$n dépanneur${n > 1 ? 's' : ''} à proximité$suffixe';
  }

  Widget _panneauBas(
    BuildContext context,
    double hauteur, {
    bool lateral = false,
  }) {
    if (_errorMessage != null) {
      return _message(
        context,
        texte: _errorMessage!,
        erreur: true,
        action: ('Réessayer', _charger),
      );
    }
    if (_isLoading) {
      return _message(context, texte: 'Recherche des dépanneurs…');
    }
    if (_visibles.isEmpty) {
      final dispo = _seulementDisponibles ? ' disponible' : '';
      final suffixe = _filtre == null ? '' : ' (${_filtres[_filtre]!.label})';
      return _message(
        context,
        texte:
            'Aucun dépanneur$dispo$suffixe à moins de ${_rayonKm.toInt()} km.',
        action: _filtresActifs ? ('Voir tous', _reinitialiserFiltres) : null,
      );
    }

    final entete = Padding(
      padding: EdgeInsets.fromLTRB(lateral ? 16 : 20, lateral ? 8 : 16, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _titrePanneau,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          if (!_positionReelle)
            Text(
              'position approximative',
              style: TextStyle(fontSize: 12.5, color: context.textSecondary),
            ),
        ],
      ),
    );

    if (lateral) {
      return Column(
        children: [
          entete,
          Expanded(
            child: ListView.separated(
              controller: _liste,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: _visibles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final p = _visibles[i];
                return SizedBox(
                  height: hauteur,
                  child: _ProviderCard(
                    p: p,
                    km: _km(p),
                    selected: p.id == _selectedId,
                    onTap: () => _afficherPrestataire(p),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        entete,
        SizedBox(
          height: hauteur,
          child: ListView.separated(
            controller: _liste,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _visibles.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final p = _visibles[i];
              return SizedBox(
                width: _largeurCarte,
                child: _ProviderCard(
                  p: p,
                  km: _km(p),
                  selected: p.id == _selectedId,
                  onTap: () => _afficherPrestataire(p),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _message(
    BuildContext context, {
    required String texte,
    bool erreur = false,
    (String, VoidCallback)? action,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = erreur ? scheme.error : scheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              erreur ? Icons.error_outline_rounded : Icons.place_outlined,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texte,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
          if (action != null)
            TextButton(onPressed: action.$2, child: Text(action.$1)),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Widgets
// ----------------------------------------------------------------------------

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderMarker extends StatelessWidget {
  const _ProviderMarker({required this.prestataire, required this.selected});

  final Prestataire prestataire;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ring = prestataire.disponible
        ? AppColors.success
        : Colors.grey.shade600;
    return Container(
      decoration: BoxDecoration(
        color: selected ? ring : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        iconePourMetier(prestataire.metier),
        size: selected ? 26 : 21,
        color: selected ? Colors.white : ring,
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.p,
    required this.km,
    required this.selected,
    required this.onTap,
  });

  final Prestataire p;
  final double km;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final eta = (km * 1.25 / 25 * 60).ceil();
    final aPhoto = p.photoUrl != null && p.photoUrl!.isNotEmpty;
    final dispo = p.disponible;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected ? scheme.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: ClientCard(
        radius: 20,
        padding: const EdgeInsets.all(14),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  backgroundImage: aPhoto ? NetworkImage(p.photoUrl!) : null,
                  child: aPhoto
                      ? null
                      : Icon(iconePourMetier(p.metier), color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.nomAffiche,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        p.metier,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (p.verifie)
                  Icon(
                    Icons.verified_rounded,
                    color: context.readable(AppColors.success),
                    size: 22,
                  ),
              ],
            ),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Meta(
                  icon: Icons.star_rounded,
                  texte: p.noteMoyenne.toStringAsFixed(1),
                  color: AppColors.gold,
                ),
                _Meta(
                  icon: Icons.near_me_rounded,
                  texte: '${km.toStringAsFixed(1)} km · $eta min',
                  color: context.textSecondary,
                ),
                _Meta(
                  icon: Icons.circle,
                  iconSize: 9,
                  texte: dispo ? 'Disponible' : 'Indisponible',
                  color: dispo
                      ? context.readable(AppColors.success)
                      : context.textTertiary,
                ),
              ],
            ),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 44),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: const Text('Voir la fiche'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({
    required this.icon,
    required this.texte,
    required this.color,
    this.iconSize = 17,
  });

  final IconData icon;
  final String texte;
  final Color color;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: color),
        const SizedBox(width: 5),
        Text(
          texte,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
      ],
    );
  }
}
