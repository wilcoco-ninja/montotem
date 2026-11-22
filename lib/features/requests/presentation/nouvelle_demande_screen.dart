
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/auth/data/location_service.dart';
import 'package:montotem/features/provider/data/provider_catalog_service.dart';
import 'package:montotem/features/tracking/domain/prestataire_model.dart'
    hide iconePourMetier;
import 'package:montotem/features/requests/data/mission_service.dart';

/// Commande à prix fixes : le client coche les prestations du catalogue du
/// dépanneur, voit le total (prestations + déplacement) et envoie.
/// Aucune négociation : les prix sont ceux du catalogue, figés par le serveur.
class NouvelleDemandeScreen extends StatefulWidget {
  const NouvelleDemandeScreen({super.key, required this.prestataire});
  final Prestataire prestataire;

  @override
  State<NouvelleDemandeScreen> createState() => _NouvelleDemandeScreenState();
}

class _NouvelleDemandeScreenState extends State<NouvelleDemandeScreen> {
  // Les routes sont ~25 % plus longues que la ligne droite (comme le serveur).
  static const double _facteurRoute = 1.25;
  static const int _maxPrestations = 8;

  final MissionService _service = MissionService();
  final ProviderCatalogService _catalogue = ProviderCatalogService();
  final LocationService _location = LocationService();
  final TextEditingController _description = TextEditingController();

  ProviderPublicCatalog? _fiche;
  bool _chargement = true;
  bool _envoi = false;
  String? _vehicule;
  final Set<String> _choix = {}; // ids de prestations
  double? _distanceKm; // ligne droite client -> prestataire

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), duration: const Duration(seconds: 5)));

  Future<void> _charger() async {
    setState(() => _chargement = true);
    final fiche = await _catalogue.obtenirFiche(widget.prestataire.id);
    if (!mounted) return;
    setState(() {
      _fiche = fiche;
      _vehicule = (fiche != null && fiche.vehicleTypes.isNotEmpty)
          ? fiche.vehicleTypes.first
          : null;
      _chargement = false;
    });
    // Position facultative : sert seulement à estimer le déplacement.
    try {
      final pos = await _location.getCurrentLocation();
      final p = widget.prestataire;
      final m = _location.distanceBetween(
          pos.latitude, pos.longitude, p.latitude, p.longitude);
      if (mounted) setState(() => _distanceKm = m / 1000);
    } catch (_) {}
  }

  List<ServiceTarif> get _services {
    final f = _fiche;
    final v = _vehicule;
    if (f == null || v == null) return const [];
    return f.servicesPour(v);
  }

  List<ServiceTarif> get _selection =>
      _services.where((s) => s.id != null && _choix.contains(s.id)).toList();

  int get _totalPrestations =>
      _selection.fold<int>(0, (t, s) => t + s.prixFcfa);

  int? get _fraisDeplacement {
    final f = _fiche;
    final km = _distanceKm;
    if (f == null || km == null) return null;
    return TravelFee.estimate(
      km: km * _facteurRoute,
      tarifKmFcfa: f.tarifKmFcfa,
      minimumFcfa: f.fraisMinFcfa,
    );
  }

  bool get _horsRayon {
    final f = _fiche;
    final km = _distanceKm;
    return f != null &&
        km != null &&
        f.rayonMaxKm > 0 &&
        km * _facteurRoute > f.rayonMaxKm;
  }

  void _basculer(ServiceTarif s) {
    final id = s.id;
    if (id == null) return;
    setState(() {
      if (_choix.contains(id)) {
        _choix.remove(id);
      } else if (_choix.length >= _maxPrestations) {
        _msg('Maximum $_maxPrestations prestations par demande.');
      } else {
        _choix.add(id);
      }
    });
  }

  Future<void> _envoyer() async {
    FocusScope.of(context).unfocus();
    final v = _vehicule;
    if (v == null || _choix.isEmpty) {
      _msg('Choisissez au moins une prestation.');
      return;
    }
    if (_horsRayon) {
      _msg('Vous êtes hors du rayon d\'intervention de ce dépanneur.');
      return;
    }
    setState(() => _envoi = true);
    try {
      final pos = await _location.getCurrentLocation();
      final texte = _description.text.trim();
      final id = await _service.creer(
        providerId: widget.prestataire.id,
        vehicle: v,
        prestationIds: _choix.toList(),
        description: texte.isEmpty ? null : texte,
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (!mounted) return;
      // L'écran de suivi affiche aussitôt « Payer le déplacement ».
      context.pushReplacement('/mes-demandes/$id');
    } on MissionException catch (e) {
      if (mounted) _msg(e.message);
    } on LocationPermissionException catch (e) {
      if (mounted) _msg(e.message);
    } catch (_) {
      if (mounted) _msg('Impossible de vous localiser. Activez le GPS.');
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.prestataire;
    final scheme = Theme.of(context).colorScheme;
    final fiche = _fiche;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Commander une intervention')),
        body: SafeArea(
          child: ContentWidth(
            maxWidth: 720,
            child: _chargement
                ? const Center(child: CircularProgressIndicator())
                : fiche == null
                    ? Center(
                        child: SingleChildScrollView(
                          child: ErrorState(
                            message:
                                'Impossible de charger les tarifs de ce dépanneur.',
                            onRetry: _charger,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          _entete(p, scheme),
                          if (!fiche.accepteMobileMoney)
                            _alerte(
                              'Ce dépanneur n\'a pas encore configuré son '
                              'paiement Mobile Money : commande impossible.',
                            ),
                          if (fiche.services.isEmpty)
                            _alerte(
                              'Ce dépanneur n\'a publié aucune prestation '
                              'avec un prix. Choisissez-en un autre.',
                            )
                          else ...[
                            if (fiche.vehicleTypes.length > 1) ...[
                              const SectionTitle('Quel véhicule ?'),
                              _choixVehicule(fiche, scheme),
                            ],
                            const SectionTitle('Prestations et prix fixes'),
                            ..._services.map(_ligne),
                            const SectionTitle('Précisions (facultatif)'),
                            AppTextField(
                              label: 'Précisions pour le dépanneur',
                              icon: Icons.notes_outlined,
                              controller: _description,
                              maxLines: 3,
                              maxLength: 300,
                            ),
                            const SizedBox(height: 8),
                            _recapitulatif(fiche, scheme),
                            const SizedBox(height: 16),
                            AppButton(
                              label: 'Commander et payer le déplacement',
                              icon: Icons.lock_outline_rounded,
                              loading: _envoi,
                              onPressed: (_choix.isEmpty ||
                                      !fiche.accepteMobileMoney ||
                                      _horsRayon)
                                  ? null
                                  : _envoyer,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Prix fixes, sans négociation. Le déplacement se '
                              'règle en Mobile Money dès l\'envoi ; la réparation '
                              'se règle à la fin du travail. Votre position GPS '
                              'n\'est partagée qu\'avec ce prestataire.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.75)),
                            ),
                          ],
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  Widget _entete(Prestataire p, ColorScheme scheme) => SoftCard(
        child: Row(
          children: [
            Icon(iconePourMetier(p.metier), color: scheme.secondary, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.nomAffiche,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(
                      '${p.metier} • ${p.noteMoyenne.toStringAsFixed(1)} ★',
                      style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
            Icon(
              p.verifie ? Icons.verified_rounded : Icons.error_outline_rounded,
              color: p.verifie ? AppTheme.successColor : AppTheme.warningColor,
              size: 28,
            ),
          ],
        ),
      );

  Widget _alerte(String texte) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SoftCard(
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppTheme.warningColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(texte,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );

  Widget _choixVehicule(ProviderPublicCatalog fiche, ColorScheme scheme) => Row(
        children: [
          for (final v in fiche.vehicleTypes)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() {
                    _vehicule = v;
                    _choix.clear(); // les prestations dépendent du véhicule
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: _vehicule == v ? scheme.primary : null,
                      border: Border.all(
                          color: _vehicule == v
                              ? scheme.primary
                              : scheme.onSurface.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      children: [
                        Icon(kVehicules[v]?.icon ?? Icons.build_rounded,
                            size: 30,
                            color: _vehicule == v ? scheme.onPrimary : null),
                        const SizedBox(height: 4),
                        Text(kVehicules[v]?.label ?? v,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color:
                                    _vehicule == v ? scheme.onPrimary : null)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );

  Widget _ligne(ServiceTarif s) {
    final scheme = Theme.of(context).colorScheme;
    final on = s.id != null && _choix.contains(s.id);
    final radius = BorderRadius.circular(AppTheme.radiusMd);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        selected: on,
        label: '${s.nom}, ${TravelFee.fcfa(s.prixFcfa)}',
        excludeSemantics: true,
        child: Material(
          color: on ? scheme.primary.withValues(alpha: 0.09) : scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color:
                  on ? scheme.primary : scheme.onSurface.withValues(alpha: 0.2),
              width: on ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: () => _basculer(s),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      on
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: on ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(s.nom,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Text(TravelFee.fcfa(s.prixFcfa),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _recapitulatif(ProviderPublicCatalog f, ColorScheme scheme) {
    final frais = _fraisDeplacement;
    final total = _totalPrestations + (frais ?? 0);
    Widget ligne(String l, String v, {bool fort = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                  child: Text(l,
                      style: TextStyle(
                          fontSize: fort ? 17 : 15.5,
                          fontWeight:
                              fort ? FontWeight.w800 : FontWeight.w500))),
              Text(v,
                  style: TextStyle(
                      fontSize: fort ? 19 : 16,
                      fontWeight: FontWeight.w800,
                      color: fort ? AppTheme.primaryColor : null)),
            ],
          ),
        );

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ligne('Prestations (${_selection.length})',
              TravelFee.fcfa(_totalPrestations)),
          ligne(
            'Déplacement',
            frais == null ? 'calculé à l\'envoi' : TravelFee.fcfa(frais),
          ),
          Text(
            '${TravelFee.fcfa(f.tarifKmFcfa)}/km · minimum '
            '${TravelFee.fcfa(f.fraisMinFcfa)}',
            style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurface.withValues(alpha: 0.65)),
          ),
          if (_horsRayon)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Vous êtes hors du rayon d\'intervention de ce dépanneur.',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.errorColor),
              ),
            ),
          Divider(height: 22, color: scheme.onSurface.withValues(alpha: 0.12)),
          ligne('Total', TravelFee.fcfa(total), fort: true),
        ],
      ),
    );
  }
}
