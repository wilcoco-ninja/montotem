import 'dart:developer' as developer;

import 'package:hive_flutter/hive_flutter.dart';

/// Cache local clé/valeur (Hive) pour le mode hors ligne.
/// Ne contient que des données de l'utilisateur connecté : il est vidé à la
/// déconnexion. Toute erreur de lecture/écriture est silencieuse : le cache
/// ne doit jamais faire échouer l'application.
class LocalCache {
  LocalCache._();

  static final LocalCache instance = LocalCache._();

  static const String _nomBoite = 'montotem_cache';

  Box<String>? _boite;

  bool get pret => _boite != null && _boite!.isOpen;

  Future<void> init() async {
    if (pret) return;
    await Hive.initFlutter();
    _boite = await Hive.openBox<String>(_nomBoite);
  }

  String? lire(String cle) {
    try {
      return pret ? _boite!.get(cle) : null;
    } catch (e) {
      developer.log('Lecture cache $cle', error: e, name: 'LocalCache');
      return null;
    }
  }

  Future<void> ecrire(String cle, String valeur) async {
    try {
      if (pret) await _boite!.put(cle, valeur);
    } catch (e) {
      developer.log('Écriture cache $cle', error: e, name: 'LocalCache');
    }
  }

  Future<void> supprimer(String cle) async {
    try {
      if (pret) await _boite!.delete(cle);
    } catch (e) {
      developer.log('Suppression cache $cle', error: e, name: 'LocalCache');
    }
  }

  /// À appeler à la déconnexion : aucune donnée d'un compte ne doit rester
  /// lisible par le suivant sur le même téléphone.
  Future<void> effacerDonneesUtilisateur() async {
    try {
      if (pret) await _boite!.clear();
    } catch (e) {
      developer.log('Vidage du cache', error: e, name: 'LocalCache');
    }
  }
}
