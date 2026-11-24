import 'package:flutter/material.dart';

import 'package:montotem/core/config/api_config.dart';
import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/auth_layout.dart';
import 'package:montotem/features/payment/data/payment_service.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final PaymentService _paymentService = PaymentService();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  bool _isProcessing = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _payer() async {
    FocusScope.of(context).unfocus();

    final cleanAmountText = _amountController.text.replaceAll(
      RegExp(r'\s+'),
      '',
    );
    final int? amount = int.tryParse(cleanAmountText);
    final String phone = _phoneController.text.trim();
    final String name = _nameController.text.trim();

    if (phone.isEmpty || name.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez remplir correctement tous les champs'),
        ),
      );
      return;
    }

    final String apiKey = ApiConfig.kkiapayPublicKey;

    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Clé KKiaPay manquante. Vérifiez la configuration dans assets/.env',
          ),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final routeFuture = _paymentService.lancerPaiement(
        context: context,
        amount: amount,
        phone: phone,
        name: name,
        reason: _reasonController.text.trim().isNotEmpty
            ? _reasonController.text.trim()
            : 'Paiement MONTOTEM',
        apiKey: apiKey,
        onSuccess: (transactionId, amount) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Paiement réussi ! Réf : $transactionId'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        },
        onFailure: (reason) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Paiement échoué : $reason'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        },
      );

      if (routeFuture != null) {
        await routeFuture;
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.textTertiary;

    return Scaffold(
      appBar: AppBar(title: const Text('Paiement Mobile Money')),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthInfoBanner(
                    title: 'Paiement via MTN MoMo ou Moov Money',
                    message: 'Transaction sécurisée, confirmation immédiate.',
                    icon: Icons.phone_android_outlined,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(height: 22),
                  AppTextField(
                    label: 'Numéro Mobile Money',
                    hint: '61000000 ou 22961000000',
                    icon: Icons.phone_outlined,
                    controller: _phoneController,
                    enabled: !_isProcessing,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'Nom complet',
                    icon: Icons.person_outline,
                    controller: _nameController,
                    enabled: !_isProcessing,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'Montant (FCFA)',
                    icon: Icons.payments_outlined,
                    controller: _amountController,
                    enabled: !_isProcessing,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'Motif (optionnel)',
                    hint: 'Ex : Dépannage plomberie',
                    icon: Icons.description_outlined,
                    controller: _reasonController,
                    enabled: !_isProcessing,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _isProcessing ? null : _payer(),
                  ),
                  const SizedBox(height: 26),
                  AppButton(
                    label: _isProcessing ? 'Traitement...' : 'Payer maintenant',
                    icon: Icons.lock_outline,
                    loading: _isProcessing,
                    onPressed: _payer,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 14,
                        color: muted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Paiement sécurisé par KKiaPay',
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
