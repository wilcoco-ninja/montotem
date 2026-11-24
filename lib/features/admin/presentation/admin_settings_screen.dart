import 'package:flutter/material.dart';

import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/app_ui.dart';
import 'package:montotem/core/widgets/auth_layout.dart';
import 'package:montotem/features/auth/data/auth_service.dart';

/// Permet à l'admin connecté de changer son pseudo et/ou son mot de passe.
/// Le mot de passe ACTUEL est toujours requis, par sécurité, même pour ne
/// changer que le pseudo.
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _pseudoController = TextEditingController();
  final TextEditingController _motDePasseActuelController =
      TextEditingController();
  final TextEditingController _nouveauMotDePasseController =
      TextEditingController();
  final TextEditingController _confirmationController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _pseudoController.dispose();
    _motDePasseActuelController.dispose();
    _nouveauMotDePasseController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _enregistrer() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final nouveauPseudo = _pseudoController.text.trim();
    final nouveauMotDePasse = _nouveauMotDePasseController.text;

    setState(() => _isLoading = true);
    final success = await _authService.changerIdentifiantsAdmin(
      motDePasseActuel: _motDePasseActuelController.text,
      nouveauPseudo: nouveauPseudo.isEmpty ? null : nouveauPseudo,
      nouveauMotDePasse: nouveauMotDePasse.isEmpty ? null : nouveauMotDePasse,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Identifiants mis à jour.'
              : 'Mot de passe actuel incorrect ou erreur serveur.',
        ),
      ),
    );
    if (success) {
      _motDePasseActuelController.clear();
      _nouveauMotDePasseController.clear();
      _confirmationController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Paramètres du compte admin')),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        child: ContentWidth(
          maxWidth: 560,
          child: SoftCard(
            padding: const EdgeInsets.all(22),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthSectionHeader(
                    icon: Icons.badge_outlined,
                    title: 'Identifiant',
                    subtitle: 'Laissez vide pour ne pas changer',
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Nouveau pseudo',
                    icon: Icons.person_outline,
                    controller: _pseudoController,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 26),
                  const AuthSectionHeader(
                    icon: Icons.lock_reset_outlined,
                    title: 'Mot de passe',
                    subtitle: 'Le mot de passe actuel est obligatoire',
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    label: 'Mot de passe actuel (obligatoire)',
                    icon: Icons.lock_outline,
                    controller: _motDePasseActuelController,
                    obscure: true,
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Requis pour toute modification'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'Nouveau mot de passe',
                    helper: 'Laisser vide pour ne pas changer',
                    icon: Icons.lock_reset_outlined,
                    controller: _nouveauMotDePasseController,
                    obscure: true,
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.isEmpty) return null;
                      if (v.length < 8) return 'Au moins 8 caractères';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    label: 'Confirmer le nouveau mot de passe',
                    icon: Icons.lock_reset_outlined,
                    controller: _confirmationController,
                    obscure: true,
                    textInputAction: TextInputAction.done,
                    validator: (v) {
                      if (_nouveauMotDePasseController.text.isEmpty) {
                        return null;
                      }
                      if (v != _nouveauMotDePasseController.text) {
                        return 'Les mots de passe ne correspondent pas';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  AppButton(
                    label: 'Enregistrer',
                    icon: Icons.check_rounded,
                    loading: _isLoading,
                    onPressed: _enregistrer,
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
