import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart' hide MultipartFile;

import 'package:montotem/core/models/app_user.dart';
import 'package:montotem/core/notifications/push_service.dart';
import 'package:montotem/core/offline/outbox_service.dart';
import 'package:montotem/core/storage/local_cache.dart';

enum UploadKind { avatar, identity }

/// Résultat de la première étape d'inscription.
enum SignUpOutcome { phoneOtpSent, emailConfirmationRequired }

/// Resultat de l'inscription email + mot de passe sans telephone (SMS
/// differe, decision produit : le compte se cree par e-mail seul).
enum SignUpSansTelephone { connecte, emailAConfirmer }

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);

  @override
  String toString() => message;
}

class UploadException implements Exception {
  final String message;
  const UploadException(this.message);

  @override
  String toString() => message;
}

/// Authentification + profils, entièrement sur Supabase
/// (tables `profiles` / `providers`, RPC `register_profile`).
class AuthService {
  AuthService();

  SupabaseClient get _sb => Supabase.instance.client;

  /// Taille maximale par bucket (alignée sur storage.buckets).
  static const int _maxAvatarOctets = 5 * 1024 * 1024;
  static const int _maxDocumentOctets = 8 * 1024 * 1024;

  // ===========================================================================
  // INSCRIPTION : email + mot de passe + téléphone
  // ===========================================================================

  /// Crée le compte. Deux issues possibles :
  ///  - [SignUpOutcome.phoneOtpSent] : session ouverte, le SMS de
  ///    vérification est envoyé, écran OTP ;
  ///  - [SignUpOutcome.emailConfirmationRequired] : « Confirm email » est
  ///    activé côté Supabase, l'utilisateur doit d'abord confirmer son
  ///    e-mail, puis [continueSignUpAfterEmailConfirmation].
  Future<SignUpOutcome> signUpWithEmailPasswordPhone({
    required String email,
    required String password,
    required String phone,
  }) async {
    try {
      final signUpRes = await _sb.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
      );

      // E-mail déjà pris : Supabase ne renvoie pas d'erreur (anti-énumération)
      // mais une liste d'identités vide.
      final identities = signUpRes.user?.identities;
      if (identities != null && identities.isEmpty) {
        throw const ApiException(
          'Ce compte existe déjà. Veuillez vous connecter.',
        );
      }

      if (signUpRes.session == null) {
        return SignUpOutcome.emailConfirmationRequired;
      }

      await _sb.auth.updateUser(UserAttributes(phone: normalizePhone(phone)));
      return SignUpOutcome.phoneOtpSent;
    } on AuthException catch (e) {
      throw _mapAuthError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      developer.log(
        'Erreur signUpWithEmailPasswordPhone',
        error: e,
        name: 'AuthService',
      );
      throw const ApiException(
        'Erreur lors de la création du compte. Veuillez réessayer.',
      );
    }
  }

  /// Étape 2 quand l'e-mail devait être confirmé : ouvre la session (ce qui
  /// n'est possible qu'après confirmation) puis déclenche le SMS.
  Future<void> continueSignUpAfterEmailConfirmation({
    required String email,
    required String password,
    required String phone,
  }) async {
    try {
      final res = await _sb.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      if (res.session == null) {
        throw const ApiException(
          'Votre e-mail n\'est pas encore confirmé. Ouvrez le lien reçu '
          'par e-mail, puis réessayez.',
        );
      }
      await _sb.auth.updateUser(UserAttributes(phone: normalizePhone(phone)));
    } on AuthException catch (e) {
      final raw = e.message.toLowerCase();
      if (raw.contains('not confirmed') || e.code == 'email_not_confirmed') {
        throw const ApiException(
          'Votre e-mail n\'est pas encore confirmé. Ouvrez le lien reçu '
          'par e-mail, puis réessayez.',
        );
      }
      if (raw.contains('invalid login')) {
        throw const ApiException(
          'Impossible de vous connecter. Vérifiez votre e-mail et votre '
          'mot de passe.',
        );
      }
      throw _mapAuthError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      developer.log(
        'Erreur continueSignUpAfterEmailConfirmation',
        error: e,
        name: 'AuthService',
      );
      throw const ApiException(
        'Erreur lors de la finalisation du compte. Veuillez réessayer.',
      );
    }
  }

  /// Inscription email + mot de passe SANS telephone (SMS differe).
  /// - [SignUpSansTelephone.connecte] : session ouverte, profil a completer ;
  /// - [SignUpSansTelephone.emailAConfirmer] : « Confirm email » actif cote
  ///   Supabase ; appeler ensuite [connecterApresConfirmationEmail].
  Future<SignUpSansTelephone> inscrireSansTelephone({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _sb.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
      );

      // E-mail deja pris : anti-enumeration, la liste d'identites est vide.
      final identities = res.user?.identities;
      if (identities != null && identities.isEmpty) {
        throw const ApiException(
          'Ce compte existe déjà. Veuillez vous connecter.',
        );
      }

      return res.session == null
          ? SignUpSansTelephone.emailAConfirmer
          : SignUpSansTelephone.connecte;
    } on AuthException catch (e) {
      throw _mapAuthError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      developer.log(
        'Erreur inscrireSansTelephone',
        error: e,
        name: 'AuthService',
      );
      throw const ApiException(
        'Erreur lors de la création du compte. Veuillez réessayer.',
      );
    }
  }

  /// Ouvre la session une fois l'e-mail confirme (aucun telephone requis :
  /// le profil se complete ensuite via /register/client).
  Future<void> connecterApresConfirmationEmail({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _sb.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      if (res.session == null) {
        throw const ApiException(
          'Votre e-mail n\'est pas encore confirmé. Ouvrez le lien reçu par '
          'e-mail, puis réessayez.',
        );
      }
    } on AuthException catch (e) {
      final raw = e.message.toLowerCase();
      if (raw.contains('not confirmed') || e.code == 'email_not_confirmed') {
        throw const ApiException(
          'Votre e-mail n\'est pas encore confirmé. Ouvrez le lien reçu par '
          'e-mail, puis réessayez.',
        );
      }
      if (raw.contains('invalid login')) {
        throw const ApiException(
          'Impossible de vous connecter. Vérifiez votre e-mail et votre '
          'mot de passe.',
        );
      }
      throw _mapAuthError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      developer.log(
        'Erreur connecterApresConfirmationEmail',
        error: e,
        name: 'AuthService',
      );
      throw const ApiException(
        'Erreur lors de la connexion. Veuillez réessayer.',
      );
    }
  }

  /// Renvoie l'e-mail de confirmation d'inscription.
  Future<void> resendSignupEmail(String email) async {
    try {
      await _sb.auth.resend(
        type: OtpType.signup,
        email: email.trim().toLowerCase(),
      );
    } on AuthException catch (e) {
      throw _mapAuthError(e);
    } catch (e) {
      developer.log('Erreur resendSignupEmail', error: e, name: 'AuthService');
      throw const ApiException(
        'Impossible de renvoyer l\'e-mail. Vérifiez votre connexion.',
      );
    }
  }

  /// Vérifie le code OTP reçu par E-MAIL (confirmation d'inscription).
  /// Doit utiliser le même `OtpType` que [resendSignupEmail].
  Future<bool> verifyEmailOtp(String email, String otp) async {
    try {
      final res = await _sb.auth.verifyOTP(
        email: email.trim().toLowerCase(),
        token: otp.trim(),
        type: OtpType.signup,
      );
      return res.session != null;
    } on AuthException catch (e) {
      developer.log('Échec verifyEmailOtp', error: e, name: 'AuthService');
      return false;
    } catch (e) {
      developer.log(
        'Erreur inattendue verifyEmailOtp',
        error: e,
        name: 'AuthService',
      );
      return false;
    }
  }

  /// Renvoie le code à 6 chiffres de confirmation d'inscription.
  Future<void> resendEmailOtp(String email) => resendSignupEmail(email);

  Future<bool> verifyPhoneOtp(String phone, String otp) async {
    final normalized = normalizePhone(phone);
    try {
      final res = await _sb.auth.verifyOTP(
        phone: normalized,
        token: otp.trim(),
        type: OtpType.phoneChange,
      );
      return res.session != null;
    } on AuthException catch (e) {
      developer.log('Échec verifyPhoneOtp', error: e, name: 'AuthService');
      return false;
    } catch (e) {
      developer.log('Erreur inattendue OTP', error: e, name: 'AuthService');
      return false;
    }
  }

  Future<void> resendPhoneOtp(String phone) async {
    try {
      await _sb.auth.updateUser(UserAttributes(phone: normalizePhone(phone)));
    } on AuthException catch (e) {
      throw _mapAuthError(e);
    }
  }

  // ===========================================================================
  // CONNEXION EXISTANTE
  // ===========================================================================

  Future<void> sendOTP(String phoneNumber, {bool creerCompte = true}) async {
    final normalized = normalizePhone(phoneNumber);
    try {
      await _sb.auth.signInWithOtp(
        phone: normalized,
        shouldCreateUser: creerCompte,
      );
    } on AuthException catch (e) {
      throw _mapAuthError(e);
    } catch (e) {
      developer.log('Erreur réseau sendOTP', error: e, name: 'AuthService');
      throw const ApiException(
        'Impossible d\'envoyer le code. Vérifiez votre connexion.',
      );
    }
  }

  Future<bool> verifyOTP(String phoneNumber, String otp) async {
    final normalized = normalizePhone(phoneNumber);
    try {
      final res = await _sb.auth.verifyOTP(
        phone: normalized,
        token: otp.trim(),
        type: OtpType.sms,
      );
      return res.session != null;
    } on AuthException catch (e) {
      developer.log('Échec verifyOTP', error: e, name: 'AuthService');
      return false;
    } catch (e) {
      developer.log('Erreur inattendue OTP', error: e, name: 'AuthService');
      return false;
    }
  }

  Future<bool> signInWithPasswordEmail(String email, String password) async {
    try {
      final res = await _sb.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      return res.session != null;
    } on AuthException catch (e) {
      developer.log(
        'Échec signInWithPasswordEmail: ${e.code} ${e.message}',
        error: e,
        name: 'AuthService',
      );
      if (e.code == 'email_not_confirmed') {
        throw const ApiException(
          'E-mail non confirmé. Ouvrez le lien reçu par e-mail.',
        );
      }
      if (e.code == 'invalid_credentials') {
        throw const ApiException('E-mail ou mot de passe incorrect.');
      }
      throw _mapAuthError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      developer.log(
        'Erreur inattendue signInWithPasswordEmail',
        error: e,
        name: 'AuthService',
      );
      throw const ApiException(
        'Une erreur est survenue lors de la connexion. Veuillez réessayer.',
      );
    }
  }

  // ===========================================================================
  // RESET MOT DE PASSE (utilisateur existant)
  // ===========================================================================

  Future<void> demanderResetMotDePasse(String phoneNumber) async {
    await sendOTP(phoneNumber, creerCompte: false);
  }

  Future<bool> resetMotDePasse({
    required String phoneNumber,
    required String otp,
    required String nouveauMotDePasse,
  }) async {
    final normalized = normalizePhone(phoneNumber);
    try {
      final res = await _sb.auth.verifyOTP(
        phone: normalized,
        token: otp.trim(),
        type: OtpType.sms,
      );
      if (res.session == null) return false;

      await _sb.auth.updateUser(UserAttributes(password: nouveauMotDePasse));
      return true;
    } on AuthException catch (e) {
      developer.log(
        'Échec resetMotDePasse AuthException',
        error: e,
        name: 'AuthService',
      );
      return false;
    } catch (e) {
      developer.log(
        'Échec resetMotDePasse Exception',
        error: e,
        name: 'AuthService',
      );
      return false;
    }
  }

  /// Définit le mot de passe du compte courant. L'e-mail est optionnel.
  Future<void> setPasswordWithEmail({
    String? email,
    required String password,
  }) async {
    try {
      final cleanEmail = (email != null && email.trim().isNotEmpty)
          ? email.trim().toLowerCase()
          : null;

      final response = await _sb.auth.updateUser(
        UserAttributes(email: cleanEmail, password: password),
      );

      if (response.user == null) {
        throw const ApiException(
          'Impossible de mettre à jour le mot de passe.',
        );
      }
    } on AuthException catch (e) {
      developer.log(
        'Échec setPasswordWithEmail AuthException',
        error: e,
        name: 'AuthService',
      );
      throw _mapAuthError(e);
    } on ApiException {
      rethrow;
    } catch (e) {
      developer.log(
        'Échec setPasswordWithEmail Exception',
        error: e,
        name: 'AuthService',
      );
      throw const ApiException('Erreur inattendue lors de la mise à jour.');
    }
  }

  // ===========================================================================
  // Session
  // ===========================================================================
  bool get isAuthenticated => _sb.auth.currentSession != null;
  String? get currentPhone => _sb.auth.currentUser?.phone;
  String? get currentUserId => _sb.auth.currentUser?.id;
  String? get currentEmail => _sb.auth.currentUser?.email;

  Future<void> signOut() async {
    try {
      await PushService.instance.desinscrire();
    } catch (e) {
      developer.log(
        'Désinscription push échouée',
        error: e,
        name: 'AuthService',
      );
    }
    try {
      await LocalCache.instance.effacerDonneesUtilisateur();
    } catch (e) {
      developer.log('Nettoyage du cache échoué', error: e, name: 'AuthService');
    }
    try {
      await OutboxService.instance.effacerDonneesUtilisateur();
    } catch (e) {
      developer.log(
        'Vidage de l\'outbox échoué',
        error: e,
        name: 'AuthService',
      );
    }
    await _sb.auth.signOut();
  }

  // ===========================================================================
  // Profil (Supabase : profiles + providers)
  // ===========================================================================

  /// Lit le profil du compte connecté. `null` si aucun profil n'existe.
  Future<AppUser?> fetchCurrentUser() async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final profile = await _sb
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (profile == null) return null;

      Map<String, dynamic>? presta;
      var approuve = false;
      if (profile['role'] == 'provider') {
        final row = await _sb
            .from('providers')
            .select()
            .eq('id', uid)
            .maybeSingle();
        if (row != null) {
          presta = {
            'business_name': row['business_name'],
            'metier': row['metier'],
            'ville': row['ville'],
            'ifu': row['ifu'],
            'photo_cni_url': row['photo_cni_url'],
            'latitude': row['latitude'],
            'longitude': row['longitude'],
          };
          approuve = row['statut_validation'] == 'approved';
        }
      }

      return AppUser.fromJson({
        'id': profile['id'],
        'phone': (profile['phone'] as String?) ?? '',
        'role': profile['role'],
        'inscription_complete': profile['inscription_complete'] ?? false,
        'first_name': profile['first_name'],
        'last_name': profile['last_name'],
        'is_approved': approuve,
        'photo_profil_url': profile['photo_profil_url'],
        'prestataire': presta,
      });
    } on PostgrestException catch (e) {
      developer.log('fetchCurrentUser échec', error: e, name: 'AuthService');
      throw const ApiException(
        'Impossible de récupérer votre profil. Vérifiez votre connexion.',
      );
    } catch (e) {
      developer.log(
        'fetchCurrentUser erreur inattendue',
        error: e,
        name: 'AuthService',
      );
      throw const ApiException(
        'Une erreur est survenue lors de la récupération du profil.',
      );
    }
  }

  /// Enregistre le formulaire d'inscription (client ou prestataire) en base.
  /// Pour un prestataire, l'administrateur est notifié automatiquement.
  Future<AppUser?> creerProfil({
    required UserRole role,
    String? nom,
    String? prenom,
    String? email,
    String? phone,
    String? metier,
    String? ville,
    String? businessName,
    String? ifu,
    String? photoProfilUrl,
    String? photoCniUrl,
    double? latitude,
    double? longitude,
  }) async {
    try {
      await _sb.rpc(
        'register_profile',
        params: {
          'p_role': role.value,
          'p_first_name': prenom,
          'p_last_name': nom,
          'p_email': email,
          'p_phone': phone != null ? normalizePhone(phone) : null,
          'p_photo_profil_url': photoProfilUrl,
          'p_business_name': businessName,
          'p_metier': metier,
          'p_ville': ville,
          'p_ifu': ifu,
          'p_photo_cni_url': photoCniUrl,
          'p_latitude': latitude,
          'p_longitude': longitude,
        },
      );
      return await fetchCurrentUser();
    } on PostgrestException catch (e) {
      developer.log('Erreur creerProfil', error: e, name: 'AuthService');
      throw ApiException(_messageRpc(e));
    } on ApiException {
      rethrow;
    } catch (e) {
      developer.log(
        'Erreur inattendue creerProfil',
        error: e,
        name: 'AuthService',
      );
      throw const ApiException(
        'Une erreur est survenue lors de la création du profil.',
      );
    }
  }

  // ===========================================================================
  // UPLOAD Supabase Storage
  //   avatars   : bucket public (photo de profil, visage, garage)
  //   documents : bucket privé (pièces d'identité)
  // Le chemin commence toujours par [folder/]<uid>/ : exigé par la RLS.
  // Sécurité (audit) : pour les documents, on renvoie le CHEMIN Storage et
  // jamais une URL signée longue durée — l'URL signée (15 minutes maximum)
  // est générée à la demande, à l'affichage, par un appelant autorisé par
  // la RLS (propriétaire ou admin).
  // ===========================================================================
  Future<String> uploaderDocument(
    Uint8List bytes,
    String nomFichier, {
    required UploadKind kind,
    String? folder,
  }) async {
    try {
      final limite = kind == UploadKind.identity
          ? _maxDocumentOctets
          : _maxAvatarOctets;
      if (bytes.isEmpty) {
        throw const UploadException('Le fichier est vide. Reprenez la photo.');
      }
      if (bytes.length > limite) {
        throw UploadException(
          'Fichier trop volumineux (maximum ${limite ~/ (1024 * 1024)} Mo).',
        );
      }

      try {
        await _sb.auth.refreshSession();
      } catch (_) {}

      final userId = _sb.auth.currentUser?.id;
      if (userId == null) {
        throw const UploadException(
          'Session expirée. Reconnectez-vous avant d\'envoyer un document.',
        );
      }

      final bucket = kind == UploadKind.identity ? 'documents' : 'avatars';
      final cleanName = nomFichier.replaceAll(RegExp(r'[^\w\.\-]'), '_');
      // Anti-traversal : aucun composant du chemin ne doit contenir ..
      if (cleanName.contains('..')) {
        throw const UploadException('Nom de fichier invalide.');
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final prefix = (folder != null && folder.trim().isNotEmpty)
          ? '${folder.trim()}/'
          : '';
      final path = '$prefix$userId/${timestamp}_$cleanName';

      await _sb.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: false,
              contentType: _contentType(nomFichier),
            ),
          );

      // Documents privés : chemin seul (URL signée courte générée à la
      // demande). Avatars : URL publique.
      if (bucket == 'documents') {
        return path;
      }

      return _sb.storage.from(bucket).getPublicUrl(path);
    } on UploadException {
      rethrow;
    } on StorageException catch (e) {
      final hint = (e.statusCode == '403' || e.statusCode == '401')
          ? ' (accès refusé : reconnectez-vous puis réessayez)'
          : '';
      developer.log('StorageException upload', error: e, name: 'AuthService');
      throw UploadException('Erreur de stockage : ${e.message}$hint');
    } catch (e) {
      developer.log(
        'Exception inattendue upload',
        error: e,
        name: 'AuthService',
      );
      throw const UploadException('Échec de l\'envoi du fichier.');
    }
  }

  String _contentType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'image/jpeg';
  }

  // ===========================================================================
  // Administrateur (compte Supabase dont profiles.role = 'admin')
  // ===========================================================================

  /// Connexion admin par e-mail + mot de passe. Un compte qui n'est pas admin
  /// est immédiatement déconnecté et refusé.
  Future<bool> signInAdmin(String email, String password) async {
    try {
      final res = await _sb.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      if (res.session == null) return false;

      if (await isAdminLoggedIn) return true;

      await _sb.auth.signOut();
      return false;
    } on AuthException catch (e) {
      developer.log('Échec connexion admin', error: e, name: 'AuthService');
      return false;
    }
  }

  Future<bool> get isAdminLoggedIn async {
    if (!isAuthenticated) return false;
    try {
      final result = await _sb.rpc('is_admin');
      return result == true;
    } catch (e) {
      developer.log(
        'Vérification admin impossible',
        error: e,
        name: 'AuthService',
      );
      return false;
    }
  }

  Future<void> signOutAdmin() => signOut();

  /// Change l'e-mail (ancien « pseudo ») et/ou le mot de passe de l'admin.
  /// Le mot de passe actuel est revérifié avant toute modification.
  Future<bool> changerIdentifiantsAdmin({
    required String motDePasseActuel,
    String? nouveauPseudo,
    String? nouveauMotDePasse,
  }) async {
    try {
      final emailActuel = currentEmail;
      if (emailActuel == null) return false;

      await _sb.auth.signInWithPassword(
        email: emailActuel,
        password: motDePasseActuel,
      );

      final nouvelEmail = nouveauPseudo?.trim().toLowerCase();
      final nouveauMdp = nouveauMotDePasse?.trim();
      final aEmail = nouvelEmail != null && nouvelEmail.isNotEmpty;
      final aMdp = nouveauMdp != null && nouveauMdp.isNotEmpty;
      if (!aEmail && !aMdp) return true;

      await _sb.auth.updateUser(
        UserAttributes(
          email: aEmail ? nouvelEmail : null,
          password: aMdp ? nouveauMdp : null,
        ),
      );
      return true;
    } catch (e) {
      developer.log(
        'Échec changement identifiants admin',
        error: e,
        name: 'AuthService',
      );
      return false;
    }
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  /// Met un numéro au format international E.164.
  static String normalizePhone(String p) {
    final cleaned = p.trim().replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return '';

    var digits = cleaned.startsWith('+')
        ? cleaned.substring(1).replaceAll('+', '')
        : cleaned.replaceAll('+', '');

    if (cleaned.startsWith('+')) {
      if (digits.startsWith('229') && digits.length == 11) {
        digits = '22901${digits.substring(3)}';
      }
      return '+$digits';
    }

    if (digits.startsWith('00')) {
      return normalizePhone('+${digits.substring(2)}');
    }
    if (digits.startsWith('229')) {
      return normalizePhone('+$digits');
    }
    if (digits.length == 10 && digits.startsWith('01')) return '+229$digits';
    if (digits.length == 8) return '+22901$digits';
    return '+$digits';
  }

  /// Vérifie un numéro déjà passé par [normalizePhone].
  static bool isValidPhone(String normalized) {
    if (!RegExp(r'^\+\d{8,15}$').hasMatch(normalized)) return false;
    if (normalized.startsWith('+229')) {
      return RegExp(r'^\+229\d{10}$').hasMatch(normalized);
    }
    return true;
  }

  /// En debug, ajoute le code Supabase brut au message pour localiser la panne.
  ApiException _mapAuthError(AuthException e) {
    final mapped = _mapAuthErrorCore(e);
    if (!kDebugMode) return mapped;
    final code = _codeOf(e);
    final detail =
        'status=${e.statusCode} code=${code.isEmpty ? '-' : code} msg=${e.message}';
    debugPrint('[AuthService] AuthException $detail');
    return ApiException('${mapped.message}\n[debug]$detail');
  }

  ApiException _mapAuthErrorCore(AuthException e) {
    final lower = e.message.toLowerCase();
    if (lower.contains('rate') || lower.contains('too many')) {
      return const ApiException(
        'Trop de tentatives. Veuillez réessayer dans quelques minutes.',
      );
    }
    if (lower.contains('invalid')) {
      return const ApiException('Informations fournies invalides.');
    }
    if (lower.contains('password')) {
      return const ApiException(
        'Le mot de passe doit contenir au moins 6 caractères.',
      );
    }
    if (lower.contains('already registered') ||
        lower.contains('already exists') ||
        lower.contains('already been registered')) {
      return const ApiException(
        'Ce compte existe déjà. Veuillez vous connecter.',
      );
    }
    if (lower.contains('phone')) {
      return const ApiException(
        'Numéro de téléphone invalide ou déjà associé à un autre compte.',
      );
    }
    return ApiException(e.message);
  }

  String _codeOf(AuthException e) {
    return e.code ?? e.statusCode.toString();
  }

  /// Traduit les erreurs levées par les fonctions SQL (`raise exception '…'`).
  String _messageRpc(PostgrestException e) {
    final msg = e.message;
    if (msg.contains('NON_CONNECTE')) {
      return 'Votre session a expiré. Veuillez vous reconnecter.';
    }
    if (msg.contains('CHAMPS_OBLIGATOIRES')) {
      return 'Le nom du garage et le métier sont obligatoires.';
    }
    if (msg.contains('POSITION_OBLIGATOIRE')) {
      return 'Merci de placer votre garage sur la carte.';
    }
    if (msg.contains('CNI_OBLIGATOIRE')) {
      return 'La pièce d\'identité est obligatoire.';
    }
    if (msg.contains('ROLE_IMMUABLE')) {
      return 'Ce compte est déjà enregistré avec un autre profil.';
    }
    if (msg.contains('ROLE_INVALIDE')) {
      return 'Ce type de compte ne peut pas être créé ici.';
    }
    return 'Impossible d\'enregistrer votre inscription. Réessayez.';
  }
}
