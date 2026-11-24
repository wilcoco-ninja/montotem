import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/features/auth/data/auth_service.dart' show AuthService;
import 'package:montotem/features/auth/data/quick_auth_service.dart';

/// Erreur affichable telle quelle (message déjà en français).
class DoorException implements Exception {
  const DoorException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Le compte existe mais n'appartient pas à cette porte (ex. un prestataire
/// qui saisit son numéro sur la porte client). La session est déjà fermée ;
/// l'écran propose le bon chemin.
class DoorMismatch implements Exception {
  const DoorMismatch({
    required this.message,
    required this.actionLabel,
    required this.actionRoute,
  });

  final String message;
  final String actionLabel;
  final String actionRoute;

  @override
  String toString() => message;
}

/// Logique des portes d'entrée (une par rôle) :
///  - client      : code SMS / WhatsApp, ou e-mail + mot de passe → [routeAfterClientSignIn] ;
///  - prestataire : e-mail ou téléphone + mot de passe → [signInProvider] ;
///  - admin       : voir `AuthService.signInAdmin`.
///
/// Chaque porte refuse les comptes des autres rôles : pas de client dans
/// l'espace Pro, pas de prestataire dans l'espace client.
class DoorService {
  SupabaseClient get _sb => Supabase.instance.client;
  final QuickAuthService _quick = QuickAuthService();

  // ── Porte client ────────────────────────────────────────────────────────
  /// Connexion client par e-mail + mot de passe, puis contrôle du rôle.
  Future<String> signInClientWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _sb.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      if (res.session == null) {
        throw const DoorException('Connexion impossible. Réessayez.');
      }
    } on AuthException catch (e) {
      developer.log('signInClientWithEmail', error: e, name: 'DoorService');
      throw DoorException(_authMessage(e));
    } on DoorException {
      rethrow;
    } catch (e) {
      developer.log('signInClientWithEmail', error: e, name: 'DoorService');
      throw const DoorException(
        'Connexion impossible. Vérifiez votre réseau et réessayez.',
      );
    }
    return routeAfterClientSignIn();
  }

  /// À appeler juste après une connexion client réussie (code ou mot de
  /// passe). Retourne la route à ouvrir.
  Future<String> routeAfterClientSignIn() async {
    final ProfileState p;
    try {
      p = await _quick.profileState();
    } on QuickAuthException catch (e) {
      throw DoorException(e.message);
    }

    if (p.role == 'provider') {
      await AuthService().signOut();
      throw const DoorMismatch(
        message:
            'Ce compte est un compte prestataire. '
            'Les prestataires se connectent depuis l\'espace Pro.',
        actionLabel: 'Aller à l\'espace Pro',
        actionRoute: '/pro/login',
      );
    }
    if (p.role == 'admin') {
      await AuthService().signOut();
      throw const DoorMismatch(
        message:
            'Ce compte est un compte d\'administration. '
            'La console se trouve à une autre adresse.',
        actionLabel: 'Ouvrir la console',
        actionRoute: '/admin/login',
      );
    }
    return p.complete ? '/home' : '/register/quick/name';
  }

  // ── Porte prestataire ───────────────────────────────────────────────────
  /// Connexion par (e-mail | téléphone) + mot de passe. Retourne la route.
  Future<String> signInProvider({
    required String identifier,
    required String password,
  }) async {
    final id = identifier.trim();
    try {
      final AuthResponse res;
      if (id.contains('@')) {
        res = await _sb.auth.signInWithPassword(
          email: id.toLowerCase(),
          password: password,
        );
      } else {
        res = await _sb.auth.signInWithPassword(
          phone: AuthService.normalizePhone(id),
          password: password,
        );
      }
      if (res.session == null) {
        throw const DoorException('Connexion impossible. Réessayez.');
      }
    } on AuthException catch (e) {
      developer.log('signInProvider', error: e, name: 'DoorService');
      throw DoorException(_authMessage(e));
    } on DoorException {
      rethrow;
    } catch (e) {
      developer.log('signInProvider', error: e, name: 'DoorService');
      throw const DoorException(
        'Connexion impossible. Vérifiez votre réseau et réessayez.',
      );
    }

    final ProfileState p;
    try {
      p = await _quick.profileState();
    } on QuickAuthException catch (e) {
      throw DoorException(e.message);
    }

    switch (p.role) {
      case 'provider':
        return p.complete ? '/provider/home' : '/register/provider';
      case 'admin':
        await AuthService().signOut();
        throw const DoorMismatch(
          message:
              'Ce compte est un compte d\'administration. '
              'Il ne peut pas se connecter à l\'espace Pro.',
          actionLabel: 'Ouvrir la console',
          actionRoute: '/admin/login',
        );
      default:
        // Compte créé par le formulaire prestataire mais dossier pas encore
        // envoyé : on reprend l'inscription au lieu de refuser.
        if (!p.complete) return '/register/provider';
        await AuthService().signOut();
        throw const DoorMismatch(
          message:
              'Ce compte est un compte client. '
              'Les clients se connectent depuis l\'espace client.',
          actionLabel: 'Aller à l\'espace client',
          actionRoute: '/login',
        );
    }
  }

  String _authMessage(AuthException e) {
    final code = (e.code ?? '').toLowerCase();
    final msg = e.message.toLowerCase();
    if (code == 'invalid_credentials' || msg.contains('invalid login')) {
      return 'Identifiant ou mot de passe incorrect.';
    }
    if (code == 'email_not_confirmed' || msg.contains('not confirmed')) {
      return 'E-mail non confirmé. Ouvrez le lien reçu par e-mail.';
    }
    if (code == 'phone_not_confirmed') {
      return 'Numéro non vérifié. Reprenez l\'inscription pour recevoir le code.';
    }
    if (msg.contains('rate') ||
        msg.contains('too many') ||
        e.statusCode == '429') {
      return 'Trop de tentatives. Patientez une minute avant de réessayer.';
    }
    return 'Connexion impossible. Réessayez.';
  }
}
