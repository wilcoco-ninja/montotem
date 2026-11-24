import 'package:flutter/material.dart'; // ✅ corrigé
import 'package:go_router/go_router.dart';

import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/auth_layout.dart';
import 'package:montotem/features/auth/data/quick_auth_service.dart';

/// Écran 3/3 — prénom et nom, puis directement la carte.
/// Pré-rempli quand l'inscription vient de Google ou Facebook.
/// Route : /register/quick/name
class QuickNameScreen extends StatefulWidget {
  const QuickNameScreen({super.key});

  @override
  State<QuickNameScreen> createState() => _QuickNameScreenState();
}

class _QuickNameScreenState extends State<QuickNameScreen> {
  final _service = QuickAuthService();
  final _formKey = GlobalKey<FormState>();
  final _prenom = TextEditingController();
  final _nom = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final names = _service.suggestedNames();
    _prenom.text = names.first;
    _nom.text = names.last;
  }

  @override
  void dispose() {
    _prenom.dispose();
    _nom.dispose();
    super.dispose();
  }

  Future<void> _valider() async {
    if (_loading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _service.registerClient(
        firstName: _prenom.text,
        lastName: _nom.text,
      );
      if (mounted) context.go('/');
    } on QuickAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Votre nom',
      subtitle: 'Comment doit-on vous appeler ?',
      icon: Icons.person_outline_rounded,
      onBack: _loading ? null : () => context.go('/login'),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              label: 'Prénom',
              controller: _prenom,
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requis' : null,
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Nom',
              controller: _nom,
              textInputAction: TextInputAction.done,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requis' : null,
              onSubmitted: (_) {
                if (!_loading) _valider();
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              AuthErrorBanner(message: _error!),
            ],
            const SizedBox(height: 22),
            AppButton(
              label: 'Continuer',
              icon: Icons.arrow_forward_rounded,
              loading: _loading,
              onPressed: _valider,
            ),
          ],
        ),
      ),
    );
  }
}
