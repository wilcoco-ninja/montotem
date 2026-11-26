import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/app_ui.dart';

/// Poste de travail admin « Tarifs & prix ».
///
/// Tous les tarifs kilométriques de l'application sont modifiables ici :
///   - Courses : base + FCFA/km pour Zémidjan, Cloboto, Kloboto ;
///   - Dépannage : déplacement express (véhicule de travail) et remorquage.
///
/// Les valeurs vivent dans `app_config` ; le serveur les utilise pour
/// recalculer le prix minimum des courses (create_ride) et les devis SOS
/// (sos_match_providers). L'écriture est réservée au super_admin (RLS).
class AdminTariffsScreen extends StatefulWidget {
  const AdminTariffsScreen({super.key});

  @override
  State<AdminTariffsScreen> createState() => _AdminTariffsScreenState();
}

class _TarifField {
  _TarifField(this.key, this.label, this.helper, this.icon);

  final String key;
  final String label;
  final String helper;
  final IconData icon;
  final TextEditingController controller = TextEditingController();
}

class _AdminTariffsScreenState extends State<AdminTariffsScreen> {
  SupabaseClient get _sb => Supabase.instance.client;

  late final List<_TarifField> _champs = [
    // Courses — transport.
    _TarifField(
      'ride_zemidjan_base_fcfa',
      'Zémidjan — départ (FCFA)',
      'Prix de départ de la course',
      Icons.two_wheeler_rounded,
    ),
    _TarifField(
      'ride_zemidjan_per_km_fcfa',
      'Zémidjan — par km (FCFA/km)',
      'Officiel : 150 FCFA/km',
      Icons.speed_rounded,
    ),
    _TarifField(
      'ride_cloboto_base_fcfa',
      'Cloboto — départ (FCFA)',
      'Prix de départ de la course',
      Icons.electric_rickshaw_rounded,
    ),
    _TarifField(
      'ride_cloboto_per_km_fcfa',
      'Cloboto — par km (FCFA/km)',
      'Officiel : 200 FCFA/km',
      Icons.speed_rounded,
    ),
    _TarifField(
      'ride_kloboto_base_fcfa',
      'Kloboto — départ (FCFA)',
      'Prix de départ de la course',
      Icons.local_shipping_rounded,
    ),
    _TarifField(
      'ride_kloboto_per_km_fcfa',
      'Kloboto — par km (FCFA/km)',
      'Officiel : 300 FCFA/km',
      Icons.speed_rounded,
    ),
    // Déplacement des prestataires (selon le type d'atelier).
    _TarifField(
      'deplacement_atelier_fcfa_km',
      'Atelier / technicien ambulant — par km (FCFA/km)',
      'Mécanicien, vulcanisateur, électricien avec véhicule de travail : '
          '100 FCFA/km',
      Icons.build_circle_rounded,
    ),
    _TarifField(
      'deplacement_garage_fcfa_km',
      'Service garage — par km (FCFA/km)',
      'Déplacement du service garage : 150 FCFA/km',
      Icons.garage_outlined,
    ),
    _TarifField(
      'deplacement_station_fcfa_km',
      'Station essence / carburant — par km (FCFA/km)',
      'Livraison de carburant : 100 FCFA/km',
      Icons.local_gas_station_outlined,
    ),
    // SOS express & remorquage.
    _TarifField(
      'sos_deplacement_express_fcfa_km',
      'Déplacement express SOS — par km (FCFA/km)',
      'Prestataire express SOS : 100 FCFA/km',
      Icons.sos_rounded,
    ),
    _TarifField(
      'sos_remorquage_fcfa_km',
      'Remorquage — par km (FCFA/km)',
      'Dépanneuse pour voitures et véhicules bloqués : 400 FCFA/km',
      Icons.local_shipping_rounded,
    ),
  ];

  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final c in _champs) {
      c.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final rows = await _sb
          .from('app_config')
          .select('key, value_int')
          .inFilter('key', _champs.map((c) => c.key).toList(growable: false));
      final valeurs = <String, int>{};
      for (final row in (rows as List)) {
        final k = '${row['key']}';
        final v = (row['value_int'] as num?)?.toInt();
        if (v != null) valeurs[k] = v;
      }
      if (!mounted) return;
      setState(() {
        for (final c in _champs) {
          final v = valeurs[c.key];
          c.controller.text = v == null ? '' : '$v';
        }
        _chargement = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger les tarifs : $e';
        _chargement = false;
      });
    }
  }

  Future<void> _enregistrer() async {
    setState(() {
      _enregistrement = true;
      _erreur = null;
    });
    try {
      final lignes = <Map<String, Object?>>[];
      for (final c in _champs) {
        final v = int.tryParse(c.controller.text.trim());
        if (v == null || v < 0 || v > 1000000) continue;
        lignes.add({
          'key': c.key,
          'value_int': v,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
      if (lignes.isNotEmpty) {
        await _sb.from('app_config').upsert(lignes, onConflict: 'key');
      }
      if (!mounted) return;
      setState(() => _enregistrement = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tarifs enregistrés. Appliqués immédiatement.'),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message.contains('row-level security') ||
                    e.message.contains('permission')
                ? "Enregistrement refusé : seul le super_admin peut modifier "
                      "les tarifs."
                : 'Erreur : ${e.message}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _enregistrement = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Erreur : $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tarifs & prix')),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(16),
              child: ContentWidth(
                maxWidth: 640,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_erreur != null) ...[
                      Text(
                        _erreur!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SectionTitle('Courses (transport)'),
                    for (final c in _champs.sublist(0, 6))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppTextField(
                          label: c.label,
                          helper: c.helper,
                          icon: c.icon,
                          controller: c.controller,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    const SectionTitle('Déplacement des prestataires'),
                    Text(
                      'Le client paie toujours le déplacement du '
                      'prestataire. Le tarif au kilomètre dépend du type '
                      'd\'atelier.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final c in _champs.sublist(6, 9))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppTextField(
                          label: c.label,
                          helper: c.helper,
                          icon: c.icon,
                          controller: c.controller,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    const SectionTitle('SOS express & remorquage'),
                    for (final c in _champs.sublist(9))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: AppTextField(
                          label: c.label,
                          helper: c.helper,
                          icon: c.icon,
                          controller: c.controller,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Le serveur recalcule le prix minimum de chaque course '
                      '(départ + FCFA/km × distance) et les devis de '
                      'dépannage avec ces valeurs. Les changements sont '
                      'immédiats, sans recompiler l\'application.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AppButton(
                      label: 'Enregistrer les tarifs',
                      icon: Icons.save_outlined,
                      loading: _enregistrement,
                      onPressed: _enregistrer,
                    ),
                    const SizedBox(height: 12),
                    AppButton(
                      label: 'Recharger',
                      icon: Icons.refresh_rounded,
                      variant: AppButtonVariant.text,
                      onPressed: _charger,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
