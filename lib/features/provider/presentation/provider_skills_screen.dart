import 'package:flutter/material.dart';

import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/features/provider/data/provider_skills_service.dart';

/// Compétences libres : le prestataire écrit lui-même ses spécialités,
/// visibles par les clients sur sa fiche.
class ProviderSkillsScreen extends StatefulWidget {
  const ProviderSkillsScreen({super.key});

  @override
  State<ProviderSkillsScreen> createState() => _ProviderSkillsScreenState();
}

class _ProviderSkillsScreenState extends State<ProviderSkillsScreen> {
  static const _suggestions = [
    'Climatisation auto',
    'Diagnostic électronique',
    'Freinage',
    'Changement d\'huile',
    'Soudure',
    'Carrosserie',
    'Pneus camion',
    'Dépannage poids lourd',
    'Remorquage moto',
    'Démarrage / alternateur',
  ];

  final _service = ProviderSkillsService();
  final _controller = TextEditingController();

  List<ProviderSkill> _skills = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _charger() async {
    try {
      final data = await _service.lister();
      if (!mounted) return;
      setState(() => _skills = data);
    } on SkillException catch (e) {
      if (mounted) _msg(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ajouter(String label) async {
    final texte = label.trim();
    if (texte.length < 2 || _busy) {
      if (texte.isNotEmpty) _msg('Écrivez au moins 2 lettres.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _service.ajouter(texte);
      _controller.clear();
      await _charger();
    } on SkillException catch (e) {
      if (mounted) _msg(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _supprimer(ProviderSkill s) async {
    try {
      await _service.supprimer(s.id);
      await _charger();
    } on SkillException catch (e) {
      if (mounted) _msg(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8);
    final existants = _skills.map((s) => s.label.toLowerCase()).toSet();

    return Scaffold(
      appBar: AppBar(title: const Text('Mes compétences')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ContentWidth(
              maxWidth: 640,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  Text(
                    'Écrivez vos spécialités. Les clients les voient sur votre '
                    'fiche et vous trouvent plus facilement.',
                    style: TextStyle(fontSize: 16, height: 1.45, color: muted),
                  ),
                  const SizedBox(height: 18),
                  AppTextField(
                    label: 'Ajouter une compétence',
                    hint: 'Ex. : Climatisation auto',
                    icon: Icons.edit_outlined,
                    controller: _controller,
                    enabled: !_busy,
                    maxLength: 60,
                    textInputAction: TextInputAction.done,
                    onSubmitted: _ajouter,
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    label: 'Ajouter',
                    icon: Icons.add_rounded,
                    loading: _busy,
                    onPressed: () => _ajouter(_controller.text),
                  ),
                  const SectionTitle('Suggestions'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _suggestions
                        .where((s) => !existants.contains(s.toLowerCase()))
                        .map((s) => ActionChip(
                              avatar: const Icon(Icons.add, size: 18),
                              label: Text(s),
                              onPressed: _busy ? null : () => _ajouter(s),
                            ))
                        .toList(),
                  ),
                  SectionTitle('Mes compétences (${_skills.length})'),
                  if (_skills.isEmpty)
                    Text('Aucune compétence ajoutée pour le moment.',
                        style: TextStyle(fontSize: 16, color: muted))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _skills
                          .map((s) => InputChip(
                                label: Text(s.label),
                                onDeleted: () => _supprimer(s),
                                deleteButtonTooltipMessage: 'Supprimer',
                              ))
                          .toList(),
                    ),
                ],
              ),
            ),
    );
  }
}
