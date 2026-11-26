import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/provider/data/provider_catalog_service.dart';
import 'package:montotem/features/tracking/domain/prestataire_model.dart';
import 'package:montotem/features/map/presentation/widgets/auth_gate_sheet.dart';

const _libellesVehicules = {
  'moto': 'Moto',
  'voiture': 'Auto',
  'camion': 'Camion',
};

/// Fiche détail d'un prestataire (visiteurs inclus) : services, grille
/// tarifaire, frais de déplacement estimés, itinéraire. Contacter / Appeler /
/// Prendre RDV passent par [requireAuth].
class ProviderDetailSheet extends StatefulWidget {
  const ProviderDetailSheet({
    super.key,
    required this.prestataire,
    required this.distanceKm,
    required this.onItineraire,
  });

  final Prestataire prestataire;

  /// Distance à vol d'oiseau entre le client et le prestataire.
  final double distanceKm;
  final VoidCallback onItineraire;

  @override
  State<ProviderDetailSheet> createState() => _ProviderDetailSheetState();
}

class _ProviderDetailSheetState extends State<ProviderDetailSheet> {
  // Les routes sont ~25 % plus longues que la ligne droite.
  static const double _facteurRoute = 1.25;

  final _service = ProviderCatalogService();
  late Future<ProviderPublicCatalog?> _fiche;

  Prestataire get _p => widget.prestataire;

  @override
  void initState() {
    super.initState();
    _fiche = _service.obtenirFiche(_p.id);
  }

  void _recharger() => setState(() => _fiche = _service.obtenirFiche(_p.id));

  Future<void> _appeler() async {
    final tel = _p.telephone?.replaceAll(RegExp(r'\s+'), '');
    if (tel == null || tel.isEmpty) return;
    try {
      if (await launchUrl(Uri(scheme: 'tel', path: tel))) return;
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Impossible de lancer l\'appel.')),
    );
  }

  void _demander() {
    final router = GoRouter.of(context);
    Navigator.pop(context);
    router.push('/nouvelle-demande', extra: _p);
  }

  void _protege(GatedAction action, VoidCallback onAllowed) {
    requireAuth(
      context,
      action: action,
      prestataireNom: _p.nomAffiche,
      onAllowed: onAllowed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final hauteurMax = MediaQuery.of(context).size.height * 0.85;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: hauteurMax),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _p.nomAffiche,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Icon(
                    _p.verifie
                        ? Icons.verified_rounded
                        : Icons.error_outline_rounded,
                    color: _p.verifie ? scheme.secondary : scheme.tertiary,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _p.metier,
                style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(
                    label: _p.noteMoyenne.toStringAsFixed(1),
                    color: Colors.amber.shade800,
                    icon: Icons.star_rounded,
                  ),
                  StatusPill(
                    label: _p.disponible ? 'Disponible' : 'Indisponible',
                    color: _p.disponible ? scheme.secondary : Colors.grey,
                  ),
                  StatusPill(
                    label: '≈ ${widget.distanceKm.toStringAsFixed(1)} km',
                    color: scheme.primary,
                    icon: Icons.near_me_rounded,
                  ),
                ],
              ),
              FutureBuilder<ProviderPublicCatalog?>(
                future: _fiche,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final fiche = snap.data;
                  if (fiche == null) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: SoftCard(
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_off_rounded),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Tarifs indisponibles pour le moment.',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            TextButton(
                              onPressed: _recharger,
                              child: const Text('Réessayer'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return _contenuFiche(fiche);
                },
              ),
              const SizedBox(height: 18),
              AppButton(
                label: 'Voir l\'itinéraire',
                icon: Icons.directions_outlined,
                onPressed: () {
                  Navigator.pop(context);
                  widget.onItineraire();
                },
              ),
              const SizedBox(height: 10),
              AppButton(
                label: 'Contacter',
                icon: Icons.chat_bubble_outline_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: () => _protege(GatedAction.contacter, _demander),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (_p.telephone != null && _p.telephone!.isNotEmpty) ...[
                    Expanded(
                      child: AppButton(
                        label: 'Appeler',
                        icon: Icons.call_outlined,
                        variant: AppButtonVariant.secondary,
                        onPressed: () =>
                            _protege(GatedAction.appeler, _appeler),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: AppButton(
                      label: 'Prendre RDV',
                      icon: Icons.event_available_outlined,
                      variant: AppButtonVariant.secondary,
                      onPressed: () =>
                          _protege(GatedAction.rendezVous, _demander),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contenuFiche(ProviderPublicCatalog f) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final aFrais = f.tarifKmEffectif > 0 || f.fraisMinFcfa > 0;
    final kmRoute = widget.distanceKm * _facteurRoute;
    final frais = TravelFee.estimate(
      km: kmRoute,
      tarifKmFcfa: f.tarifKmEffectif,
      minimumFcfa: f.fraisMinFcfa,
    );
    final horsRayon = f.rayonMaxKm > 0 && kmRoute > f.rayonMaxKm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (f.vehicleTypes.isNotEmpty) ...[
          const SectionTitle('Véhicules pris en charge'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: f.vehicleTypes
                .map(
                  (v) => Chip(
                    label: Text(_libellesVehicules[v] ?? v),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        ],
        if (aFrais) ...[
          const SectionTitle('Déplacement'),
          SoftCard(
            child: Row(
              children: [
                Icon(Icons.local_shipping_outlined, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Environ ${TravelFee.fcfa(frais)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${TravelFee.fcfa(f.tarifKmEffectif)}/km · minimum '
                        '${TravelFee.fcfa(f.fraisMinFcfa)} · estimation pour '
                        '${kmRoute.toStringAsFixed(1)} km',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      if (horsRayon)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Au-delà de son rayon habituel (${f.rayonMaxKm} km).',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.tertiary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SectionTitle('Prestations et tarifs'),
        if (f.services.isEmpty)
          Text(
            'Ce prestataire n\'a pas encore publié ses tarifs.',
            style: TextStyle(color: onSurface.withValues(alpha: 0.65)),
          )
        else
          SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < f.services.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _ligneService(f.services[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _ligneService(ServiceTarif s) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.nom,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _libellesVehicules[s.categorieVehicule] ??
                      s.categorieVehicule,
                  style: TextStyle(
                    fontSize: 12,
                    color: onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          Text(
            s.prixFcfa <= 0 ? 'Sur devis' : TravelFee.fcfa(s.prixFcfa),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: s.prixFcfa <= 0 ? onSurface.withValues(alpha: 0.65) : null,
            ),
          ),
        ],
      ),
    );
  }
}
