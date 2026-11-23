// Persistance de la session Supabase dans le stockage chiffre de l'appareil.
//
// Par defaut, supabase_flutter enregistre le jeton de session dans
// SharedPreferences (non chiffre). Cette implementation remplace ce
// comportement par flutter_secure_storage (Keychain iOS / Keystore Android).
//
// Branche : Supabase.initialize > authOptions > FlutterAuthClientOptions
//           > localStorage: SessionSecuriseeLecture()

import 'dart:developer' as developer;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stockage de session chiffre pour supabase_flutter.
class SessionSecuriseeLecture extends LocalStorage {
  const SessionSecuriseeLecture();

  static const FlutterSecureStorage _stockage = FlutterSecureStorage();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    try {
      return await _stockage.containsKey(key: supabasePersistSessionKey);
    } catch (e) {
      developer.log(
        'Lecture du stockage securise impossible',
        error: e,
        name: 'SessionSecuriseeLecture',
      );
      return false;
    }
  }

  @override
  Future<String?> accessToken() async {
    try {
      return await _stockage.read(key: supabasePersistSessionKey);
    } catch (e) {
      developer.log(
        'Lecture du stockage securise impossible',
        error: e,
        name: 'SessionSecuriseeLecture',
      );
      return null;
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _stockage.write(
        key: supabasePersistSessionKey,
        value: persistSessionString,
      );
    } catch (e) {
      developer.log(
        'Ecriture du stockage securise impossible',
        error: e,
        name: 'SessionSecuriseeLecture',
      );
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _stockage.delete(key: supabasePersistSessionKey);
    } catch (e) {
      developer.log(
        'Suppression du stockage securise impossible',
        error: e,
        name: 'SessionSecuriseeLecture',
      );
    }
  }
}
