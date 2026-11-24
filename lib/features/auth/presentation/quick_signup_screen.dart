import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/auth_layout.dart';
import 'package:montotem/features/auth/data/auth_service.dart' show AuthService;
import 'package:montotem/features/auth/data/quick_auth_service.dart';
import 'package:montotem/features/auth/presentation/registration_flow.dart';

/// Ãƒâ€°cran 1/3 Ã¢â‚¬â€ inscription ou connexion en une saisie : le numÃƒÂ©ro.
/// Route : /register/quick?role=client|provider
class QuickSignupScreen extends StatefulWidget {
  const QuickSignupScreen({super.key, this.role});

  final String? role;

  @override
  State<QuickSignupScreen> createState() => _QuickSignupScreenState();
}

class _QuickSignupScreenState extends State<QuickSignupScreen> {
  final _service = QuickAuthService();
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();

  StreamSubscription<AuthState>? _sub;
  bool _loading = false;
  String? _error;

  String? get _role => RegistrationRole.parse(widget.role);

  bool get _googleActif =>
      (dotenv.env['GOOGLE_LOGIN_ENABLED'] ?? 'false').toLowerCase() == 'true';

  @override
  void initState() {
    super.initState();
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn && s.session != null) {
        _continuer();
      }
    });
    if (_service.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _continuer());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _continuer() async {
    try {
      final route = await _service.nextRoute(requestedRole: _role);
      if (mounted) context.go(route);
    } on QuickAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  String? _valider(String? v) {
    if (v == null || v.trim().isEmpty) return 'Entrez votre numÃƒÂ©ro';
    if (!AuthService.isValidPhone(AuthService.normalizePhone(v))) {
      return 'NumÃƒÂ©ro invalide. Exemple : 01 97 00 00 00';
    }
    return null;
  }

  Future<void> _envoyerCode() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final phone = AuthService.normalizePhone(_phone.text);
    setState(() => _loading = true);
    try {
      await _service.sendOtp(phone);
      if (!mounted) return;
      context.push(
        RegistrationRole.withRole('/register/quick/otp', _role),
        extra: phone,
      );
    } on QuickAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _social(OAuthProvider p) async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await _service.signInWithProvider(p);
    } on QuickAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.7);
    final prestataire = _role == RegistrationRole.provider;

    return AuthShell(
      title: prestataire ? 'Devenez prestataire' : 'Connexion ou inscription',
      subtitle: prestataire
          ? 'Commencez avec votre numÃƒÂ©ro, on s\'occupe du reste'
          : 'MÃƒÂªme dÃƒÂ©marche pour les deux : votre numÃƒÂ©ro et un code SMS. '
                'Pas de mot de passe ÃƒÂ  retenir.',
      icon: prestataire ? Icons.build_circle_outlined : Icons.bolt_rounded,
      onBack: _loading ? null : () => context.go('/explore'),
      footer: TextButton(
        onPressed: _loading ? null : () => context.go('/explore'),
        child: Text(
          'Continuer sans compte',
          style: TextStyle(color: muted, fontWeight: FontWeight.w700),
        ),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'NumÃƒÂ©ro de tÃƒÂ©lÃƒÂ©phone',
              hint: '01 97 00 00 00',
              helper: 'Vous recevrez un code par SMS',
              icon: Icons.phone_outlined,
              controller: _phone,
              enabled: !_loading,
              autofocus: true,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
              ],
              validator: _valider,
              onSubmitted: (_) => _loading ? null : _envoyerCode(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              AuthErrorBanner(message: _error!),
            ],
            const SizedBox(height: 18),
            AppButton(
              label: 'Recevoir mon code',
              icon: Icons.sms_outlined,
              loading: _loading,
              onPressed: _envoyerCode,
            ),
            if (!prestataire && _googleActif) ...[
              const SizedBox(height: 18),
              const AuthDividerLabel(label: 'ou'),
              const SizedBox(height: 14),
              AppButton(
                label: 'Continuer avec Google',
                icon: Icons.g_mobiledata_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: _loading
                    ? null
                    : () => _social(OAuthProvider.google),
              ),
            ],
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: _loading ? null : () => context.go('/login'),
                style: TextButton.styleFrom(foregroundColor: muted),
                child: const Text(
                  'Connexion avec mot de passe',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
