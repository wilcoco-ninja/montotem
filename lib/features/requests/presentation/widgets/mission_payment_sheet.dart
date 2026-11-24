import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/features/auth/data/auth_service.dart' show AuthService;
import 'package:montotem/features/requests/data/mission_service.dart';
import 'package:montotem/features/requests/domain/mission_model.dart';
import 'package:montotem/features/requests/domain/mission_payment_model.dart';

/// Retourne true si le paiement a été déclaré.
Future<bool?> showMissionPaymentSheet(
  BuildContext context, {
  required Mission mission,
  required String kind,
  required int montant,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _PaymentSheet(mission: mission, kind: kind, montant: montant),
    ),
  );
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({
    required this.mission,
    required this.kind,
    required this.montant,
  });

  final Mission mission;
  final String kind;
  final int montant;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final MissionService _service = MissionService();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone;
  final TextEditingController _ref = TextEditingController();

  late final List<PayMethod> _methodes;
  late PayMethod _methode;
  bool _envoi = false;

  MomoAccount? get _momo => widget.mission.providerMomo;

  @override
  void initState() {
    super.initState();
    _methodes = [if (_momo != null) _momo!.methode, PayMethod.especes];
    _methode = _methodes.first;
    _phone = TextEditingController(text: widget.mission.clientPhone ?? '');
  }

  @override
  void dispose() {
    _phone.dispose();
    _ref.dispose();
    super.dispose();
  }

  Future<void> _copier(String texte) async {
    await Clipboard.setData(ClipboardData(text: texte));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Numéro copié.')));
  }

  String? _validerPhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Champ obligatoire';
    if (!AuthService.isValidPhone(AuthService.normalizePhone(v))) {
      return 'Numéro invalide. Exemple : 01 97 00 00 00';
    }
    return null;
  }

  String? _validerRef(String? v) => (v == null || v.trim().length < 4)
      ? 'Saisissez la référence reçue par SMS'
      : null;

  Future<void> _envoyer() async {
    FocusScope.of(context).unfocus();
    if (_methode.mobileMoney && !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _envoi = true);
    try {
      await _service.declarerPaiement(
        missionId: widget.mission.id,
        kind: widget.kind,
        methode: _methode,
        phone: _methode.mobileMoney
            ? AuthService.normalizePhone(_phone.text)
            : null,
        reference: _methode.mobileMoney ? _ref.text.trim() : null,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paiement déclaré. Le dépanneur va le confirmer.'),
          duration: Duration(seconds: 6),
        ),
      );
    } on MissionException catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.85);
    final somme = TravelFee.fcfa(widget.montant);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.kind == 'trajet'
                  ? 'Payer le déplacement'
                  : 'Payer la réparation',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              somme,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 14),
            if (_momo == null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Ce dépanneur n\'a pas encore indiqué de numéro Mobile Money. '
                  'Le paiement se fait en espèces.',
                  style: TextStyle(fontSize: 16, height: 1.4),
                ),
              ),
            if (_methodes.length > 1) ...[
              const Text(
                'Comment payez-vous ?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _methodes
                    .map(
                      (m) => ChoiceChip(
                        label: Text(
                          m.libelle,
                          style: const TextStyle(fontSize: 16),
                        ),
                        selected: _methode == m,
                        onSelected: _envoi
                            ? null
                            : (_) => setState(() => _methode = m),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],
            if (_methode.mobileMoney && _momo != null) ...[
              Text(
                '1. Envoyez exactement $somme par ${_methode.libelle} au :',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _momo!.numero,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if ((_momo!.titulaire ?? '').isNotEmpty)
                            Text(
                              'Au nom de ${_momo!.titulaire}',
                              style: const TextStyle(fontSize: 15),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      iconSize: 28,
                      tooltip: 'Copier le numéro',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () => _copier(_momo!.numero),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '2. Renseignez votre paiement',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              AppTextField(
                label: 'Numéro avec lequel vous avez payé',
                hint: '01 97 00 00 00',
                icon: Icons.phone_outlined,
                controller: _phone,
                enabled: !_envoi,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                validator: _validerPhone,
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Référence de la transaction',
                helper: 'Reçue par SMS après le paiement',
                icon: Icons.receipt_long_outlined,
                controller: _ref,
                enabled: !_envoi,
                textInputAction: TextInputAction.done,
                validator: _validerRef,
                onSubmitted: (_) => _envoi ? null : _envoyer(),
              ),
            ] else
              Text(
                'Remettez $somme en espèces au dépanneur, puis appuyez sur le '
                'bouton ci-dessous. Il confirmera la réception.',
                style: TextStyle(fontSize: 17, height: 1.45, color: muted),
              ),
            const SizedBox(height: 20),
            AppButton(
              label: _methode.mobileMoney
                  ? 'J\'ai payé : déclarer'
                  : 'J\'ai remis l\'argent',
              icon: Icons.check_rounded,
              loading: _envoi,
              onPressed: _envoyer,
            ),
          ],
        ),
      ),
    );
  }
}
