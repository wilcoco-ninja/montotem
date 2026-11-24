import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/auth/data/quick_auth_service.dart'
    show QuickAuthException;
import 'package:montotem/features/provider/data/provider_catalog_service.dart';

/// « Mes prestations et prix » : le prestataire modifie son catalogue après
/// l'inscription. Un prix fixe par prestation, jamais de devis.
/// Route suggérée : /provider/catalog[cite: 27]
class ProviderCatalogScreen extends StatefulWidget {
  const ProviderCatalogScreen({super.key});

  @override
  State<ProviderCatalogScreen> createState() => _ProviderCatalogScreenState();
}

class _Ligne {
  _Ligne(this.nom, this.categorie, int? prix)
    : nomCtl = TextEditingController(text: nom),
      prixCtl = TextEditingController(text: prix?.toString() ?? '');
  String nom;
  String categorie;
  final TextEditingController nomCtl;
  final TextEditingController prixCtl;
  void dispose() {
    nomCtl.dispose();
    prixCtl.dispose();
  }
}

class _ProviderCatalogScreenState extends State<ProviderCatalogScreen> {
  final _service = ProviderCatalogService();
  final List<_Ligne> _lignes = [];
  ProviderPublicCatalog? _fiche;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final l in _lignes) {
      l.dispose();
    }
    super.dispose();
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _charger() async {
    setState(() => _loading = true);
    final fiche = await _service.obtenirFiche(_service.idConnecte ?? '');
    final services = fiche?.services ?? const <ServiceTarif>[];
    if (!mounted) return;
    for (final l in _lignes) {
      l.dispose();
    }
    _lignes
      ..clear()
      ..addAll(
        services.map((s) => _Ligne(s.nom, s.categorieVehicule, s.prixFcfa)),
      );
    setState(() {
      _fiche = fiche;
      _loading = false;
    });
  }

  Future<void> _enregistrer() async {
    final f = _fiche;
    if (f == null) return;
    final services = <ServiceTarif>[];
    for (final l in _lignes) {
      final nom = l.nomCtl.text.trim();
      final prix = int.tryParse(l.prixCtl.text.trim());
      if (nom.length < 2) {
        _msg('Chaque prestation doit avoir un nom.');
        return;
      }
      if (prix == null || prix <= 0) {
        _msg('« $nom » : indiquez un prix fixe supérieur à 0.');
        return;
      }
      services.add(
        ServiceTarif(nom: nom, categorieVehicule: l.categorie, prixFcfa: prix),
      );
    }
    if (services.isEmpty) {
      _msg('Gardez au moins une prestation.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.enregistrer(
        vehicleTypes: f.vehicleTypes,
        services: services,
        tarifKmFcfa: f.tarifKmFcfa,
        fraisMinFcfa: f.fraisMinFcfa,
        rayonKm: f.rayonMaxKm,
      );
      if (!mounted) return;
      _msg('Catalogue enregistré.');
      await _charger();
    } on QuickAuthException catch (e) {
      if (mounted) _msg(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _fiche;
    return Scaffold(
      appBar: AppBar(title: const Text('Mes prestations et prix')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : f == null
          ? Center(
              child: ErrorState(
                message: 'Catalogue indisponible.',
                onRetry: _charger,
              ),
            )
          : ContentWidth(
              maxWidth: 640,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Un prix fixe par prestation. Les clients commandent '
                      'exactement ce que vous affichez, sans négociation.\n\n'
                      'Déplacement : ${TravelFee.fcfa(f.tarifKmFcfa)}/km, '
                      'minimum ${TravelFee.fcfa(f.fraisMinFcfa)}.',
                      style: const TextStyle(fontSize: 14.5, height: 1.45),
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (var i = 0; i < _lignes.length; i++) _carte(i, f),
                  const SizedBox(height: 10),
                  AppButton(
                    label: 'Ajouter une prestation',
                    icon: Icons.add_rounded,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => setState(
                      () => _lignes.add(
                        _Ligne(
                          '',
                          f.vehicleTypes.isNotEmpty
                              ? f.vehicleTypes.first
                              : 'voiture',
                          null,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppButton(
                    label: 'Enregistrer les modifications',
                    icon: Icons.save_rounded,
                    loading: _saving,
                    onPressed: _enregistrer,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _carte(int i, ProviderPublicCatalog f) {
    final l = _lignes[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SoftCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: l.nomCtl,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Nom de la prestation',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Supprimer',
                  color: Theme.of(context).colorScheme.error,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => setState(() {
                    _lignes.removeAt(i).dispose();
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: f.vehicleTypes
                  .map(
                    (v) => ChoiceChip(
                      label: Text(kVehicules[v]?.label ?? v),
                      selected: l.categorie == v,
                      onSelected: (_) => setState(() => l.categorie = v),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: l.prixCtl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 7,
              decoration: const InputDecoration(
                labelText: 'Prix fixe',
                suffixText: 'FCFA',
                counterText: '',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
