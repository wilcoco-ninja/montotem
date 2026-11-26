import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/features/auth/data/location_service.dart';
import 'package:montotem/features/sos/data/providers_nearest_service.dart';
import 'package:montotem/features/sos/data/sos_service.dart';
import 'package:montotem/features/sos/domain/sos_constants.dart';

/// Écran « SOS Je Suis En Panne » — parcours strict en 4 étapes :
///   1. Position exacte sur la route + niveau de sécurité de la chaussée ;
///   2. Véhicule au moment de la panne (14 codes officiels) ;
///   3. Type de panne — filtrage dynamique strict selon le véhicule ;
///   4. Prestataires compatibles + devis transparent + commande garantie.
class AssistantPanneScreen extends StatefulWidget {
  const AssistantPanneScreen({super.key});

  @override
  State<AssistantPanneScreen> createState() => _AssistantPanneScreenState();
}

enum _Etape { position, vehicule, panne, resultat }

class _AssistantPanneScreenState extends State<AssistantPanneScreen> {
  final LocationService _location = LocationService();
  final SosService _sos = SosService.instance;
  final ProvidersNearestService _proximite = ProvidersNearestService();

  _Etape _etape = _Etape.position;

  // Étape 1 — position (Cotonou par défaut si le GPS échoue) + sécurité.
  double _lat = 6.3703;
  double _lng = 2.3912;
  String _repere = 'Position GPS en cours...';
  bool _gpsFiable = false;
  SosNiveauSecurite _niveau = SosNiveauSecurite.attention;
  bool _localisationEnCours = true;

  // Étape 2 — véhicule.
  SosVehicule? _vehicule;

  // Étape 3 — panne.
  List<SosPanne> _pannes = const [];
  bool _pannesEnCours = false;
  String? _pannesErreur;
  SosPanne? _panne;

  // Étape 4 — prestataires + devis.
  List<SosPrestataire> _resultats = const [];
  bool _rechercheEnCours = false;
  String? _resultatsErreur;
  List<SosPrestataire> _contactsSecteur = const [];
  String? _commandeEnCours;

  @override
  void initState() {
    super.initState();
    _capturerPosition();
  }

  // ---------------------------------------------------------------------------
  // Étape 1 : GPS + repère local proche
  // ---------------------------------------------------------------------------
  Future<void> _capturerPosition() async {
    if (!mounted) return;
    setState(() {
      _localisationEnCours = true;
      _repere = 'Position GPS en cours...';
    });
    try {
      final Position p = await _location.getCurrentLocation();
      final String repere =
          '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
      if (!mounted) return;
      setState(() {
        _lat = p.latitude;
        _lng = p.longitude;
        _repere = repere;
        _gpsFiable = true;
        _localisationEnCours = false;
      });
    } on LocationPermissionException catch (e) {
      if (!mounted) return;
      setState(() {
        _localisationEnCours = false;
        _gpsFiable = false;
        _repere = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _localisationEnCours = false;
        _gpsFiable = false;
        _repere = 'GPS indisponible — position par défaut : Cotonou.';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Étape 3 : pannes compatibles avec le véhicule choisi
  // ---------------------------------------------------------------------------
  Future<void> _chargerPannes() async {
    final v = _vehicule;
    if (v == null) return;
    if (!mounted) return;
    setState(() {
      _pannesEnCours = true;
      _pannesErreur = null;
      _panne = null;
    });
    try {
      final liste = await _sos.pannesPour(v);
      if (!mounted) return;
      setState(() {
        _pannes = liste;
        _pannesEnCours = false;
      });
    } on SosException catch (e) {
      if (!mounted) return;
      setState(() {
        _pannesErreur = e.message;
        _pannesEnCours = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pannesErreur = 'Impossible de charger la liste des pannes.';
        _pannesEnCours = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Étape 4 : prestataires compatibles + devis transparent
  // ---------------------------------------------------------------------------
  Future<void> _chargerResultats() async {
    final v = _vehicule;
    final p = _panne;
    if (v == null || p == null) return;
    if (!mounted) return;
    setState(() {
      _rechercheEnCours = true;
      _resultatsErreur = null;
      _contactsSecteur = const [];
      _resultats = const [];
    });
    try {
      final liste = await _sos.rechercherPrestataires(
        vehicule: v,
        panne: p,
        latitude: _lat,
        longitude: _lng,
      );
      if (!mounted) return;
      if (liste.isEmpty) {
        final proches = await _proximite.chercher(
          position: LatLng(_lat, _lng),
          rayonKm: 25,
          limite: 6,
        );
        if (!mounted) return;
        setState(() {
          _contactsSecteur = proches
              .map(
                (x) => SosPrestataire(
                  id: x.id,
                  nom: x.nom,
                  metier: x.metier,
                  telephone: x.telephone,
                  distanceKm: 0,
                  devis: const SosDevis(
                    mainOeuvreFcfa: 0,
                    pieceCode: null,
                    pieceLibelle: null,
                    piecePrixFcfa: 0,
                    pieceStock: 0,
                    deplacementFcfa: 0,
                    totalFcfa: 0,
                    tarifKmGaranti: 0,
                  ),
                  services: const [],
                  competences: const [],
                  habilitations: const [],
                ),
              )
              .toList();
          if (proches.isNotEmpty) {
            _resultatsErreur =
                'Aucun dépanneur SOS libre dans votre secteur pour cette panne. '
                '${proches.length} professionnel(s) couvrent le Grand Cotonou : '
                'appelez-les directement.';
          }
        });
      }
      if (!mounted) return;
      setState(() {
        _resultats = liste;
        _rechercheEnCours = false;
      });
    } on SosException catch (e) {
      if (!mounted) return;
      setState(() {
        _resultatsErreur = e.message;
        _rechercheEnCours = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resultatsErreur = 'Recherche impossible. Vérifiez votre réseau.';
        _rechercheEnCours = false;
      });
    }
  }

  Future<void> _commander(SosPrestataire pr) async {
    final v = _vehicule;
    final p = _panne;
    if (v == null || p == null) return;
    if (!mounted) return;
    setState(() => _commandeEnCours = pr.id);
    try {
      final id = await _sos.demanderIntervention(
        vehicule: v,
        panne: p,
        latitude: _lat,
        longitude: _lng,
        prestataireId: pr.id,
        niveau: _niveau,
        repereLocal: _repere,
      );
      if (!mounted) return;
      setState(() => _commandeEnCours = null);
      final reference = id.length >= 8 ? id.substring(0, 8) : id;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_rounded,
            color: AppTheme.successColor,
            size: 48,
          ),
          title: const Text('Demande envoyée'),
          content: Text(
            'Votre demande SOS #$reference a été transmise à '
            '${pr.nomAffiche}. Le devis affiché est garanti : toute '
            'modification devra être acceptée par vous.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } on SosException catch (e) {
      if (!mounted) return;
      setState(() => _commandeEnCours = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _commandeEnCours = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Commande impossible. Réessayez.'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Future<void> _appeler(String? telephone) async {
    if (telephone == null || telephone.trim().isEmpty) return;
    final uri = Uri(scheme: 'tel', path: telephone.trim());
    try {
      final lance = await canLaunchUrl(uri);
      if (lance) await launchUrl(uri);
    } catch (_) {
      // Un échec d'appel reste silencieux : l'utilisateur peut recomposer.
    }
  }

  void _retour() {
    setState(() {
      if (_etape == _Etape.vehicule) {
        _etape = _Etape.position;
      } else if (_etape == _Etape.panne) {
        _etape = _Etape.vehicule;
        _panne = null;
        _pannes = const [];
      } else if (_etape == _Etape.resultat) {
        _etape = _Etape.panne;
        _resultats = const [];
        _contactsSecteur = const [];
        _resultatsErreur = null;
      }
    });
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS Je suis en panne'),
        leading: _etape == _Etape.position
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _retour,
              ),
      ),
      body: Column(
        children: [
          _EnteteEtapes(etape: _etape),
          Divider(height: 1, color: scheme.outlineVariant),
          Expanded(
            child: switch (_etape) {
              _Etape.position => _etapePosition(),
              _Etape.vehicule => _etapeVehicule(),
              _Etape.panne => _etapePanne(),
              _Etape.resultat => _etapeResultat(),
            },
          ),
        ],
      ),
    );
  }

  Widget _etapePosition() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: _localisationEnCours
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _gpsFiable
                        ? Icons.my_location_rounded
                        : Icons.location_off_rounded,
                    color: _gpsFiable
                        ? AppTheme.successColor
                        : AppTheme.warningColor,
                  ),
            title: const Text('Votre position sur la route'),
            subtitle: Text(_repere),
            trailing: IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _capturerPosition,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Niveau de sécurité de la chaussée',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final n in SosNiveauSecurite.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RadioListTile<SosNiveauSecurite>(
              value: n,
              groupValue: _niveau,
              onChanged: (v) {
                if (v != null) setState(() => _niveau = v);
              },
              secondary: Icon(_iconeNiveau(n), color: _couleurNiveau(n)),
              title: Text(n.libelle),
              subtitle: Text(n.consigne),
            ),
          ),
        const SizedBox(height: 16),
        AppButton(
          label: 'Continuer : mon véhicule',
          icon: Icons.arrow_forward_rounded,
          onPressed: _localisationEnCours
              ? null
              : () {
                  setState(() => _etape = _Etape.vehicule);
                },
        ),
      ],
    );
  }

  Widget _etapeVehicule() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Quel véhicule rouliez-vous au moment de la panne ?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        for (final g in SosGroupe.values) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              g.libelle,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          for (final v in kSosVehicules.where((v) => v.groupe == g))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CarteChoix(
                selected: _vehicule?.code == v.code,
                icon: v.icone,
                titre: v.libelle,
                sousTitre: v.detail,
                onTap: () => setState(() => _vehicule = v),
              ),
            ),
        ],
        const SizedBox(height: 16),
        AppButton(
          label: 'Continuer : ma panne',
          icon: Icons.arrow_forward_rounded,
          onPressed: _vehicule == null
              ? null
              : () {
                  setState(() => _etape = _Etape.panne);
                  _chargerPannes();
                },
        ),
      ],
    );
  }

  Widget _etapePanne() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Quel est le type de panne ?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        if (_vehicule != null && !_pannesEnCours)
          Text(
            'Véhicule : ${_vehicule!.libelle} — '
            '${_pannes.length} panne(s) prise(s) en charge',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
        const SizedBox(height: 12),
        if (_pannesEnCours)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_pannesErreur != null)
          _BlocErreur(message: _pannesErreur!, onRetraiter: _chargerPannes)
        else
          for (final p in _pannes)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CarteChoix(
                selected: _panne?.code == p.code,
                icon: p.icone,
                titre: p.libelle,
                sousTitre: p.description,
                onTap: () => setState(() => _panne = p),
              ),
            ),
        const SizedBox(height: 16),
        AppButton(
          label: 'Trouver un dépanneur',
          icon: Icons.search_rounded,
          onPressed: _panne == null
              ? null
              : () {
                  setState(() => _etape = _Etape.resultat);
                  _chargerResultats();
                },
        ),
      ],
    );
  }

  Widget _etapeResultat() {
    if (_rechercheEnCours) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _chargerResultats,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_panne != null)
            _CarteResume(
              vehicule: _vehicule,
              panne: _panne,
              repere: _repere,
              niveau: _niveau,
            ),
          const SizedBox(height: 16),
          if (_resultats.isEmpty) ...[
            if (_resultatsErreur != null)
              _BlocErreur(
                message: _resultatsErreur!,
                onRetraiter: _chargerResultats,
              )
            else
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'Aucun prestataire compatible disponible pour le moment. '
                    'Réessayez dans quelques instants.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            if (_contactsSecteur.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Professionnels du secteur',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final c in _contactsSecteur)
                _LigneContact(
                  nom: c.nomAffiche,
                  metier: c.metier,
                  telephone: c.telephone,
                  onAppeler: () => _appeler(c.telephone),
                ),
            ],
          ] else ...[
            Text(
              '${_resultats.length} prestataire(s) compatible(s)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final pr in _resultats)
              _CartePrestataire(
                prestataire: pr,
                enCommande: _commandeEnCours == pr.id,
                onCommander: () => _commander(pr),
                onAppeler: () => _appeler(pr.telephone),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets privés de l'écran
// ---------------------------------------------------------------------------

IconData _iconeNiveau(SosNiveauSecurite n) => switch (n) {
  SosNiveauSecurite.ok => Icons.check_circle_outline_rounded,
  SosNiveauSecurite.attention => Icons.warning_amber_rounded,
  SosNiveauSecurite.danger => Icons.dangerous_rounded,
};

Color _couleurNiveau(SosNiveauSecurite n) => switch (n) {
  SosNiveauSecurite.ok => AppTheme.successColor,
  SosNiveauSecurite.attention => AppTheme.warningColor,
  SosNiveauSecurite.danger => AppTheme.errorColor,
};

String _fcfa(int montant) {
  final s = montant.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    b.write(s[i]);
    final reste = s.length - 1 - i;
    if (reste > 0 && reste % 3 == 0) b.write(' ');
  }
  return '${b.toString()} FCFA';
}

class _EnteteEtapes extends StatelessWidget {
  const _EnteteEtapes({required this.etape});

  final _Etape etape;

  @override
  Widget build(BuildContext context) {
    const titres = ['Position', 'Véhicule', 'Panne', 'Dépanneur'];
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            for (var i = 0; i < titres.length; i++) ...[
              Expanded(
                child: Column(
                  children: [
                    Icon(
                      i <= etape.index
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: i <= etape.index
                          ? AppTheme.successColor
                          : scheme.outline,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      titres[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CarteChoix extends StatelessWidget {
  const _CarteChoix({
    required this.selected,
    required this.icon,
    required this.titre,
    required this.sousTitre,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: selected ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: selected ? scheme.primary : scheme.outline),
        title: Text(titre),
        subtitle: Text(sousTitre, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: Icon(
          selected
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          color: selected ? scheme.primary : scheme.outline,
        ),
      ),
    );
  }
}

class _BlocErreur extends StatelessWidget {
  const _BlocErreur({required this.message, required this.onRetraiter});

  final String message;
  final VoidCallback onRetraiter;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.errorColor.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, color: AppTheme.errorColor),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetraiter,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarteResume extends StatelessWidget {
  const _CarteResume({
    required this.vehicule,
    required this.panne,
    required this.repere,
    required this.niveau,
  });

  final SosVehicule? vehicule;
  final SosPanne? panne;
  final String repere;
  final SosNiveauSecurite niveau;

  @override
  Widget build(BuildContext context) {
    final diagnostic = diagnosticPourPanne(panne?.code);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Récapitulatif',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(vehicule?.icone ?? Icons.help_outline_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(vehicule?.libelle ?? '—')),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(panne?.icone ?? Icons.help_outline_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(panne?.libelle ?? '—')),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(repere)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _iconeNiveau(niveau),
                  size: 20,
                  color: _couleurNiveau(niveau),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(niveau.libelle)),
              ],
            ),
            if (diagnostic case final d?) ...[
              const Divider(height: 24),
              Text(
                'Diagnostic pro',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.engineering_rounded, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Métier requis : ${d.metier}'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.miscellaneous_services_rounded, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Service : ${d.service}')),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.tips_and_updates_rounded, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      d.conseil,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CartePrestataire extends StatelessWidget {
  const _CartePrestataire({
    required this.prestataire,
    required this.enCommande,
    required this.onCommander,
    required this.onAppeler,
  });

  final SosPrestataire prestataire;
  final bool enCommande;
  final VoidCallback onCommander;
  final VoidCallback onAppeler;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = prestataire.devis;
    final lignes = <(String, int)>[
      ("Main-d'œuvre / intervention", d.mainOeuvreFcfa),
      if (d.pieceCode != null)
        ('Pièce : ${d.pieceLibelle ?? d.pieceCode}', d.piecePrixFcfa),
      ('Déplacement', d.deplacementFcfa),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    prestataire.nomAffiche,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${prestataire.distanceKm.toStringAsFixed(1)} km',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: scheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (prestataire.metier.isNotEmpty) prestataire.metier,
                if (prestataire.noteMoyenne > 0)
                  '${prestataire.noteMoyenne.toStringAsFixed(1)} ★',
                'Tarif au km : ${_fcfa(d.tarifKmGaranti)}',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.outline),
            ),
            if (prestataire.services.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in prestataire.services)
                    Chip(
                      label: Text(
                        sosServiceLibelle(s),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Devis transparent (garanti)',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            for (final (libelle, montant) in lignes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        libelle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      _fcfa(montant),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total garanti',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  _fcfa(d.totalFcfa),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.successColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (prestataire.telephone != null &&
                    prestataire.telephone!.trim().isNotEmpty)
                  IconButton.outlined(
                    onPressed: onAppeler,
                    icon: const Icon(Icons.call_rounded),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton(
                    label: 'Commander cette intervention',
                    icon: Icons.sos_rounded,
                    onPressed: enCommande ? null : onCommander,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LigneContact extends StatelessWidget {
  const _LigneContact({
    required this.nom,
    required this.metier,
    required this.telephone,
    required this.onAppeler,
  });

  final String nom;
  final String metier;
  final String? telephone;
  final VoidCallback onAppeler;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.person_pin_circle_rounded),
        title: Text(nom),
        subtitle: Text(
          metier,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.outline),
        ),
        trailing: IconButton.filledTonal(
          onPressed: onAppeler,
          icon: const Icon(Icons.call_rounded),
        ),
      ),
    );
  }
}
