import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/models/app_user.dart';
import 'package:montotem/core/theme/app_theme.dart';
import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/auth_layout.dart';
import 'package:montotem/features/auth/data/auth_service.dart';
import 'package:montotem/features/auth/presentation/widgets/photo_picker_field.dart';

class ClientRegistrationScreen extends StatefulWidget {
  const ClientRegistrationScreen({super.key});

  @override
  State<ClientRegistrationScreen> createState() =>
      _ClientRegistrationScreenState();
}

class _ClientRegistrationScreenState extends State<ClientRegistrationScreen> {
  final AuthService _authService = AuthService();
  final _formKey = GlobalKey<FormState>();

  final _prenomController = TextEditingController();
  final _nomController = TextEditingController();
  final _emailController = TextEditingController();
  late final TextEditingController _phoneController;

  Uint8List? _selfie;
  bool _isLoading = false;
  bool _photoManquanteSignalee = false;

  @override
  void initState() {
    super.initState();

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/login');
      });
      _phoneController = TextEditingController();
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    final email = user?.email ?? '';
    final phone = user?.phone ?? '';

    if (email.isNotEmpty) _emailController.text = email;
    _phoneController = TextEditingController(text: phone);

    // Le téléphone doit être vérifié avant de créer le profil.
    if (phone.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/register/phone?role=client');
      });
    }
  }

  @override
  void dispose() {
    _prenomController.dispose();
    _nomController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _afficherMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 8)),
    );
  }

  Future<void> _valider() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_selfie == null) {
      setState(() => _photoManquanteSignalee = true);
      _afficherMessage(
        'Une photo est nécessaire pour finaliser l\'inscription',
      );
      return;
    }

    setState(() => _isLoading = true);

    String photoUrl;
    try {
      photoUrl = await _authService.uploaderDocument(
        _selfie!,
        'selfie.jpg',
        kind: UploadKind.identity,
        folder: 'clients',
      );
    } on UploadException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _afficherMessage(e.message);
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _afficherMessage('Erreur lors du transfert de la photo : $e');
      return;
    }

    AppUser? user;
    try {
      user = await _authService.creerProfil(
        role: UserRole.client,
        nom: _nomController.text.trim(),
        prenom: _prenomController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text,
        photoProfilUrl: photoUrl,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _afficherMessage(e.message);
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _afficherMessage('Erreur inattendue ou réseau : $e');
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (user == null) {
      _afficherMessage('Impossible de créer votre profil. Réessayez.');
      return;
    }
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.7);
    final erreurPhoto = _photoManquanteSignalee && _selfie == null;

    return AuthShell(
      title: 'Votre profil client',
      subtitle: 'Dernière étape avant de trouver un dépanneur',
      icon: Icons.person_outline_rounded,
      onBack: _isLoading ? null : () => context.go('/welcome'),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Déjà un compte ?', style: TextStyle(color: muted)),
          TextButton(
            onPressed: _isLoading ? null : () => context.go('/login'),
            child: const Text(
              'Me connecter',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      child: AbsorbPointer(
        absorbing: _isLoading,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthInfoBanner(
                title: 'Compte sécurisé',
                message: 'Mot de passe et téléphone déjà configurés. Complétez votre profil.',
              ),
              const SizedBox(height: 22),
              const AuthSectionHeader(
                icon: Icons.badge_outlined,
                title: 'Identité',
                subtitle: 'Comment vous apparaîtrez aux prestataires',
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Prénom',
                      controller: _prenomController,
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                      label: 'Nom',
                      controller: _nomController,
                      textInputAction: TextInputAction.done,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Requis' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Email du compte',
                helper: 'Modifiable depuis les paramètres du compte',
                icon: Icons.email_outlined,
                controller: _emailController,
                readOnly: true,
              ),
              const SizedBox(height: 14),
              AppTextField(
                label: 'Téléphone vérifié',
                helper: 'Numéro validé par SMS',
                icon: Icons.phone_outlined,
                controller: _phoneController,
                readOnly: true,
              ),
              const SizedBox(height: 24),
              const AuthSectionHeader(
                icon: Icons.camera_alt_outlined,
                title: 'Votre photo',
                subtitle: 'Obligatoire pour la sécurité de tous',
              ),
              const SizedBox(height: 14),
              Center(
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: erreurPhoto
                        ? Border.all(color: AppTheme.errorColor, width: 1.6)
                        : null,
                  ),
                  child: PhotoPickerField(
                    label: 'Votre photo',
                    icon: Icons.camera_alt_outlined,
                    bytes: _selfie,
                    onChanged: (bytes) => setState(() {
                      _selfie = bytes;
                      if (bytes != null) _photoManquanteSignalee = false;
                    }),
                  ),
                ),
              ),
              if (erreurPhoto) ...[
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Photo obligatoire',
                    style: TextStyle(
                      color: AppTheme.errorColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 26),
              AppButton(
                label: 'Terminer mon inscription',
                icon: Icons.check_rounded,
                loading: _isLoading,
                onPressed: _valider,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
