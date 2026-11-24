import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/features/auth/data/auth_service.dart' show AuthService;
import 'package:montotem/features/requests/data/mission_service.dart';
import 'package:montotem/features/requests/domain/mission_payment_model.dart';

Future<void> showProviderMomoSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: const _MomoSheet(),
    ),
  );
}

class _MomoSheet extends StatefulWidget {
  const _MomoSheet();

  @override
  State<_MomoSheet> createState() => _MomoSheetState();
}

class _MomoSheetState extends State<_MomoSheet> {
  final MissionService _service = MissionService();
  final _formKey = GlobalKey<FormState>();
  final _numero = TextEditingController();
  final _titulaire = TextEditingController();

  PayMethod? _operateur;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _numero.dispose();
    _titulaire.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final acc = await _service.monMomo();
      if (!mounted) return;
      if (acc != null) {
        setState(() {
          _operateur = acc.methode;
          _numero.text = acc.numero;
          _titulaire.text = acc.titulaire ?? '';
        });
      }
    } on MissionException {
      // Formulaire vide : l'utilisateur peut quand mÃƒÂªme saisir.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  String? _validerNumero(String? v) {
    if (v == null || v.trim().isEmpty) return 'Champ obligatoire';
    if (!AuthService.isValidPhone(AuthService.normalizePhone(v))) {
      return 'NumÃƒÂ©ro invalide. Exemple : 01 97 00 00 00';
    }
    return null;
  }

  Future<void> _enregistrer() async {
    FocusScope.of(context).unfocus();
    final op = _operateur;
    if (op == null) {
      _msg('Choisissez votre opÃƒÂ©rateur.');
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await _service.definirMomo(
        operateur: op.code,
        numero: AuthService.normalizePhone(_numero.text),
        titulaire: _titulaire.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      _msg(
        'NumÃƒÂ©ro enregistrÃƒÂ©. Vos clients peuvent vous payer par Mobile Money.',
      );
    } on MissionException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _msg(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.85);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Recevoir mes paiements',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ce numÃƒÂ©ro est montrÃƒÂ© au client uniquement quand vous '
                    'acceptez sa demande.',
                    style: TextStyle(fontSize: 16, height: 1.4, color: muted),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Votre opÃƒÂ©rateur',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: PayMethod.values
                        .where((m) => m.mobileMoney)
                        .map(
                          (m) => ChoiceChip(
                            label: Text(
                              m.libelle,
                              style: const TextStyle(fontSize: 16),
                            ),
                            selected: _operateur == m,
                            onSelected: _saving
                                ? null
                                : (_) => setState(() => _operateur = m),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'NumÃƒÂ©ro Mobile Money',
                    hint: '01 97 00 00 00',
                    icon: Icons.phone_outlined,
                    controller: _numero,
                    enabled: !_saving,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                    ],
                    validator: _validerNumero,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'Nom sur le compte (facultatif)',
                    icon: Icons.person_outline,
                    controller: _titulaire,
                    enabled: !_saving,
                    maxLength: 80,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 18),
                  AppButton(
                    label: 'Enregistrer',
                    icon: Icons.check_rounded,
                    loading: _saving,
                    onPressed: _enregistrer,
                  ),
                ],
              ),
            ),
    );
  }
}
