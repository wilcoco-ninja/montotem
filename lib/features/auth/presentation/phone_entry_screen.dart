import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/auth_layout.dart';
import 'package:montotem/features/auth/data/auth_service.dart';
import 'package:montotem/features/auth/presentation/registration_flow.dart';

/// Affiché quand un utilisateur connecté n'a pas de numéro vérifié :
/// envoie le code SMS puis reprend l'inscription au bon formulaire.
class PhoneEntryScreen extends StatefulWidget {
  const PhoneEntryScreen({super.key, this.role});

  final String? role;

  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  String? get _role => RegistrationRole.parse(widget.role);

  String get _porte =>
      _role == RegistrationRole.provider ? '/pro/login' : '/login';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_authService.isAuthenticated) {
        context.go(_porte);
        return;
      }
      final phone = _authService.currentPhone;
      if (phone != null && phone.isNotEmpty) {
        context.go(RegistrationRole.formRoute(_role));
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  String? _validerPhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Champ obligatoire';
    if (!AuthService.isValidPhone(AuthService.normalizePhone(v))) {
      return 'Numéro invalide. Exemple : 01 97 00 00 00';
    }
    return null;
  }

  Future<void> _envoyer() async {
    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final phone = AuthService.normalizePhone(_phoneController.text);

    setState(() => _isLoading = true);
    try {
      await _authService.resendPhoneOtp(phone);
      if (!mounted) return;
      setState(() => _isLoading = false);
      context.go(
        RegistrationRole.withRole('/register/verify-phone', _role),
        extra: phone,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Erreur inattendue : $e';
      });
    }
  }

  Future<void> _seDeconnecter() async {
    await _authService.signOut();
    if (!mounted) return;
    context.go(_porte);
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.7);

    return AuthShell(
      title: 'Vérifiez votre numéro',
      subtitle: 'Un code SMS sécurise votre compte avant de créer votre profil',
      icon: Icons.phone_android_outlined,
      onBack: _isLoading ? null : () => context.go(_porte),
      footer: TextButton.icon(
        onPressed: _isLoading ? null : _seDeconnecter,
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: const Text('Se déconnecter'),
        style: TextButton.styleFrom(foregroundColor: muted),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Numéro de téléphone',
              hint: '01 97 00 00 00',
              helper: 'Format Bénin : +229 01 XX XX XX XX',
              icon: Icons.phone_outlined,
              controller: _phoneController,
              enabled: !_isLoading,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
              validator: _validerPhone,
              onSubmitted: (_) => _isLoading ? null : _envoyer(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              AuthErrorBanner(message: _errorMessage!),
            ],
            const SizedBox(height: 22),
            AppButton(
              label: 'Recevoir le code',
              icon: Icons.sms_outlined,
              loading: _isLoading,
              onPressed: _envoyer,
            ),
          ],
        ),
      ),
    );
  }
}
