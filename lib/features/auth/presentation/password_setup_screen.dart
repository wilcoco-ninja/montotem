import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/theme/app_colors.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/auth_layout.dart';
import 'package:montotem/features/auth/data/auth_service.dart';

class PasswordSetupScreen extends StatefulWidget {
  const PasswordSetupScreen({super.key, this.isReset = false});

  final bool isReset;

  @override
  State<PasswordSetupScreen> createState() => _PasswordSetupScreenState();
}

class _PasswordSetupScreenState extends State<PasswordSetupScreen> {
  final AuthService _authService = AuthService();

  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _pwdController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _otpSent = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (!widget.isReset) {
      final existing = Supabase.instance.client.auth.currentUser?.email;
      if (existing != null &&
          !existing.contains('@phone.fake') &&
          !existing.contains('@privaterelay')) {
        _emailController.text = existing;
      }
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    _pwdController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// Porte de connexion de l'espace courant (Pro si ?space=provider).
  String get _porte {
    try {
      final uri = GoRouter.of(context).routerDelegate.currentConfiguration.uri;
      final p = uri.path;
      if (p == '/provider' || p.startsWith('/provider/')) return '/pro/login';
      if (p == '/pro' || p.startsWith('/pro/')) return '/pro/login';
      if (p.startsWith('/register/provider')) return '/pro/login';
      if (p.startsWith('/register/transport')) return '/pro/login';
      if (p.startsWith('/register') &&
          uri.queryParameters['role'] == 'provider') {
        return '/pro/login';
      }
      if (uri.queryParameters['space'] == 'provider') return '/pro/login';
      return '/login';
    } catch (_) {
      return '/login';
    }
  }

  String? _validerMotDePasse(String v) {
    if (v.isEmpty) return 'Champ obligatoire';
    if (v.length < 8) return 'Minimum 8 caractères';
    if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Au moins 1 majuscule';
    if (!RegExp(r'[0-9]').hasMatch(v)) return 'Au moins 1 chiffre';
    return null;
  }

  bool _emailValide(String v) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

  bool _formulaireValide() {
    setState(() => _errorMessage = null);

    if (!widget.isReset && !_emailValide(_emailController.text)) {
      setState(() => _errorMessage = 'Adresse email invalide.');
      return false;
    }
    final pwdError = _validerMotDePasse(_pwdController.text);
    if (pwdError != null) {
      setState(() => _errorMessage = pwdError);
      return false;
    }
    if (_pwdController.text != _confirmController.text) {
      setState(() => _errorMessage = 'Les mots de passe ne correspondent pas.');
      return false;
    }
    if (widget.isReset && _otpController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Merci de saisir le code reçu par SMS.');
      return false;
    }
    return true;
  }

  Future<void> _envoyerOtpReset() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _errorMessage = 'Merci de saisir votre numéro.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _authService.sendOTP(phone);
      if (!mounted) return;
      setState(() => _otpSent = true);
      _afficherMessage('Code envoyé par SMS.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Erreur réseau : $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _definirMotDePasse() async {
    if (!_formulaireValide()) return;

    setState(() => _isLoading = true);
    try {
      await _authService.setPasswordWithEmail(
        email: _emailController.text.trim(),
        password: _pwdController.text,
      );
      if (!mounted) return;

      _afficherMessage(
        'Compte sécurisé ! Un email de confirmation a été envoyé.',
        duration: const Duration(seconds: 5),
      );

      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      context.go('/register/role');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reinitialiserMotDePasse() async {
    if (!_formulaireValide()) return;

    setState(() => _isLoading = true);
    try {
      final ok = await _authService.resetMotDePasse(
        phoneNumber: _phoneController.text.trim(),
        otp: _otpController.text.trim(),
        nouveauMotDePasse: _pwdController.text,
      );
      if (!mounted) return;

      if (!ok) {
        setState(
          () => _errorMessage =
              'Code invalide ou expiré. Réessayez ou demandez un nouveau code.',
        );
        return;
      }

      _afficherMessage('Mot de passe réinitialisé avec succès !');
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      context.go(_porte);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _afficherMessage(String msg, {Duration? duration}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.successText,
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isReset
        ? 'Mot de passe oublié'
        : 'Sécuriser mon compte';
    final subtitle = widget.isReset
        ? 'Recevez un code par SMS, puis choisissez un nouveau mot de passe'
        : 'Choisissez un email et un mot de passe pour vous reconnecter sans SMS';

    return AuthShell(
      title: title,
      subtitle: subtitle,
      icon: widget.isReset
          ? Icons.lock_reset_outlined
          : Icons.verified_user_outlined,
      onBack: _isLoading ? null : () => context.go(_porte),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildFormulaire(),
      ),
    );
  }

  List<Widget> _buildFormulaire() {
    final showPasswordFields = !widget.isReset || _otpSent;

    return [
      if (widget.isReset) ...[
        AppTextField(
          label: 'Numéro de téléphone',
          hint: '+229 XX XX XX XX',
          icon: Icons.phone_outlined,
          controller: _phoneController,
          enabled: !_otpSent && !_isLoading,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 14),
        if (!_otpSent)
          AppButton(
            label: 'Envoyer le code',
            icon: Icons.sms_outlined,
            loading: _isLoading,
            onPressed: _envoyerOtpReset,
          ),
        if (_otpSent) ...[
          AppTextField(
            label: 'Code reçu par SMS',
            icon: Icons.pin_outlined,
            controller: _otpController,
            enabled: !_isLoading,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading ? null : _envoyerOtpReset,
              child: const Text('Renvoyer le code'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
      if (!widget.isReset) ...[
        AppTextField(
          label: 'Adresse email',
          hint: 'exemple@email.com',
          helper: 'Utilisée pour vous reconnecter et récupérer votre compte.',
          icon: Icons.email_outlined,
          controller: _emailController,
          enabled: !_isLoading,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),
      ],
      if (showPasswordFields) ...[
        AppTextField(
          label: 'Mot de passe',
          icon: Icons.lock_outline,
          controller: _pwdController,
          enabled: !_isLoading,
          obscure: true,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),
        PasswordRules(password: _pwdController.text),
        const SizedBox(height: 14),
        AppTextField(
          label: 'Confirmer le mot de passe',
          icon: Icons.lock_outline,
          controller: _confirmController,
          enabled: !_isLoading,
          obscure: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (_isLoading) return;
            widget.isReset ? _reinitialiserMotDePasse() : _definirMotDePasse();
          },
        ),
      ],
      if (_errorMessage != null) ...[
        const SizedBox(height: 16),
        AuthErrorBanner(message: _errorMessage!),
      ],
      if (showPasswordFields) ...[
        const SizedBox(height: 22),
        AppButton(
          label: widget.isReset ? 'Réinitialiser le mot de passe' : 'Continuer',
          icon: widget.isReset
              ? Icons.check_circle_outline
              : Icons.arrow_forward_rounded,
          loading: _isLoading,
          onPressed: widget.isReset
              ? _reinitialiserMotDePasse
              : _definirMotDePasse,
        ),
      ],
    ];
  }
}
