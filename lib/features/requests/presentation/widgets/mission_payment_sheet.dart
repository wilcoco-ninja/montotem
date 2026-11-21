
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

/// Retourne true si le paiement a ÃƒÂ©tÃƒÂ© dÃƒÂ©clarÃƒÂ©.
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
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
    _methodes = [
      if (_momo != null) _momo!.methode,
      PayMethod.especes,
    ];
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
        .showSnackBar(const SnackBar(content: Text('NumÃƒÂ©ro copiÃƒÂ©.')));
  }

  String? _validerPhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Champ obligatoire';
    if (!AuthService.isValidPhone(AuthService.normalizePhone(v))) {
      return 'NumÃƒÂ©ro invalide. Exemple : 01 97 00 00 00';
    }
    return null;
  }

  String? _validerRef(String? v) => (v == null || v.trim().length < 4)
      ? 'Saisissez la rÃƒÂ©fÃƒÂ©rence reÃƒÂ§ue par SMS'
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Paiement dÃƒÂ©clarÃƒÂ©. Le dÃƒÂ©panneur va le confirmer.'),
        duration: Duration(seconds: 6),
      ));
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
                  ? 'Payer le dÃƒÂ©placement'
                  : 'Payer la rÃƒÂ©paration',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(somme,
                style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryColor)),
            const SizedBox(height: 14),
            if (_momo == null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.warningColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Ce dÃƒÂ©panneur n\'a pas encore indiquÃƒÂ© de numÃƒÂ©ro Mobile Money. '
                  'Le paiement se fait en espÃƒÂ¨ces.',
                  style: TextStyle(fontSize: 16, height: 1.4),
                ),
              ),
            if (_methodes.length > 1) ...[
              const Text('Comment payez-vous ?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _methodes
                    .map((m) => ChoiceChip(
                          label: Text(m.libelle,
                              style: const TextStyle(fontSize: 16)),
                          selected: _methode == m,
                          onSelected: _envoi
                              ? null
                              : (_) => setState(() => _methode = m),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
            ],
            if (_methode.mobileMoney && _momo != null) ...[
              Text('1. Envoyez exactement $somme par ${_methode.libelle} au :',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
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
                          Text(_momo!.numero,
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w800)),
                          if ((_momo!.titulaire ?? '').isNotEmpty)
                            Text('Au nom de ${_momo!.titulaire}',
                                style: const TextStyle(fontSize: 15)),
                        ],
                      ),
                    ),
                    IconButton(
                      iconSize: 28,
                      tooltip: 'Copier le numÃƒÂ©ro',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () => _copier(_momo!.numero),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('2. Renseignez votre paiement',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              AppTextField(
                label: 'NumÃƒÂ©ro avec lequel vous avez payÃƒÂ©',
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
                label: 'RÃƒÂ©fÃƒÂ©rence de la transaction',
                helper: 'ReÃƒÂ§ue par SMS aprÃƒÂ¨s le paiement',
                icon: Icons.receipt_long_outlined,
                controller: _ref,
                enabled: !_envoi,
                textInputAction: TextInputAction.done,
                validator: _validerRef,
                onSubmitted: (_) => _envoi ? null : _envoyer(),
              ),
            ] else
              Text(
                'Remettez $somme en espÃƒÂ¨ces au dÃƒÂ©panneur, puis appuyez sur le '
                'bouton ci-dessous. Il confirmera la rÃƒÂ©ception.',
                style: TextStyle(fontSize: 17, height: 1.45, color: muted),
              ),
            const SizedBox(height: 20),
            AppButton(
              label: _methode.mobileMoney
                  ? 'J\'ai payÃƒÂ© : dÃƒÂ©clarer'
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
