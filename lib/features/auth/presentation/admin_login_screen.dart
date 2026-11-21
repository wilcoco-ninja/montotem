import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/auth_layout.dart';
import 'package:montotem/features/auth/data/auth_service.dart';

/// Porte ADMIN : console d'administration, e-mail + mot de passe, compte
/// Supabase dont le profil a le rôle `admin`. Aucune autre porte n'y mène :
/// l'adresse n'est liée depuis aucun écran public.
///
/// Route : /admin/login (web uniquement)
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  static const int _maxEssais = 5;
  static const Duration _blocage = Duration(seconds: 60);

  final _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  int _echecs = 0;
  DateTime? _bloqueJusqua;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _seConnecter() async {
    FocusScope.of(context).unfocus();

    final fin = _bloqueJusqua;
    if (fin != null && DateTime.now().isBefore(fin)) {
      final reste = fin.difference(DateTime.now()).inSeconds + 1;
      setState(() => _errorMessage = 'Trop d\'essais. Patientez $reste s.');
      return;
    }

    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    try {
      final success = await _authService.signInAdmin(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;

      if (!success) {
        _echecs++;
        if (_echecs >= _maxEssais) {
          _bloqueJusqua = DateTime.now().add(_blocage);
          _echecs = 0;
        }
        setState(() => _errorMessage =
            'E-mail ou mot de passe incorrect, ou compte non administrateur.');
        return;
      }

      _echecs = 0;
      TextInput.finishAutofillContext();
      context.go('/admin/dashboard');
    } catch (e, stackTrace) {
      developer.log('Erreur de connexion admin',
          error: e, stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _errorMessage =
          'Une erreur de connexion est survenue. Veuillez réessayer.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return AuthShell(
        title: 'Console web uniquement',
        subtitle: 'L\'administration de MONTOTEM s\'utilise depuis un '
            'navigateur sur ordinateur.',
        icon: Icons.desktop_windows_outlined,
        onBack: () => context.go('/explore'),
        child: AppButton(
          label: 'Retour à l\'application',
          icon: Icons.arrow_back_rounded,
          onPressed: () => context.go('/explore'),
        ),
      );
    }

    return AuthShell(
      title: 'Connexion à la console',
      subtitle: 'Identifiants de l\'équipe MONTOTEM',
      icon: Icons.admin_panel_settings_outlined,
      onBack: _isLoading ? null : () => context.go('/explore'),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'Adresse e-mail',
                icon: Icons.email_outlined,
                controller: _emailController,
                enabled: !_isLoading,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: (value) {
                  final v = value?.trim() ?? '';
                  if (v.isEmpty) return 'Veuillez saisir votre e-mail';
                  if (!v.contains('@') || !v.contains('.')) {
                    return 'Adresse e-mail invalide';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Mot de passe',
                icon: Icons.lock_outline,
                controller: _passwordController,
                enabled: !_isLoading,
                obscure: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Veuillez saisir votre mot de passe'
                    : null,
                onSubmitted: (_) {
                  if (!_isLoading) _seConnecter();
                },
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                AuthErrorBanner(message: _errorMessage!),
              ],
              const SizedBox(height: 22),
              AppButton(
                label: 'Ouvrir la console',
                icon: Icons.login_rounded,
                loading: _isLoading,
                onPressed: _seConnecter,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
