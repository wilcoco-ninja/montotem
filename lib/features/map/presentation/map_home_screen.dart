// lib/features/map/presentation/map_home_screen.dart
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/routing_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_ui.dart';
import '../../auth/data/location_service.dart';
import '../../auth/data/matching_service.dart';
import '../../tracking/domain/prestataire_model.dart' hide iconePourMetier;
import 'widgets/auth_gate_sheet.dart';
import 'widgets/provider_detail_sheet.dart';
import 'widgets/route_overlay.dart';

// ----------------------------------------------------------------------------
// CatÃƒÂ©gories
// ----------------------------------------------------------------------------

enum _Cat { tous, zemidjan, kloboto, depannage }

enum _Genre { zemidjan, kloboto, depanneur }

extension on _Genre {
  String get label => switch (this) {
    _Genre.zemidjan => 'ZÃƒÂ©midjan',
    _Genre.kloboto => 'Kloboto',
    _Genre.depanneur => 'DÃƒÂ©panneur',
  };

  IconData get icon => switch (this) {
    _Genre.zemidjan => Icons.two_wheeler_rounded,
    _Genre.kloboto => Icons.electric_rickshaw_rounded,
    _Genre.depanneur => Icons.build_circle_rounded,
  };

  Color get color => switch (this) {
    _Genre.zemidjan => const Color(0xFFF59E0B),
    _Genre.kloboto => const Color(0xFF16A34A),
    _Genre.depanneur => const Color(0xFFDC2626),
  };

  /// Code transmis ÃƒÂ  la route /ride/new (null = pas un conducteur).
  String? get codeCourse => switch (this) {
    _Genre.zemidjan => 'zemidjan',
    _Genre.kloboto => 'tricycle_fret',
    _Genre.depanneur => null,
  };
}

/// VÃƒÂ©hicule en panne : clÃƒÂ© = valeur stockÃƒÂ©e dans providers.vehicle_types.
const _vehiculesPanne = <String, ({String label, IconData icon})>{
  'moto': (label: 'Moto', icon: Icons.two_wheeler_rounded),
  'voiture': (label: 'Voiture', icon: Icons.directions_car_rounded),
  'camion': (label: 'Camion', icon: Icons.local_shipping_rounded),
  'tricycle': (label: 'Kloboto', icon: Icons.electric_rickshaw_rounded),
};

_Genre _genreDe(Prestataire p) {
  final k = (p.kind ?? '').toLowerCase();
  if (k.isNotEmpty) {
    if (k == 'zemidjan') return _Genre.zemidjan;
    if (k == 'tricycle_fret') return _Genre.kloboto;
    return _Genre.depanneur;
  }
  final m = p.metier.toLowerCase();
  if (m.contains('zÃƒÂ©midjan') || m.contains('zemidjan')) {
    return _Genre.zemidjan;
  }
  if (m.contains('kloboto') || m.contains('klobot')) return _Genre.kloboto;
  return _Genre.depanneur;
}

// ----------------------------------------------------------------------------
// Ãƒâ€°cran
// ----------------------------------------------------------------------------

/// Ãƒâ€°cran d'ouverture de MonTotem : la carte plein ÃƒÂ©cran, comme Google Maps.
///
/// - Visiteur : voit la carte et les points (zÃƒÂ©midjan, kloboto, dÃƒÂ©panneurs),
///   circule librement, mais doit se connecter pour voir les infos d'un
///   prestataire ou commander une course.
/// - ConnectÃƒÂ© : mÃƒÂªmes ÃƒÂ©crans, plus fiches complÃƒÂ¨tes, courses et demandes.
class MapHomeScreen extends StatefulWidget {
  const MapHomeScreen({super.key});

  @override
  State<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends State<MapHomeScreen> {
  static const double _rayonKm = 15;
  static const Distance _distance = Distance();

  final MapController _mapController = MapController();
  final RoutingService _routingService = RoutingService();
  final LocationService _locationService = LocationService();
  final MatchingService _matchingService = MatchingService();

  StreamSubscription<AuthState>? _authSub;

  LatLng _userPosition = const LatLng(
    AppConstants.initialLatitude,
    AppConstants.initialLongitude,
  );
  bool _positionReelle = false;
  bool _isMapReady = false;
  bool _isLoading = true;
  bool _routeEnCours = false;
  String? _errorMessage;

  _Cat _cat = _Cat.tous;
  String? _vehiculePanne; // seulement si _cat == depannage
  bool _seulementDispos = false;
  String? _selectedId;

  List<Prestataire> _tous = [];
  List<Prestataire> _dansRayon = [];
  List<Prestataire> _visibles = [];
  List<LatLng> _routeGeometry = const [];

  /// id prestataire -> types de vÃƒÂ©hicules (RPC publique provider_vehicle_map).
  Map<String, List<String>> _vehicules = const {};

  bool get _connecte => Supabase.instance.client.auth.currentSession != null;

  Prestataire? get _selection {
    final id = _selectedId;
    if (id == null) return null;
    for (final p in _visibles) {
      if (p.id == id) return p;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // La carte s'affiche tout de suite ; position et donnÃƒÂ©es arrivent aprÃƒÂ¨s.
    unawaited(_localiser());
    unawaited(_chargerDonnees());
    // Connexion / dÃƒÂ©connexion : on recharge (un visiteur ne reÃƒÂ§oit que des
    // points anonymes, un connectÃƒÂ© reÃƒÂ§oit les fiches complÃƒÂ¨tes).
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      setState(() => _selectedId = null);
      unawaited(_chargerDonnees(silencieux: true));
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ DonnÃƒÂ©es Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Future<void> _chargerDonnees({bool silencieux = false}) async {
    if (!silencieux) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final resultats = await Future.wait([
        _matchingService.obtenirPourCarte(),
        _chargerVehicules(),
      ]);
      if (!mounted) return;
      setState(() {
        _tous = resultats[0] as List<Prestataire>;
        _vehicules = resultats[1] as Map<String, List<String>>;
        _errorMessage = null;
        _recalculer();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Impossible de charger la carte. VÃƒÂ©rifiez votre connexion.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Ne lÃƒÂ¨ve jamais : sans cette RPC, les filtres montrent simplement tout.
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

  /// Ne lÃƒÂ¨ve jamais : sans GPS on garde la position de repli (Cotonou).
  Future<void> _localiser({bool message = false}) async {
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
    } on LocationPermissionException catch (e) {
      if (message && mounted) _msg(e.message);
    } catch (_) {
      if (message && mounted) {
        _msg('Impossible de vous localiser. Activez le GPS.');
      }
    }
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // Ã¢â€â‚¬Ã¢â€â‚¬ Filtres Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  bool _typeOk(Prestataire p, String type) {
    final types = _vehicules[p.id];
    if (types == null || types.isEmpty) return true; // ancien dossier
    return types.contains(type);
  }

  bool _passe(Prestataire p) {
    final g = _genreDe(p);
    if (_cat == _Cat.zemidjan && g != _Genre.zemidjan) return false;
    if (_cat == _Cat.kloboto && g != _Genre.kloboto) return false;
    if (_cat == _Cat.depannage) {
      if (g != _Genre.depanneur) return false;
      final v = _vehiculePanne;
      if (v != null && !_typeOk(p, v)) return false;
    }
    if (_seulementDispos && !p.disponible) return false;
    return true;
  }

  double _km(Prestataire p) => _distance.as(
    LengthUnit.Kilometer,
    _userPosition,
    LatLng(p.latitude, p.longitude),
  );

  int _eta(double km) => math.max(1, (km * 1.25 / 25 * 60).ceil());

  /// RÃƒÂ©sultats triÃƒÂ©s par distance croissante.
  void _recalculer() {
    _dansRayon = _tous.where((p) => _km(p) <= _rayonKm).toList();
    _visibles = _dansRayon.where(_passe).toList()
      ..sort((a, b) => _km(a).compareTo(_km(b)));
  }

  int _nbGenre(_Genre g) =>
      _dansRayon.where((p) => _genreDe(p) == g && p.disponible).length;

  int _nbPanne(String type) => _dansRayon
      .where(
        (p) =>
            _genreDe(p) == _Genre.depanneur && p.disponible && _typeOk(p, type),
      )
      .length;

  void _choisirCat(_Cat c) {
    setState(() {
      _cat = c;
      _vehiculePanne = null;
      _selectedId = null;
      _routeGeometry = const [];
      _recalculer();
    });
  }

  void _reinitialiser() {
    setState(() {
      _cat = _Cat.tous;
      _vehiculePanne = null;
      _seulementDispos = false;
      _selectedId = null;
      _recalculer();
    });
  }

  /// DÃƒÂ©pannage express : on ne garde que les dÃƒÂ©panneurs disponibles qui
  /// prennent en charge ce vÃƒÂ©hicule, et on prÃƒÂ©sÃƒÂ©lectionne le plus proche.
  void _lancerDepannage(String vehicule) {
    setState(() {
      _cat = _Cat.depannage;
      _vehiculePanne = vehicule;
      _seulementDispos = true;
      _selectedId = null;
      _routeGeometry = const [];
      _recalculer();
    });
    if (_visibles.isNotEmpty) {
      _selectionner(_visibles.first);
    } else {
      _msg(
        'Aucun dÃƒÂ©panneur disponible ÃƒÂ  moins de ${_rayonKm.toInt()} km '
        'pour ce vÃƒÂ©hicule.',
      );
    }
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Actions Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  void _selectionner(Prestataire p) {
    setState(() => _selectedId = p.id);
    if (_isMapReady) {
      _mapController.move(
        LatLng(p.latitude, p.longitude),
        math.max(_mapController.camera.zoom, 15),
      );
    }
  }

  /// Course ZÃƒÂ©midjan / Kloboto : compte obligatoire.
  void _commander(String codeCourse) {
    requireAuth(
      context,
      action: GatedAction.course,
      onAllowed: () => context.push('/ride/new?kind=$codeCourse'),
    );
  }

  /// Infos complÃƒÂ¨tes d'un prestataire : compte obligatoire.
  void _voirInfos(Prestataire p) {
    requireAuth(
      context,
      action: GatedAction.voirInfos,
      onAllowed: () {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          constraints: const BoxConstraints(maxWidth: 640),
          showDragHandle: true,
          useSafeArea: true,
          builder: (_) => ProviderDetailSheet(
            prestataire: p,
            distanceKm: _km(p),
            onItineraire: () => _itineraire(p),
          ),
        );
      },
    );
  }

  void _demanderDepannage(Prestataire p) {
    requireAuth(
      context,
      action: GatedAction.depannage,
      onAllowed: () => context.push('/nouvelle-demande', extra: p),
    );
  }

  Future<void> _itineraire(Prestataire p) async {
    if (_routeEnCours) return;
    setState(() => _routeEnCours = true);
    try {
      // getRoutes ne lÃƒÂ¨ve pas : repli sur une ligne droite si OSRM ÃƒÂ©choue.
      final routes = await _routingService.getRoutes(
        origin: _userPosition,
        destination: LatLng(p.latitude, p.longitude),
      );
      if (!mounted || routes.isEmpty) return;
      final geom = routes.first.geometry;
      setState(() => _routeGeometry = geom);
      if (_isMapReady && geom.length >= 2) {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: geom,
            padding: const EdgeInsets.fromLTRB(40, 160, 40, 300),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _routeEnCours = false);
    }
  }

  Future<void> _deconnecter() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se dÃƒÂ©connecter ?'),
        content: const Text(
          'Vous pourrez vous reconnecter ÃƒÂ  tout moment.',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Se dÃƒÂ©connecter'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.auth.signOut();
      if (mounted) _msg('Vous ÃƒÂªtes dÃƒÂ©connectÃƒÂ©.');
    } catch (_) {
      if (mounted) _msg('DÃƒÂ©connexion impossible. RÃƒÂ©essayez.');
    }
  }

  void _surMenu(String valeur) {
    if (valeur == 'logout') {
      _deconnecter();
    } else {
      context.push(valeur);
    }
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Feuilles (recherche, panne, liste) Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  void _ouvrirRecherche() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Que cherchez-vous ?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              _OptionTile(
                icon: Icons.two_wheeler_rounded,
                color: _Genre.zemidjan.color,
                titre: 'ZÃƒÂ©midjan',
                sousTitre:
                    '${_nbGenre(_Genre.zemidjan)} disponible(s) prÃƒÂ¨s '
                    'de vous',
                onTap: () {
                  Navigator.pop(ctx);
                  _choisirCat(_Cat.zemidjan);
                },
              ),
              const SizedBox(height: 10),
              _OptionTile(
                icon: Icons.electric_rickshaw_rounded,
                color: _Genre.kloboto.color,
                titre: 'Kloboto (tricycle)',
                sousTitre:
                    '${_nbGenre(_Genre.kloboto)} disponible(s) prÃƒÂ¨s '
                    'de vous',
                onTap: () {
                  Navigator.pop(ctx);
                  _choisirCat(_Cat.kloboto);
                },
              ),
              const SizedBox(height: 10),
              _OptionTile(
                icon: Icons.car_crash_rounded,
                color: _Genre.depanneur.color,
                titre: 'DÃƒÂ©pannage express',
                sousTitre: 'Moto, voiture, camion ou kloboto en panne',
                onTap: () {
                  Navigator.pop(ctx);
                  _ouvrirPanne();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _ouvrirPanne() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Quel vÃƒÂ©hicule est en panne ?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Nous affichons les dÃƒÂ©panneurs disponibles les plus proches '
                'de vous, pour une rÃƒÂ©paration express.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              for (final e in _vehiculesPanne.entries) ...[
                _OptionTile(
                  icon: e.value.icon,
                  color: _Genre.depanneur.color,
                  titre: e.value.label,
                  sousTitre: _isLoading
                      ? 'RechercheÃ¢â‚¬Â¦'
                      : '${_nbPanne(e.key)} dÃƒÂ©panneur(s) disponible(s)',
                  onTap: () {
                    Navigator.pop(ctx);
                    _lancerDepannage(e.key);
                  },
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _ouvrirListe() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (ctx, controller) {
          if (_visibles.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucun rÃƒÂ©sultat ÃƒÂ  proximitÃƒÂ©.',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            );
          }
          return ListView.separated(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            itemCount: _visibles.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final p = _visibles[i];
              final g = _genreDe(p);
              final km = _km(p);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: g.color.withValues(alpha: 0.15),
                  child: Icon(g.icon, color: g.color),
                ),
                title: Text(
                  _titre(p),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${km.toStringAsFixed(1)} km Ã‚Â· Ã¢â€°Ë† ${_eta(km)} min'
                  ' Ã‚Â· ${p.disponible ? 'Disponible' : 'Indisponible'}',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _selectionner(p);
                },
              );
            },
          );
        },
      ),
    );
  }

  /// Un visiteur ne voit jamais le nom : seulement le type de prestataire.
  String _titre(Prestataire p) =>
      _connecte ? p.nomAffiche : '${_genreDe(p).label} prÃƒÂ¨s de vous';

  // Ã¢â€â‚¬Ã¢â€â‚¬ UI Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _carte(),
          if (_isLoading || _routeEnCours)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 3),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _barreRecherche(context),
                        const SizedBox(height: 8),
                        _chips(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            if (_routeGeometry.isNotEmpty)
                              ActionChip(
                                avatar: const Icon(
                                  Icons.close_rounded,
                                  size: 20,
                                ),
                                label: const Text('Effacer l\'itinÃƒÂ©raire'),
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surface,
                                onPressed: () =>
                                    setState(() => _routeGeometry = const []),
                              ),
                            const Spacer(),
                            FloatingActionButton.small(
                              heroTag: 'map_home_locate',
                              tooltip: 'Ma position',
                              onPressed: () => _localiser(message: true),
                              child: const Icon(Icons.my_location_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _panneau(context),
                        const SizedBox(height: 4),
                        Text(
                          'Ã‚Â© OpenStreetMap contributors',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _carte() {
    return FlutterMap(
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
        onTap: (_, _) {
          if (_selectedId != null) setState(() => _selectedId = null);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'bj.totem.app',
        ),
        if (_routeGeometry.length >= 2) createPolylineLayer(_routeGeometry),
        MarkerLayer(markers: _markers()),
      ],
    );
  }

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
        final taille = sel ? 58.0 : 44.0;
        return Marker(
          point: LatLng(p.latitude, p.longitude),
          width: taille,
          height: taille,
          child: GestureDetector(
            onTap: () => _selectionner(p),
            child: _ProviderMarker(
              genre: _genreDe(p),
              disponible: p.disponible,
              selected: sel,
            ),
          ),
        );
      }),
    ];
  }

  Widget _barreRecherche(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Rechercher un zÃƒÂ©midjan, un kloboto ou un dÃƒÂ©panneur',
      child: Material(
        elevation: 6,
        shadowColor: Colors.black45,
        color: scheme.surface,
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: _ouvrirRecherche,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: scheme.primary, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'ZÃƒÂ©midjan, kloboto, dÃƒÂ©pannageÃ¢â‚¬Â¦',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16.5,
                        color: context.textSecondary,
                      ),
                    ),
                  ),
                  _avatar(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = Supabase.instance.client.auth.currentUser;
    final identite = (user?.email?.isNotEmpty ?? false)
        ? user!.email!
        : (user?.phone ?? 'Mon compte');

    return PopupMenuButton<String>(
      tooltip: _connecte ? 'Mon compte' : 'Se connecter',
      offset: const Offset(0, 48),
      onSelected: _surMenu,
      itemBuilder: (_) => _connecte
          ? [
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  identite,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const PopupMenuItem(
                value: '/rides',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.two_wheeler_rounded),
                  title: Text('Mes courses'),
                ),
              ),
              const PopupMenuItem(
                value: '/mes-demandes',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.receipt_long_outlined),
                  title: Text('Mes demandes de dÃƒÂ©pannage'),
                ),
              ),
              const PopupMenuItem(
                value: '/account',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.person_outline_rounded),
                  title: Text('Mon compte'),
                ),
              ),
              const PopupMenuItem(
                value: '/emergency',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.local_hospital_outlined),
                  title: Text('NumÃƒÂ©ros d\'urgence'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.logout_rounded,
                    color: AppTheme.errorColor,
                  ),
                  title: Text(
                    'Se dÃƒÂ©connecter',
                    style: TextStyle(color: AppTheme.errorColor),
                  ),
                ),
              ),
            ]
          : const [
              PopupMenuItem(
                value: '/register/quick?role=client',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.phone_iphone_rounded),
                  title: Text('S\'inscrire / se connecter'),
                ),
              ),
              PopupMenuItem(
                value: '/login',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.password_rounded),
                  title: Text('Connexion avec mot de passe'),
                ),
              ),
              PopupMenuItem(
                value: '/register/quick?role=provider',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.build_circle_outlined),
                  title: Text('Devenir prestataire'),
                ),
              ),
              PopupMenuItem(
                value: '/emergency',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.local_hospital_outlined),
                  title: Text('NumÃƒÂ©ros d\'urgence'),
                ),
              ),
            ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: CircleAvatar(
          radius: 19,
          backgroundColor: scheme.primary,
          child: Icon(
            _connecte ? Icons.person_rounded : Icons.person_outline_rounded,
            color: scheme.onPrimary,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _chips(BuildContext context) {
    final panne = _cat == _Cat.depannage;
    final vp = _vehiculePanne;
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(
            context,
            'Tous',
            Icons.apps_rounded,
            _cat == _Cat.tous,
            _reinitialiser,
          ),
          _chip(
            context,
            'ZÃƒÂ©midjan',
            Icons.two_wheeler_rounded,
            _cat == _Cat.zemidjan,
            () => _choisirCat(_Cat.zemidjan),
          ),
          _chip(
            context,
            'Kloboto',
            Icons.electric_rickshaw_rounded,
            _cat == _Cat.kloboto,
            () => _choisirCat(_Cat.kloboto),
          ),
          _chip(
            context,
            panne && vp != null
                ? 'DÃƒÂ©pannage Ã‚Â· ${_vehiculesPanne[vp]!.label}'
                : 'DÃƒÂ©pannage',
            Icons.build_rounded,
            panne,
            _ouvrirPanne,
          ),
          _chip(
            context,
            'Disponibles',
            Icons.bolt_rounded,
            _seulementDispos,
            () {
              setState(() {
                _seulementDispos = !_seulementDispos;
                _selectedId = null;
                _recalculer();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimary : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          elevation: 3,
          shadowColor: Colors.black38,
          color: selected ? scheme.primary : scheme.surface,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 19, color: fg),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Panneau du bas Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  Widget _panneau(BuildContext context) {
    final sel = _selection;
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: _errorMessage != null
          ? _erreur()
          : sel != null
          ? _carteSelection(context, sel)
          : _actions(context),
    );
  }

  Widget _erreur() {
    return Row(
      children: [
        const Icon(Icons.cloud_off_rounded, color: AppTheme.errorColor),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _errorMessage!,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        TextButton(
          onPressed: _chargerDonnees,
          child: const Text('RÃƒÂ©essayer'),
        ),
      ],
    );
  }

  Widget _actions(BuildContext context) {
    final n = _visibles.length;
    final filtresActifs = _cat != _Cat.tous || _seulementDispos;
    final titre = _isLoading
        ? 'Recherche en coursÃ¢â‚¬Â¦'
        : n == 0
        ? 'Aucun rÃƒÂ©sultat ÃƒÂ  moins de ${_rayonKm.toInt()} km'
        : '$n autour de vous';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                titre,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (n > 0)
              TextButton(
                onPressed: _ouvrirListe,
                child: const Text('Voir la liste'),
              ),
            if (n == 0 && filtresActifs && !_isLoading)
              TextButton(
                onPressed: _reinitialiser,
                child: const Text('Voir tout'),
              ),
          ],
        ),
        if (!_connecte)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Explorez librement. Connectez-vous pour commander une course '
              'ou voir les infos d\'un prestataire.',
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: context.textSecondary,
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'ZÃƒÂ©midjan',
                icon: Icons.two_wheeler_rounded,
                onPressed: () => _commander('zemidjan'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppButton(
                label: 'Kloboto',
                icon: Icons.electric_rickshaw_rounded,
                onPressed: () => _commander('tricycle_fret'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AppButton(
          label: 'Panne ? DÃƒÂ©pannage express',
          icon: Icons.car_crash_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: _ouvrirPanne,
        ),
      ],
    );
  }

  Widget _carteSelection(BuildContext context, Prestataire p) {
    final g = _genreDe(p);
    final km = _km(p);
    final connecte = _connecte;
    final conducteur = g.codeCourse != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: g.color.withValues(alpha: 0.15),
              child: Icon(g.icon, color: g.color, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titre(p),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    connecte ? p.metier : 'Connectez-vous pour voir son profil',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Fermer',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _selectedId = null),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            StatusPill(
              label: '${km.toStringAsFixed(1)} km Ã‚Â· Ã¢â€°Ë† ${_eta(km)} min',
              color: AppTheme.primaryColor,
              icon: Icons.near_me_rounded,
            ),
            StatusPill(
              label: p.disponible ? 'Disponible' : 'Indisponible',
              color: p.disponible ? AppTheme.successColor : Colors.grey,
            ),
            if (connecte)
              StatusPill(
                label: p.noteMoyenne.toStringAsFixed(1),
                color: AppColors.gold,
                icon: Icons.star_rounded,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (conducteur)
          AppButton(
            label: g == _Genre.zemidjan
                ? 'Commander un zÃƒÂ©midjan'
                : 'Commander un kloboto',
            icon: g.icon,
            onPressed: () => _commander(g.codeCourse!),
          )
        else
          AppButton(
            label: 'Demander un dÃƒÂ©pannage',
            icon: Icons.build_rounded,
            onPressed: () => _demanderDepannage(p),
          ),
        const SizedBox(height: 8),
        AppButton(
          label: connecte
              ? 'Voir les infos'
              : 'Se connecter pour voir les infos',
          icon: connecte
              ? Icons.info_outline_rounded
              : Icons.lock_outline_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: () => _voirInfos(p),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Widgets
// ----------------------------------------------------------------------------

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.color,
    required this.titre,
    required this.sousTitre,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 30, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titre,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  sousTitre,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _UserDot extends StatelessWidget {
  const _UserDot();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.2),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.blue,
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
  const _ProviderMarker({
    required this.genre,
    required this.disponible,
    required this.selected,
  });

  final _Genre genre;
  final bool disponible;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ring = disponible ? genre.color : Colors.grey.shade600;
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
        genre.icon,
        size: selected ? 28 : 22,
        color: selected ? Colors.white : ring,
      ),
    );
  }
}
