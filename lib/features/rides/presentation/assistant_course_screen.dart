// lib/features/rides/presentation/assistant_course_screen.dart
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart' hide iconePourMetier;
import 'package:montotem/features/auth/data/location_service.dart';
import 'package:montotem/features/sos/data/providers_nearest_service.dart';
import 'package:montotem/features/tracking/domain/prestataire_model.dart'
    show Prestataire, iconePourMetier;

/// Assistant Course : choisir ZÃƒÂ©midjan / Cloboto / Kloboto,
/// puis voir les conducteurs proches.
class AssistantCourseScreen extends StatefulWidget {
  const AssistantCourseScreen({super.key});

  @override
  State<AssistantCourseScreen> createState() => _AssistantCourseScreenState();
}

class _AssistantCourseScreenState extends State<AssistantCourseScreen> {
  final _location = LocationService();

  String? _kindChoisi;
  LatLng? _me;
  List<Prestataire> _prestatairesList = const [];
  bool _chargement = false;
  String? _erreur;

  Future<void> _choisir(String kind) async {
    setState(() {
      _kindChoisi = kind;
      _chargement = true;
      _erreur = null;
    });

    // 1) Position (peut lever LocationPermissionException)
    LatLng pos;
    try {
      if (_me != null) {
        pos = _me!;
      } else {
        // Ã¢Å¡Â Ã¯Â¸Â Typage explicite : `getCurrentLocation()` retourne `Position`.
        final Position p = await _location.getCurrentLocation();
        pos = LatLng(p.latitude, p.longitude);
      }
      _me = pos;
    } on LocationPermissionException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erreur = 'Activez votre GPS pour trouver un conducteur.';
        _chargement = false;
      });
      return;
    }

    // 2) Recherche des conducteurs (peut lever)
    try {
      final liste = await ProvidersNearestService().chercher(
        position: pos,
        kind: kind,
        rayonKm: 5,
        limite: 3,
      );
      if (!mounted) return;
      setState(() {
        _prestatairesList = liste;
        _chargement = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erreur = 'Recherche indisponible. VÃƒÂ©rifiez votre connexion.';
        _prestatairesList = const [];
        _chargement = false;
      });
    }
  }

  Future<void> _ouvrirCourse() async {
    final kind = _kindChoisi;
    if (kind == null) return;
    await context.push('/ride/new?kind=$kind');
  }

  Future<void> _appeler(String? tel) async {
    final clean = tel?.replaceAll(RegExp(r'[^\d+]'), '');
    if (clean == null || clean.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: clean));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _kindChoisi == null ? 'Prendre une course' : 'Conducteurs proches',
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (_kindChoisi != null) {
              setState(() {
                _kindChoisi = null;
                _prestatairesList = const [];
                _erreur = null;
              });
            } else {
              context.pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_erreur != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: colorScheme.errorContainer,
                child: Text(
                  _erreur!,
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            Expanded(
              child: _kindChoisi == null ? _choixKind() : _buildResultatsView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _choixKind() {
    final colorScheme = Theme.of(context).colorScheme;
    return ContentWidth(
      maxWidth: 640,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Quel type de course ?',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Choisissez le vÃƒÂ©hicule qui correspond ÃƒÂ  votre besoin.',
            style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          _CarteKind(
            kind: 'zemidjan',
            titre: 'ZÃƒÂ©midjan',
            sousTitre: 'Moto-taxi Ã‚Â· 1 passager',
            icon: Icons.two_wheeler_rounded,
            couleur: const Color(0xFFFFC400),
            onTap: () => _choisir('zemidjan'),
          ),
          const SizedBox(height: 14),
          _CarteKind(
            kind: 'tricycle_passenger',
            titre: 'Cloboto',
            sousTitre: 'Tricycle Ã‚Â· 2 ÃƒÂ  3 passagers',
            icon: Icons.electric_rickshaw_rounded,
            couleur: const Color(0xFFFFC400),
            onTap: () => _choisir('tricycle_passenger'),
          ),
          const SizedBox(height: 14),
          _CarteKind(
            kind: 'tricycle_fret',
            titre: 'Kloboto',
            sousTitre: 'Tricycle Ã‚Â· bagages, colis, marchandises',
            icon: Icons.inventory_2_rounded,
            couleur: const Color(0xFF2E7D32),
            onTap: () => _choisir('tricycle_fret'),
          ),
        ],
      ),
    );
  }

  Widget _buildResultatsView() {
    if (_chargement) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Recherche des conducteurs prochesÃ¢â‚¬Â¦'),
          ],
        ),
      );
    }
    if (_prestatairesList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Aucun conducteur ÃƒÂ  proximitÃƒÂ©.',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),
              AppButton(
                label: 'Commander une course',
                icon: Icons.local_taxi_rounded,
                onPressed: _ouvrirCourse,
              ),
            ],
          ),
        ),
      );
    }
    return ContentWidth(
      maxWidth: 640,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${_prestatairesList.length} conducteur'
            '${_prestatairesList.length > 1 ? 's' : ''} proche'
            '${_prestatairesList.length > 1 ? 's' : ''}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          for (final p in _prestatairesList) ...[
            _CarteConducteur(
              conducteur: p,
              onAppeler: () => _appeler(p.telephone),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 16),
          AppButton(
            label: 'Commander une course',
            icon: Icons.local_taxi_rounded,
            onPressed: _ouvrirCourse,
          ),
        ],
      ),
    );
  }
}

class _CarteKind extends StatelessWidget {
  const _CarteKind({
    required this.kind,
    required this.titre,
    required this.sousTitre,
    required this.icon,
    required this.couleur,
    required this.onTap,
  });

  final String kind;
  final String titre;
  final String sousTitre;
  final IconData icon;
  final Color couleur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '$titre. $sousTitre',
      excludeSemantics: true,
      child: Material(
        color: couleur.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          side: BorderSide(color: couleur.withValues(alpha: 0.5), width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: couleur.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: couleur, size: 36),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titre,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sousTitre,
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: couleur, size: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CarteConducteur extends StatelessWidget {
  const _CarteConducteur({required this.conducteur, required this.onAppeler});

  final Prestataire conducteur;
  final VoidCallback onAppeler;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tel = conducteur.telephone;
    return SoftCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              iconePourMetier(conducteur.metier),
              size: 30,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conducteur.nomAffiche,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${conducteur.metier} Ã‚Â· '
                  '${conducteur.noteMoyenne.toStringAsFixed(1)} Ã¢Ëœâ€¦',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            icon: const Icon(Icons.call_rounded),
            onPressed: (tel == null || tel.isEmpty) ? null : onAppeler,
          ),
        ],
      ),
    );
  }
}
