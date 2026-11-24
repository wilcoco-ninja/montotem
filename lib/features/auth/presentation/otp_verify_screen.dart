import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/auth_layout.dart';
import 'package:montotem/features/auth/data/auth_service.dart';
import 'package:montotem/features/auth/presentation/registration_flow.dart';

class OtpVerifyScreen extends StatefulWidget {
  const OtpVerifyScreen({super.key, required this.phone, this.role});

  final String phone;
  final String? role;

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  static const int _cooldownSeconds = 60;

  final AuthService _authService = AuthService();
  final _otpController = TextEditingController();

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
    _otpController.dispose();
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

    final code = _otpController.text.trim();
    if (code.length < 6) {
      setState(() => _errorMessage = 'Entrez le code complet à 6 chiffres.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final ok = await _authService.verifyPhoneOtp(widget.phone, code);
      if (!mounted) return;

      if (!ok) {
        setState(() => _errorMessage = 'Code invalide ou expiré.');
        return;
      }

      context.go(
        RegistrationRole.formRoute(RegistrationRole.parse(widget.role)),
      );
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

  Future<void> _renvoyer() async {
    if (_isLoading || _cooldown > 0) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _authService.resendPhoneOtp(widget.phone);
      if (!mounted) return;
      _demarrerCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nouveau code envoyé par SMS.')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Impossible de renvoyer le code : $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _annuler() async {
    await _authService.signOut();
    if (!mounted) return;
    context.go(
      widget.role == RegistrationRole.provider ? '/pro/login' : '/login',
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return AuthShell(
      title: 'Vérifiez votre numéro',
      subtitle: 'Code à 6 chiffres envoyé au\n${widget.phone}',
      icon: Icons.sms_outlined,
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
          TextField(
            controller: _otpController,
            enabled: !_isLoading,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            autofillHints: const [AutofillHints.oneTimeCode],
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 10,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (val) {
              if (_errorMessage != null) setState(() => _errorMessage = null);
              if (val.trim().length == 6 && !_isLoading) _verifier();
            },
            decoration: const InputDecoration(
              hintText: '••••••',
              counterText: '',
              contentPadding: EdgeInsets.symmetric(vertical: 20),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            AuthErrorBanner(message: _errorMessage!),
          ],
          const SizedBox(height: 22),
          AppButton(
            label: 'Vérifier le code',
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
