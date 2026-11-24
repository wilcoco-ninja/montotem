import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/auth_layout.dart';
import 'package:montotem/features/auth/data/auth_service.dart' show AuthService;
import 'package:montotem/features/auth/data/door_service.dart';

/// Porte PRESTATAIRE : e-mail ou téléphone + mot de passe.
///
/// Différente de la porte client (SMS) : le prestataire a un dossier vérifié,
/// un compte professionnel, et se reconnecte avec des identifiants. Un compte
/// client ou admin est refusé ici et orienté vers sa propre porte.
///
/// Route : /pro/login
class ProLoginScreen extends StatefulWidget {
  const ProLoginScreen({super.key});

  @override
  State<ProLoginScreen> createState() => _ProLoginScreenState();
}

class _ProLoginScreenState extends State<ProLoginScreen> {
  static const int _maxEssais = 5;
  static const Duration _blocage = Duration(seconds: 30);

  final _door = DoorService();
  final _formKey = GlobalKey<FormState>();
  final _identifiant = TextEditingController();
  final _motDePasse = TextEditingController();

  bool _loading = false;
  String? _error;
  DoorMismatch? _mismatch;
  int _echecs = 0;
  DateTime? _bloqueJusqua;

  @override
  void dispose() {
    _identifiant.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  String? _validerIdentifiant(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Entrez votre e-mail ou votre numéro';
    if (s.contains('@')) {
      return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)
          ? null
          : 'Adresse e-mail invalide';
    }
    return AuthService.isValidPhone(AuthService.normalizePhone(s))
        ? null
        : 'Numéro invalide. Exemple : 01 97 00 00 00';
  }

  Future<void> _seConnecter() async {
    FocusScope.of(context).unfocus();

    final fin = _bloqueJusqua;
    if (fin != null && DateTime.now().isBefore(fin)) {
      final reste = fin.difference(DateTime.now()).inSeconds + 1;
      setState(() => _error = 'Trop d\'essais. Patientez $reste s.');
      return;
    }

    setState(() {
      _error = null;
      _mismatch = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      final route = await _door.signInProvider(
        identifier: _identifiant.text,
        password: _motDePasse.text,
      );
      TextInput.finishAutofillContext();
      _echecs = 0;
      if (mounted) context.go(route);
    } on DoorMismatch catch (m) {
      if (mounted) setState(() => _mismatch = m);
    } on DoorException catch (e) {
      _echecs++;
      if (_echecs >= _maxEssais) {
        _bloqueJusqua = DateTime.now().add(_blocage);
        _echecs = 0;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return AuthShell(
      title: 'Espace prestataire',
      subtitle:
          'Connectez-vous pour recevoir vos missions et gérer '
          'vos prestations et vos prix.',
      icon: Icons.handyman_outlined,
      onBack: _loading ? null : () => context.go('/explore'),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Pas encore prestataire ?', style: TextStyle(color: muted)),
              TextButton(
                onPressed: _loading
                    ? null
                    : () => context.push('/register/signup?role=provider'),
                child: const Text(
                  'Déposer mon dossier',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: _loading ? null : () => context.go('/login'),
            style: TextButton.styleFrom(foregroundColor: muted),
            child: const Text(
              'Je cherche un dépanneur · espace client',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_mismatch != null) ...[
                _Mismatch(
                  mismatch: _mismatch!,
                  onAction: () => context.go(_mismatch!.actionRoute),
                ),
                const SizedBox(height: 16),
              ],
              AppTextField(
                label: 'E-mail ou téléphone',
                hint: 'atelier@exemple.com ou 01 97 00 00 00',
                icon: Icons.person_outline_rounded,
                controller: _identifiant,
                enabled: !_loading,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                validator: _validerIdentifiant,
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Mot de passe',
                icon: Icons.lock_outline,
                controller: _motDePasse,
                enabled: !_loading,
                obscure: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Entrez votre mot de passe'
                    : null,
                onSubmitted: (_) => _loading ? null : _seConnecter(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading
                      ? null
                      : () => context.push('/forgot-password?space=provider'),
                  child: const Text('Mot de passe oublié ?'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                AuthErrorBanner(message: _error!),
              ],
              const SizedBox(height: 14),
              AppButton(
                label: 'Accéder à mon espace',
                icon: Icons.login_rounded,
                loading: _loading,
                onPressed: _seConnecter,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Mismatch extends StatelessWidget {
  const _Mismatch({required this.mismatch, required this.onAction});

  final DoorMismatch mismatch;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.swap_horiz_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mismatch.message,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppButton(
            label: mismatch.actionLabel,
            icon: Icons.arrow_forward_rounded,
            variant: AppButtonVariant.secondary,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}
