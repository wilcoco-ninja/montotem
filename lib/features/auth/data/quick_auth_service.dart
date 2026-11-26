import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/flavor/app_flavor.dart';

/// Erreur lisible par l'utilisateur (message déjà en français).
class QuickAuthException implements Exception {
  QuickAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// État du profil après authentification.
class ProfileState {
  const ProfileState({
    required this.role,
    required this.complete,
    this.firstName,
    this.lastName,
  });

  final String role; // client | provider | admin
  final bool complete;
  final String? firstName;
  final String? lastName;
}

/// Authentification express : téléphone + code SMS, ou Google / Facebook.
///
/// Ne dépend d'aucun autre service de l'application : tout passe par
/// Supabase Auth et la fonction `register_profile` (le téléphone et l'email
/// sont lus côté serveur dans auth.users, jamais fournis par le client).
class QuickAuthService {
  SupabaseClient get _sb => Supabase.instance.client;

  /// Lien de retour OAuth mobile (à déclarer aussi dans Supabase >
  /// Authentication > URL Configuration et dans AndroidManifest / Info.plist).
  static const String oauthRedirectMobile = 'io.montotem.bj://login-callback/';

  bool get isAuthenticated => _sb.auth.currentSession != null;

  // ── Téléphone + OTP ───────────────────────────────────────────────────
  /// Envoie le code par SMS (défaut) ou par WhatsApp. La vérification
  /// ([verifyOtp]) est identique pour les deux canaux.
  Future<void> sendOtp(
    String phoneE164, {
    OtpChannel channel = OtpChannel.sms,
  }) async {
    try {
      await _sb.auth.signInWithOtp(
        phone: phoneE164,
        shouldCreateUser: true,
        channel: channel,
      );
    } on AuthException catch (e) {
      developer.log('sendOtp', error: e, name: 'QuickAuthService');
      throw QuickAuthException(_authMessage(e));
    } catch (e) {
      developer.log('sendOtp', error: e, name: 'QuickAuthService');
      throw QuickAuthException('Connexion impossible. Vérifiez votre réseau.');
    }
  }

  Future<void> verifyOtp(String phoneE164, String code) async {
    try {
      final res = await _sb.auth.verifyOTP(
        phone: phoneE164,
        token: code,
        type: OtpType.sms,
      );
      if (res.session == null) {
        throw QuickAuthException('Code invalide ou expiré.');
      }
    } on AuthException catch (e) {
      developer.log('verifyOtp', error: e, name: 'QuickAuthService');
      throw QuickAuthException(_authMessage(e));
    } on QuickAuthException {
      rethrow;
    } catch (e) {
      developer.log('verifyOtp', error: e, name: 'QuickAuthService');
      throw QuickAuthException('Connexion impossible. Vérifiez votre réseau.');
    }
  }

  // ── Google / Facebook ─────────────────────────────────────────────────
  /// Ouvre le navigateur du fournisseur. La session arrive ensuite par
  /// `onAuthStateChange` (l'écran appelant écoute l'événement signedIn).
  Future<void> signInWithProvider(OAuthProvider provider) async {
    try {
      await _sb.auth.signInWithOAuth(
        provider,
        redirectTo: kIsWeb ? null : oauthRedirectMobile,
      );
    } on AuthException catch (e) {
      developer.log('oauth', error: e, name: 'QuickAuthService');
      throw QuickAuthException(_authMessage(e));
    } catch (e) {
      developer.log('oauth', error: e, name: 'QuickAuthService');
      throw QuickAuthException('Connexion impossible. Réessayez.');
    }
  }

  // ── Profil ────────────────────────────────────────────────────────────
  Future<ProfileState> profileState() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw QuickAuthException('Session expirée.');
    try {
      final row = await _sb
          .from('profiles')
          .select('role, inscription_complete, first_name, last_name')
          .eq('id', uid)
          .maybeSingle();
      return ProfileState(
        role: '${row?['role'] ?? 'client'}',
        complete: row?['inscription_complete'] == true,
        firstName: row?['first_name'] as String?,
        lastName: row?['last_name'] as String?,
      );
    } catch (e) {
      developer.log('profileState', error: e, name: 'QuickAuthService');
      throw QuickAuthException('Impossible de charger votre profil.');
    }
  }

  /// Prénom / nom proposés par Google ou Facebook (métadonnées du compte).
  ({String first, String last}) suggestedNames() {
    final meta = _sb.auth.currentUser?.userMetadata ?? const {};
    final full = '${meta['full_name'] ?? meta['name'] ?? ''}'.trim();
    var first = '${meta['given_name'] ?? ''}'.trim();
    var last = '${meta['family_name'] ?? ''}'.trim();
    if (first.isEmpty && full.isNotEmpty) {
      final parts = full.split(RegExp(r'\s+'));
      first = parts.first;
      last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }
    return (first: first, last: last);
  }

  Future<void> registerClient({
    required String firstName,
    required String lastName,
  }) async {
    try {
      await _sb.rpc(
        'register_profile',
        params: {
          'p_role': 'client',
          'p_first_name': firstName.trim(),
          'p_last_name': lastName.trim(),
        },
      );
    } on PostgrestException catch (e) {
      developer.log('registerClient', error: e, name: 'QuickAuthService');
      throw QuickAuthException(_rpcMessage(e));
    }
  }

  /// Dossier prestataire (étape finale du stepper). Les fichiers sont déjà
  /// téléversés ; seules leurs URL sont transmises.
  Future<void> registerProvider({
    required String firstName,
    required String lastName,
    required String businessName,
    required String metier,
    required String ville,
    required String ifu,
    required String photoProfilUrl,
    required String photoCniUrl,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _sb.rpc(
        'register_profile',
        params: {
          'p_role': 'provider',
          'p_first_name': firstName.trim(),
          'p_last_name': lastName.trim(),
          'p_photo_profil_url': photoProfilUrl,
          'p_business_name': businessName.trim(),
          'p_metier': metier,
          'p_ville': ville.trim(),
          'p_ifu': ifu.trim(),
          'p_photo_cni_url': photoCniUrl,
          'p_latitude': latitude,
          'p_longitude': longitude,
        },
      );
    } on PostgrestException catch (e) {
      developer.log('registerProvider', error: e, name: 'QuickAuthService');
      throw QuickAuthException(_rpcMessage(e));
    }
  }

  /// Où envoyer l'utilisateur maintenant qu'il est connecté.
  Future<String> nextRoute({String? requestedRole}) async {
    final p = await profileState();
    if (p.complete) {
      return switch (p.role) {
        // L'app conducteur renvoie à son espace, l'app Pro au sien.
        'provider' => AppFlavor.current.homeRoute,
        // L'espace admin n'existe que sur le web (cf. app_router.dart).
        'admin' => kIsWeb ? '/admin/dashboard' : '/home',
        _ => '/home',
      };
    }
    return requestedRole == 'provider'
        ? (AppFlavor.current.isDriver
              ? '/register/driver'
              : '/register/provider')
        : '/register/quick/name';
  }

  // ── Messages ──────────────────────────────────────────────────────────
  String _authMessage(AuthException e) {
    final m = '${e.message} ${e.code ?? ''}'.toLowerCase();
    if (m.contains('rate') || m.contains('too many') || e.statusCode == '429') {
      return 'Trop de tentatives. Patientez une minute avant de réessayer.';
    }
    if (m.contains('expired') || m.contains('invalid')) {
      return 'Code invalide ou expiré.';
    }
    // Fournisseur de connexion (Google, Facebook) non activé dans Supabase.
    if (m.contains('provider is not enabled') ||
        m.contains('unsupported provider')) {
      return 'Ce mode de connexion n\'est pas encore disponible. '
          'Utilisez votre numéro de téléphone.';
    }
    // Aucun service d'envoi de SMS configuré côté Supabase.
    if (m.contains('error sending') ||
        (m.contains('phone') && m.contains('provider')) ||
        m.contains('sms_send_failed') ||
        e.statusCode == '500') {
      return 'L\'envoi du code est momentanément indisponible. '
          'Réessayez dans quelques minutes.';
    }
    if (m.contains('sms')) {
      return 'Le SMS n\'a pas pu être envoyé. Vérifiez le numéro.';
    }
    return 'Connexion impossible. Réessayez.';
  }

  String _rpcMessage(PostgrestException e) {
    final m = e.message;
    if (m.contains('NON_CONNECTE')) return 'Session expirée. Reconnectez-vous.';
    if (m.contains('ROLE_IMMUABLE')) {
      return 'Ce compte est déjà enregistré avec un autre profil.';
    }
    if (m.contains('CHAMPS_OBLIGATOIRES')) {
      return 'Nom de l\'atelier et métier obligatoires.';
    }
    if (m.contains('POSITION_OBLIGATOIRE')) {
      return 'Placez votre atelier sur la carte.';
    }
    if (m.contains('CNI_OBLIGATOIRE')) {
      return 'La pièce d\'identité est obligatoire.';
    }
    return 'Enregistrement impossible. Réessayez.';
  }
}
