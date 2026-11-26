import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:montotem/core/widgets/app_button.dart';
import 'package:montotem/core/widgets/app_text_field.dart';
import 'package:montotem/core/widgets/auth_layout.dart';
import 'package:montotem/features/auth/data/auth_service.dart'
    show ApiException, AuthService, SignUpSansTelephone;

/// Inscription CLIENT par e-mail + mot de passe, sans telephone.
///
/// Decision produit : le service SMS/WhatsApp est differe, donc l'inscription
/// client ne passe plus par le numero (l'OTP SMS reste disponible avec le
/// numero quand il sera active). Etapes :
///  1. creation du compte (signUp email + mot de passe) ;
///  2a. session ouverte -> /register/client (profil, photo facultative) ;
///  2b. « Confirm email » actif cote Supabase -> ecran d'attente, l'utilisateur
///      confirme par e-mail puis appuie sur « J'ai confirme mon e-mail ».
/// Route : /register/client/email
class ClientEmailSignupScreen extends StatefulWidget {
  const ClientEmailSignupScreen({super.key});

  @override
  State<ClientEmailSignupScreen> createState() =>
      _ClientEmailSignupScreenState();
}

class _ClientEmailSignupScreenState extends State<ClientEmailSignupScreen> {
  final AuthService _service = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _motDePasse = TextEditingController();
  final _confirmation = TextEditingController();

  bool _attenteConfirmation = false;
  bool _emailRenvoye = false;
  bool _chargement = false;
  String? _erreur;

  @override
  void dispose() {
    _email.dispose();
    _motDePasse.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  String? _validerEmail(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Requis';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(t);
    if (!ok) return 'Adresse e-mail invalide';
    return null;
  }

  String? _validerMotDePasse(String? v) {
    if (v == null || v.length < 8) return 'Au moins 8 caractères';
    return null;
  }

  String? _validerConfirmation(String? v) {
    if (v != _motDePasse.text) {
      return 'Les deux mots de passe ne correspondent pas';
    }
    return null;
  }

  Future<void> _soumettre() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _erreur = null;
      _emailRenvoye = false;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _chargement = true);
    try {
      final etat = await _service.inscrireSansTelephone(
        email: _email.text,
        password: _motDePasse.text,
      );
      if (!mounted) return;
      if (etat == SignUpSansTelephone.emailAConfirmer) {
        setState(() {
          _attenteConfirmation = true;
          _chargement = false;
        });
      } else {
        context.go('/register/client');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _erreur = e.message;
          _chargement = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _erreur = 'Erreur réseau. Réessayez dans un instant.';
          _chargement = false;
        });
      }
    }
  }

  Future<void> _jAiConfirme() async {
    setState(() => _erreur = null);
    setState(() => _chargement = true);
    try {
      await _service.connecterApresConfirmationEmail(
        email: _email.text,
        password: _motDePasse.text,
      );
      if (!mounted) return;
      context.go('/register/client');
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _erreur = e.message;
          _chargement = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _erreur = 'Erreur réseau. Réessayez dans un instant.';
          _chargement = false;
        });
      }
    }
  }

  Future<void> _renvoyerEmail() async {
    setState(() {
      _erreur = null;
      _chargement = true;
    });
    try {
      await _service.resendSignupEmail(_email.text);
      if (!mounted) return;
      setState(() {
        _emailRenvoye = true;
        _chargement = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _erreur = e.message;
          _chargement = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _erreur = 'Erreur réseau. Réessayez dans un instant.';
          _chargement = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.7);

    return AuthShell(
      title: 'Créez votre compte',
      subtitle:
          'E-mail + mot de passe. Sans numéro : le service SMS '
          'sera activé plus tard.',
      icon: Icons.mail_outline_rounded,
      onBack: _chargement ? null : () => context.go('/explore'),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Déjà un compte ?', style: TextStyle(color: muted)),
          TextButton(
            onPressed: _chargement ? null : () => context.go('/login'),
            child: const Text(
              'Se connecter',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_attenteConfirmation) ...[
              const AuthInfoBanner(
                title: 'Confirmez votre e-mail',
                message:
                    'Un lien de confirmation vient de partir. Ouvrez-le, '
                    'puis revenez ici et appuyez sur '
                    '« J\'ai confirmé mon e-mail ».',
              ),
              const SizedBox(height: 14),
              if (_emailRenvoye)
                const AuthInfoBanner(
                  title: 'E-mail renvoyé',
                  message: 'Vérifiez vos messages (et vos indésirables).',
                ),
              const SizedBox(height: 14),
            ],
            AppTextField(
              label: 'Adresse e-mail',
              hint: 'vous@exemple.com',
              icon: Icons.email_outlined,
              controller: _email,
              enabled: !_chargement && !_attenteConfirmation,
              autofocus: !_attenteConfirmation,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              validator: _validerEmail,
              onSubmitted: (_) =>
                  _chargement ? null : FocusScope.of(context).nextFocus(),
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Mot de passe',
              helper: 'Au moins 8 caractères',
              icon: Icons.lock_outline_rounded,
              controller: _motDePasse,
              obscure: true,
              enabled: !_chargement,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              validator: _validerMotDePasse,
              onSubmitted: (_) =>
                  _chargement ? null : FocusScope.of(context).nextFocus(),
            ),
            const SizedBox(height: 14),
            AppTextField(
              label: 'Confirmez le mot de passe',
              icon: Icons.lock_reset_outlined,
              controller: _confirmation,
              obscure: true,
              enabled: !_chargement,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              validator: _validerConfirmation,
              onSubmitted: (_) =>
                  _chargement || _attenteConfirmation ? null : _soumettre(),
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 14),
              AuthErrorBanner(message: _erreur!),
            ],
            const SizedBox(height: 18),
            if (!_attenteConfirmation)
              AppButton(
                label: 'Créer mon compte',
                icon: Icons.check_rounded,
                loading: _chargement,
                onPressed: _soumettre,
              )
            else ...[
              AppButton(
                label: "J'ai confirmé mon e-mail",
                icon: Icons.mark_email_read_outlined,
                loading: _chargement,
                onPressed: _jAiConfirme,
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _chargement ? null : _renvoyerEmail,
                child: const Text(
                  'Je n\'ai rien reçu : renvoyer l\'e-mail',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
