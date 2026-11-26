import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/auth_layout.dart';
import 'package:montotem/features/auth/data/auth_service.dart' show AuthService;
import 'package:montotem/features/auth/data/door_service.dart';
import 'package:montotem/features/auth/data/quick_auth_service.dart';

enum _Step { choix, code }

enum _Methode { telephone, email }

enum _Canal { sms, whatsapp }

/// Porte CLIENT. Le client choisit comment se connecter :
///  - Téléphone : numéro + code reçu par SMS ou par WhatsApp (au choix) ;
///  - E-mail : adresse + mot de passe.
/// Le numéro sert aussi à s'inscrire (un numéro inconnu crée le compte).
/// Google / Facebook en complément. Un compte prestataire ou admin est refusé
/// ici et orienté vers sa propre porte.
///
/// Routes : /login et /register/quick
class ClientAuthScreen extends StatefulWidget {
  const ClientAuthScreen({super.key});

  @override
  State<ClientAuthScreen> createState() => _ClientAuthScreenState();
}

class _ClientAuthScreenState extends State<ClientAuthScreen> {
  static const int _cooldownSeconds = 60;

  final _quick = QuickAuthService();
  final _door = DoorService();
  final _formPhone = GlobalKey<FormState>();
  final _formEmail = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _motDePasse = TextEditingController();
  final _codeFocus = FocusNode();

  StreamSubscription<AuthState>? _sub;
  Timer? _timer;
  _Step _step = _Step.choix;
  _Methode _methode = _Methode.telephone;
  _Canal _canal = _Canal.sms;
  String _e164 = '';
  bool _loading = false;
  String? _error;
  DoorMismatch? _mismatch;
  int _cooldown = 0;
  int _echecs = 0;
  DateTime? _bloqueJusqua;

  OtpChannel get _otpChannel =>
      _canal == _Canal.whatsapp ? OtpChannel.whatsapp : OtpChannel.sms;

  String get _nomCanal => _canal == _Canal.whatsapp ? 'WhatsApp' : 'SMS';

  @override
  void initState() {
    super.initState();
    // Retour d'un Google / Facebook : la session apparaît ici.
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn &&
          s.session != null &&
          _step == _Step.choix &&
          !_loading) {
        _continuer();
      }
    });
    if (_quick.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _continuer());
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _email.dispose();
    _motDePasse.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _continuer() async {
    try {
      final route = await _quick.nextRoute();
      if (mounted) context.go(route);
    } on QuickAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _demarrerCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  String? _validerTelephone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Entrez votre numéro';
    if (!AuthService.isValidPhone(AuthService.normalizePhone(v))) {
      return 'Numéro invalide. Exemple : 01 97 00 00 00';
    }
    return null;
  }

  String? _validerEmail(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Entrez votre e-mail';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
      return 'Adresse e-mail invalide';
    }
    return null;
  }

  void _changerMethode(_Methode m) {
    if (_loading || m == _methode) return;
    setState(() {
      _methode = m;
      _error = null;
      _mismatch = null;
    });
  }

  // ── Téléphone ─────────────────────────────────────────────────────────

  Future<void> _envoyerCode() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _mismatch = null;
    });
    if (!(_formPhone.currentState?.validate() ?? false)) return;

    final phone = AuthService.normalizePhone(_phone.text);
    setState(() => _loading = true);
    try {
      await _quick.sendOtp(phone, channel: _otpChannel);
      if (!mounted) return;
      setState(() {
        _e164 = phone;
        _step = _Step.code;
        _code.clear();
      });
      _demarrerCooldown();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _codeFocus.requestFocus(),
      );
    } on QuickAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifier() async {
    if (_loading) return;
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Entrez les 6 chiffres reçus par $_nomCanal.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _quick.verifyOtp(_e164, code);
      final route = await _door.routeAfterClientSignIn();
      if (mounted) context.go(route);
    } on DoorMismatch catch (m) {
      if (!mounted) return;
      _timer?.cancel();
      setState(() {
        _mismatch = m;
        _step = _Step.choix;
        _code.clear();
      });
    } on DoorException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on QuickAuthException catch (e) {
      if (!mounted) return;
      _code.clear();
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _renvoyer({_Canal? autreCanal}) async {
    if (_loading || (_cooldown > 0 && autreCanal == null)) return;
    if (autreCanal != null) _canal = autreCanal;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _quick.sendOtp(_e164, channel: _otpChannel);
      if (!mounted) return;
      _demarrerCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nouveau code envoyé par $_nomCanal.')),
      );
    } on QuickAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changerNumero() {
    _timer?.cancel();
    setState(() {
      _step = _Step.choix;
      _code.clear();
      _error = null;
    });
  }

  // ── E-mail + mot de passe ─────────────────────────────────────────────

  Future<void> _connecterEmail() async {
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
    if (!(_formEmail.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      final route = await _door.signInClientWithEmail(
        email: _email.text,
        password: _motDePasse.text,
      );
      TextInput.finishAutofillContext();
      _echecs = 0;
      if (mounted) context.go(route);
    } on DoorMismatch catch (m) {
      if (mounted) setState(() => _mismatch = m);
    } on DoorException catch (e) {
      _echecs++;
      if (_echecs >= 5) {
        _bloqueJusqua = DateTime.now().add(const Duration(seconds: 30));
        _echecs = 0;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _social(OAuthProvider p) async {
    setState(() {
      _error = null;
      _mismatch = null;
      _loading = true;
    });
    try {
      await _quick.signInWithProvider(p);
    } on QuickAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final saisieCode = _step == _Step.code;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final parEmail = _methode == _Methode.email;

    return AuthShell(
      title: saisieCode
          ? 'Entrez le code'
          : (parEmail
                ? 'Content de\nvous revoir'
                : 'Un dépanneur\npas loin de vous'),
      subtitle: saisieCode
          ? 'Code à 6 chiffres envoyé par $_nomCanal au $_e164'
          : (parEmail
                ? 'Connectez-vous avec votre e-mail et votre mot de passe.'
                : 'Choisissez comment recevoir votre code, ou connectez-vous '
                      'avec votre e-mail.'),
      icon: saisieCode
          ? (_canal == _Canal.whatsapp
                ? Icons.chat_outlined
                : Icons.sms_outlined)
          : Icons.bolt_rounded,
      onBack: _loading
          ? null
          : (saisieCode ? _changerNumero : () => context.go('/explore')),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!saisieCode)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Pas encore de compte ?', style: TextStyle(color: muted)),
                TextButton(
                  onPressed: _loading ? null : () => context.go('/join'),
                  child: const Text(
                    'S\'inscrire',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          if (!saisieCode)
            TextButton(
              onPressed: _loading ? null : () => context.go('/explore'),
              style: TextButton.styleFrom(foregroundColor: muted),
              child: const Text(
                'Explorer la carte sans compte',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
      child: saisieCode ? _buildCode() : _buildChoix(),
    );
  }

  Widget _buildChoix() {
    final parEmail = _methode == _Methode.email;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_mismatch != null) ...[
          _MismatchCard(
            mismatch: _mismatch!,
            onAction: () => context.go(_mismatch!.actionRoute),
          ),
          const SizedBox(height: 16),
        ],
        SegmentedButton<_Methode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: _Methode.telephone,
              icon: Icon(Icons.phone_iphone_rounded, size: 18),
              label: Text('Téléphone'),
            ),
            ButtonSegment(
              value: _Methode.email,
              icon: Icon(Icons.alternate_email_rounded, size: 18),
              label: Text('E-mail'),
            ),
          ],
          selected: {_methode},
          onSelectionChanged: (s) => _changerMethode(s.first),
        ),
        const SizedBox(height: 18),
        if (parEmail) _buildEmail() else _buildPhone(),
        if (_error != null) ...[
          const SizedBox(height: 14),
          AuthErrorBanner(message: _error!),
        ],
        const SizedBox(height: 18),
        AppButton(
          label: parEmail ? 'Se connecter' : 'Recevoir mon code par $_nomCanal',
          icon: parEmail ? Icons.login_rounded : Icons.arrow_forward_rounded,
          loading: _loading,
          onPressed: parEmail ? _connecterEmail : _envoyerCode,
        ),
        const SizedBox(height: 20),
        const AuthDividerLabel(label: 'ou'),
        const SizedBox(height: 14),
        AppButton(
          label: 'Continuer avec Google',
          icon: Icons.g_mobiledata_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: _loading ? null : () => _social(OAuthProvider.google),
        ),
        const SizedBox(height: 10),
        AppButton(
          label: 'Continuer avec Facebook',
          icon: Icons.facebook_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: _loading ? null : () => _social(OAuthProvider.facebook),
        ),
      ],
    );
  }

  Widget _buildPhone() {
    return Form(
      key: _formPhone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Recevoir le code par',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<_Canal>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: _Canal.sms,
                icon: Icon(Icons.sms_outlined, size: 18),
                label: Text('SMS'),
              ),
              ButtonSegment(
                value: _Canal.whatsapp,
                icon: Icon(Icons.chat_outlined, size: 18),
                label: Text('WhatsApp'),
              ),
            ],
            selected: {_canal},
            onSelectionChanged: (s) => setState(() => _canal = s.first),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _phone,
            enabled: !_loading,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
            ],
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            validator: _validerTelephone,
            onFieldSubmitted: (_) => _loading ? null : _envoyerCode(),
            decoration: const InputDecoration(
              labelText: 'Numéro de téléphone',
              hintText: '01 97 00 00 00',
              helperText: 'Bénin · +229',
              prefixIcon: Icon(Icons.phone_outlined),
              prefixText: '+229  ',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmail() {
    return AutofillGroup(
      child: Form(
        key: _formEmail,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'E-mail',
              hint: 'vous@exemple.com',
              icon: Icons.alternate_email_rounded,
              controller: _email,
              enabled: !_loading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email,
              ],
              validator: _validerEmail,
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
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Entrez votre mot de passe' : null,
              onSubmitted: (_) => _loading ? null : _connecterEmail(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _loading
                    ? null
                    : () => context.push('/forgot-password'),
                child: const Text('Mot de passe oublié ?'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCode() {
    final autre = _canal == _Canal.sms ? _Canal.whatsapp : _Canal.sms;
    final nomAutre = autre == _Canal.whatsapp ? 'WhatsApp' : 'SMS';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CodeBoxes(
          controller: _code,
          focus: _codeFocus,
          enabled: !_loading,
          onChanged: (v) {
            if (_error != null) setState(() => _error = null);
            if (v.trim().length == 6) _verifier();
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          AuthErrorBanner(message: _error!),
        ],
        const SizedBox(height: 22),
        AppButton(
          label: 'Valider',
          icon: Icons.check_rounded,
          loading: _loading,
          onPressed: _verifier,
        ),
        const SizedBox(height: 6),
        AppButton(
          label: _cooldown > 0
              ? 'Renvoyer le code (${_cooldown}s)'
              : 'Renvoyer le code',
          variant: AppButtonVariant.text,
          onPressed: (_loading || _cooldown > 0) ? null : _renvoyer,
        ),
        AppButton(
          label: 'Recevoir plutôt par $nomAutre',
          variant: AppButtonVariant.text,
          onPressed: (_loading || _cooldown > 0)
              ? null
              : () => _renvoyer(autreCanal: autre),
        ),
        AppButton(
          label: 'Changer de numéro',
          variant: AppButtonVariant.text,
          onPressed: _loading ? null : _changerNumero,
        ),
      ],
    );
  }
}

/// Six cases pour le code (SMS ou WhatsApp). Un vrai champ invisible reçoit la saisie
/// (clavier numérique, collage, remplissage automatique du SMS).
class _CodeBoxes extends StatelessWidget {
  const _CodeBoxes({
    required this.controller,
    required this.focus,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;
  final ValueChanged<String> onChanged;

  static const int _length = 6;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => focus.requestFocus(),
      child: AnimatedBuilder(
        animation: Listenable.merge([controller, focus]),
        builder: (context, _) {
          final text = controller.text;
          final current = text.length >= _length ? _length - 1 : text.length;
          return Stack(
            children: [
              Row(
                children: [
                  for (var i = 0; i < _length; i++) ...[
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        height: 62,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: focus.hasFocus && i == current
                                ? scheme.primary
                                : scheme.outline,
                            width: focus.hasFocus && i == current ? 2.4 : 1.4,
                          ),
                        ),
                        child: Text(
                          i < text.length ? text[i] : '',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    if (i < _length - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: controller,
                    focusNode: focus,
                    enabled: enabled,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: _length,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: onChanged,
                    decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MismatchCard extends StatelessWidget {
  const _MismatchCard({required this.mismatch, required this.onAction});

  final DoorMismatch mismatch;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
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
                    fontSize: 15,
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
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}
