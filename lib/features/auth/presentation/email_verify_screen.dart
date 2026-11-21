import 'dart:async';

import 'package:flutter/material.dart';                 // ✅ corrigé
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/auth_layout.dart';
import 'package:montotem/features/auth/data/auth_service.dart';
import 'package:montotem/features/auth/presentation/registration_flow.dart';

class EmailVerifyScreen extends StatefulWidget {
  const EmailVerifyScreen({super.key, required this.email, this.role});

  final String email;
  final String? role;

  @override
  State<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends State<EmailVerifyScreen> {
  static const int _cooldownSeconds = 60;

  final AuthService _authService = AuthService();
  final _codeController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  int _cooldown = _cooldownSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _demarrerCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _demarrerCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown -= 1);
      }
    });
  }

  Future<void> _verifier() async {
    if (_isLoading) return;

    final code = _codeController.text.trim();
    if (code.length < 6) {
      setState(() => _errorMessage = 'Entrez le code complet à 6 chiffres.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final ok = await _authService.verifyEmailOtp(widget.email, code);
      if (!mounted) return;
      if (!ok) {
        setState(() => _errorMessage = 'Code invalide ou expiré.');
        return;
      }
      context.go(
        RegistrationRole.formRoute(RegistrationRole.parse(widget.role)),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _renvoyer() async {
    if (_isLoading || _cooldown > 0) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _authService.resendEmailOtp(widget.email);
      if (!mounted) return;
      _demarrerCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nouveau code envoyé par e-mail.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Impossible de renvoyer le code : $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _annuler() async {
    await _authService.signOut();
    if (!mounted) return;
    // ✅ Correction : comparaison de deux RegistrationRole, pas String vs enum.
    final role = RegistrationRole.parse(widget.role);
    context.go(role == RegistrationRole.provider ? '/pro/login' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return AuthShell(
      title: 'Vérifiez votre e-mail',
      subtitle: 'Code à 6 chiffres envoyé à\n${widget.email}',
      icon: Icons.mark_email_read_outlined,
      onBack: _isLoading ? null : _annuler,
      footer: TextButton.icon(
        onPressed: _isLoading ? null : _annuler,
        icon: const Icon(Icons.close_rounded, size: 18),
        label: const Text('Annuler l\'inscription'),
        style: TextButton.styleFrom(
          foregroundColor: onSurface.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            label: 'Code reçu par e-mail',
            hint: '123456',
            icon: Icons.pin_outlined,
            controller: _codeController,
            enabled: !_isLoading,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (v) {
              if (_errorMessage != null) setState(() => _errorMessage = null);
              if (v.trim().length == 6 && !_isLoading) _verifier();
            },
            // ✅ Correction : ne pas retourner Future? dans un void.
            onSubmitted: (_) {
              if (!_isLoading) _verifier();
            },
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            AuthErrorBanner(message: _errorMessage!),
          ],
          const SizedBox(height: 22),
          AppButton(
            label: 'Valider mon e-mail',
            icon: Icons.verified_outlined,
            loading: _isLoading,
            onPressed: _verifier,
          ),
          const SizedBox(height: 4),
          AppButton(
            label: _cooldown > 0
                ? 'Renvoyer le code (${_cooldown}s)'
                : 'Renvoyer le code',
            variant: AppButtonVariant.text,
            onPressed: (_isLoading || _cooldown > 0) ? null : _renvoyer,
          ),
        ],
      ),
    );
  }
}