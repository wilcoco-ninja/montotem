import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import 'package:montotem/core/constants/app_constants.dart';
import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/utils/responsive.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/emergency/data/emergency_actions.dart';
import 'package:montotem/features/emergency/data/emergency_connectivity.dart';
import 'package:montotem/features/emergency/data/emergency_numbers_repository.dart';
import 'package:montotem/features/emergency/data/emergency_places_repository.dart';
import 'package:montotem/features/emergency/data/emergency_preparation.dart';
import 'package:montotem/features/emergency/data/emergency_tile_provider.dart';
import 'package:montotem/features/emergency/domain/emergency_models.dart';

class EmergencyServicesScreen extends StatefulWidget {
  const EmergencyServicesScreen({super.key});

  @override
  State<EmergencyServicesScreen> createState() =>
      _EmergencyServicesScreenState();
}

class _EmergencyServicesScreenState extends State<EmergencyServicesScreen> {
  final EmergencyNumbersRepository _numeros =
      EmergencyNumbersRepository.instance;
  final EmergencyPlacesRepository _lieux = EmergencyPlacesRepository.instance;
  final MapController _map = MapController();
  final CachedTileProvider _tuiles = CachedTileProvider();

  LatLng _centre = const LatLng(
    AppConstants.initialLatitude,
    AppConstants.initialLongitude,
  );
  bool _positionReelle = false;
  bool _mapPrete = false;
  bool _horsLigne = false;
  bool _preparation = false;
  ServiceKind? _filtre;
  StreamSubscription<bool>? _connSub;

  CountryNumbers get _pays => _numeros.resoudre(
    lat: _positionReelle ? _centre.latitude : null,
    lng: _positionReelle ? _centre.longitude : null,
  );

  @override
  void initState() {
    super.initState();
    _numeros.init().then((_) {
      if (mounted) setState(() {});
    });
    _lieux.charger().then((_) {
      if (mounted) setState(() {});
    });
    estHorsLigne().then((v) {
      if (mounted) setState(() => _horsLigne = v);
    });
    _connSub = horsLigneStream().listen((v) {
      if (mounted) setState(() => _horsLigne = v);
    });
    _localiser();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _localiser() async {
    final d = await SosLocator.derniere();
    if (mounted && d != null) _definirPosition(LatLng(d.latitude, d.longitude));
    final a = await SosLocator.actuelle();
    if (mounted && a != null) {
      final p = LatLng(a.latitude, a.longitude);
      _definirPosition(p);
      unawaited(EmergencyPreparation.lancer(p));
    }
  }

  void _definirPosition(LatLng p) {
    setState(() {
      _centre = p;
      _positionReelle = true;
    });
    if (_mapPrete) _map.move(p, 14);
  }

  Future<void> _preparer() async {
    if (_preparation) return;
    setState(() => _preparation = true);
    await _lieux.preparer(_centre, force: true);
    unawaited(TileDiskCache.instance.prechargerAutour(_centre));
    if (!mounted) return;
    setState(() => _preparation = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _lieux.vide
              ? 'Aucune donnée reçue. Vérifiez votre connexion et réessayez.'
              : 'Zone préparée : disponible hors ligne.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pays = _pays;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Services d\'urgence'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sos_outlined),
            tooltip: 'SOS',
            onPressed: () => context.push('/sos'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Préparer ma zone',
            onPressed: (_horsLigne || _preparation) ? null : _preparer,
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gutter = context.gutter;
            if (constraints.maxWidth >= 900) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(gutter, 4, gutter / 2, 32),
                      children: _blocNumeros(pays),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(gutter / 2, 4, gutter, 32),
                      children: [..._blocCarte(hauteur: 340), ..._blocListe()],
                    ),
                  ),
                ],
              );
            }
            return ContentWidth(
              maxWidth: 800,
              child: ListView(
                padding: EdgeInsets.fromLTRB(gutter, 4, gutter, 32),
                children: [
                  ..._blocNumeros(pays),
                  ..._blocCarte(hauteur: 260),
                  ..._blocListe(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _banniereHorsLigne() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.warningColor.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 26),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hors ligne : les données enregistrées sur ce téléphone sont utilisées.',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _blocNumeros(CountryNumbers pays) {
    return [
      if (_horsLigne) _banniereHorsLigne(),
      Text(
        'Numéros d\'urgence : ${pays.nom}',
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      ),
      if (pays.confiance != Confiance.officiel)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            pays.confiance == Confiance.recoupe
                ? 'Numéros recoupés entre plusieurs sources publiques, pas '
                      'encore confirmés par l\'autorité nationale.'
                : 'Numéros à confirmer pour ce pays. Si l\'appel n\'aboutit '
                      'pas, essayez le 112.',
            style: TextStyle(
              fontSize: 14.5,
              height: 1.35,
              color: context.readable(AppTheme.warningColor),
            ),
          ),
        ),
      const SizedBox(height: 10),
      AdaptiveGrid(
        minItemWidth: 340,
        maxColumns: 2,
        spacing: 10,
        children: [
          for (final k in ServiceKind.values)
            _BoutonAppel(
              kind: k,
              numero: pays.numero(k),
              onTap: () => appelerNumero(pays.numero(k)),
            ),
        ],
      ),
    ];
  }

  List<Widget> _blocCarte({required double hauteur}) {
    final proches = _lieux.plusProches(_centre, kind: _filtre, limite: 15);
    return [
      const SectionTitle('Carte'),
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: hauteur,
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _centre,
              initialZoom: 14,
              onMapReady: () {
                _mapPrete = true;
                if (_positionReelle) _map.move(_centre, 14);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'bj.totem.app',
                tileProvider: _tuiles,
              ),
              MarkerLayer(
                markers: [
                  if (_positionReelle)
                    Marker(
                      point: _centre,
                      width: 30,
                      height: 30,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  for (final p in proches)
                    Marker(
                      point: p.lieu.position,
                      width: 46,
                      height: 46,
                      child: GestureDetector(
                        onTap: () =>
                            context.push('/emergency/route', extra: p.lieu),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: p.lieu.kind.couleur,
                              width: 3,
                            ),
                          ),
                          child: Icon(
                            p.lieu.kind.icone,
                            color: p.lieu.kind.couleur,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Tous'),
            selected: _filtre == null,
            showCheckmark: false,
            onSelected: (_) => setState(() => _filtre = null),
          ),
          for (final k in ServiceKind.values)
            ChoiceChip(
              avatar: Icon(k.icone, size: 20, color: k.couleur),
              label: Text(k.libelleLieu),
              selected: _filtre == k,
              showCheckmark: false,
              onSelected: (_) => setState(() => _filtre = k),
            ),
        ],
      ),
    ];
  }

  List<Widget> _blocListe() {
    final proches = _lieux.plusProches(_centre, kind: _filtre, limite: 15);
    return [
      const SectionTitle('Les plus proches'),
      if (_lieux.vide) ...[
        const EmptyState(
          icon: Icons.cloud_download_outlined,
          title: 'Aucun établissement enregistré',
          message:
              'Avec internet, préparez votre zone une fois : la liste, '
              'les itinéraires et la carte restent ensuite disponibles hors ligne.',
        ),
        const SizedBox(height: 14),
        AppButton(
          label: _preparation ? 'Préparation…' : 'Préparer ma zone',
          icon: Icons.download_rounded,
          loading: _preparation,
          onPressed: _horsLigne ? null : _preparer,
        ),
      ] else ...[
        AdaptiveGrid(
          minItemWidth: 360,
          maxColumns: 2,
          spacing: 10,
          children: [
            for (final p in proches)
              SoftCard(
                onTap: () => context.push('/emergency/route', extra: p.lieu),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: p.lieu.kind.couleur.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        p.lieu.kind.icone,
                        color: p.lieu.kind.couleur,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.lieu.nom,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${p.km.toStringAsFixed(1)} km à vol d\'oiseau',
                            style: TextStyle(
                              fontSize: 14.5,
                              color: context.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (p.lieu.telephone != null)
                      IconButton.filledTonal(
                        iconSize: 26,
                        tooltip: 'Appeler',
                        icon: const Icon(Icons.call_rounded),
                        onPressed: () => appelerNumero(p.lieu.telephone!),
                      ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
          ],
        ),
        if (_lieux.dateMiseAJour != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Données enregistrées le ${_lieux.dateMiseAJour!.day.toString().padLeft(2, '0')}/'
              '${_lieux.dateMiseAJour!.month.toString().padLeft(2, '0')}/'
              '${_lieux.dateMiseAJour!.year}.',
              style: TextStyle(fontSize: 14, color: context.textTertiary),
            ),
          ),
      ],
    ];
  }
}

class _BoutonAppel extends StatelessWidget {
  const _BoutonAppel({
    required this.kind,
    required this.numero,
    required this.onTap,
  });

  final ServiceKind kind;
  final String numero;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Semantics(
      button: true,
      label: 'Appeler ${kind.libelle}, numéro $numero',
      child: Material(
        color: kind.couleur,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(kind.icone, color: Colors.white, size: 34),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    kind.libelle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  numero,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.call_rounded, color: Colors.white, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
