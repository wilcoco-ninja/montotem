import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tracking/domain/prestataire_model.dart';

/// Erreur lisible renvoyée à l'interface (le détail technique va dans les logs).
class MatchingException implements Exception {
  const MatchingException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Prestataires visibles sur la carte, lus depuis Supabase
/// (fonction SQL `providers_nearby` : uniquement les prestataires validés
/// par l'administrateur et dont l'abonnement est actif).
class MatchingService {
  MatchingService();

  SupabaseClient get _sb => Supabase.instance.client;

  Future<List<Prestataire>> trouverPrestatairesProches(
    double latitude,
    double longitude,
    double distanceMaxKm,
  ) async {
    final List<Prestataire> tous = await _fetchPrestataires();

    final List<Prestataire> proches = tous.where((p) {
      final double dist = Geolocator.distanceBetween(
        latitude,
        longitude,
        p.latitude,
        p.longitude,
      );
      return p.disponible && dist <= distanceMaxKm * 1000;
    }).toList()
      ..sort((a, b) => b.noteMoyenne.compareTo(a.noteMoyenne));

    return proches;
  }

  /// Utilisé par l'accueil (carte globale) : tous les prestataires visibles,
  /// disponibles ou non, sans filtre de distance.
  Future<List<Prestataire>> obtenirTousLesPrestataires() {
    return _fetchPrestataires();
  }

  /// Carte d'ouverture de l'application.
  ///
  /// - Connecté : fiches complètes (`providers_nearby`).
  /// - Visiteur : points anonymes (`providers_map_public`) — position, type et
  ///   disponibilité seulement. Nom, photo, téléphone, adresse et note restent
  ///   cachés tant que le visiteur n'a pas de compte.
  Future<List<Prestataire>> obtenirPourCarte() async {
    if (_sb.auth.currentSession != null) return _fetchPrestataires();

    try {
      final dynamic data = await _sb.rpc('providers_map_public');
      if (data is List) {
        return data
            .whereType<Map<dynamic, dynamic>>()
            .map((raw) => _anonymiser(_depuisLigne(Map<String, dynamic>.from(raw))))
            .toList();
      }
    } on PostgrestException catch (e, stackTrace) {
      // Migration 07 pas encore appliquée : repli sur la liste complète, mais
      // les champs privés sont retirés côté application.
      _journaliser(
        'providers_map_public -> code=${e.code} message=${e.message}',
        e,
        stackTrace,
      );
    } catch (e, stackTrace) {
      _journaliser('providers_map_public inattendu : $e', e, stackTrace);
    }

    final tous = await _fetchPrestataires();
    return tous.map(_anonymiser).toList();
  }

  /// Ne garde que ce qu'un visiteur a le droit de voir.
  Prestataire _anonymiser(Prestataire p) => Prestataire(
        id: p.id,
        nom: '',
        metier: p.metier,
        latitude: p.latitude,
        longitude: p.longitude,
        disponible: p.disponible,
        verifie: p.verifie,
        kind: p.kind,
      );

  Future<List<Prestataire>> _fetchPrestataires() async {
    try {
      final dynamic data = await _sb.rpc('providers_nearby');
      if (data is! List) return const <Prestataire>[];
      return data
          .whereType<Map<dynamic, dynamic>>()
          .map((raw) => _depuisLigne(Map<String, dynamic>.from(raw)))
          .toList();
    } on PostgrestException catch (e, stackTrace) {
      // `error: e` s'affiche « {} » sur le web : on écrit le détail en clair.
      _journaliser(
        'providers_nearby -> code=${e.code} message=${e.message} '
        'details=${e.details} hint=${e.hint}',
        e,
        stackTrace,
      );
      throw MatchingException(_messagePour(e));
    } on MatchingException {
      rethrow;
    } catch (e, stackTrace) {
      _journaliser('fetchPrestataires inattendu : $e', e, stackTrace);
      throw const MatchingException(
        'Impossible de récupérer la liste des prestataires. '
        'Vérifiez votre connexion.',
      );
    }
  }

  /// Message adapté à la cause, sans jargon technique pour l'utilisateur.
  String _messagePour(PostgrestException e) {
    final String code = e.code ?? '';
    // 42883 : fonction absente ; 42703 : colonne absente ; PGRST202 : RPC
    // introuvable dans le cache de schéma. Dans ces cas, le problème vient
    // de la base (migration non appliquée), pas de la connexion.
    if (code == '42883' || code == '42703' || code == 'PGRST202') {
      return 'La liste des prestataires est momentanément indisponible. '
          'Réessayez dans quelques minutes.';
    }
    return 'Impossible de récupérer la liste des prestataires. '
        'Vérifiez votre connexion.';
  }

  void _journaliser(String texte, Object erreur, StackTrace pile) {
    debugPrint('[MatchingService] $texte');
    developer.log(
      texte,
      error: erreur.toString(),
      stackTrace: pile,
      name: 'MatchingService',
    );
  }

  Prestataire _depuisLigne(Map<String, dynamic> m) {
    return Prestataire(
      id: '${m['id']}',
      nom: (m['nom'] as String?) ?? 'Prestataire',
      metier: (m['metier'] as String?) ?? '',
      latitude: (m['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (m['longitude'] as num?)?.toDouble() ?? 0.0,
      telephone: m['telephone'] as String?,
      photoUrl: m['photo_url'] as String?,
      kind: m['provider_kind'] as String?,
      businessName: m['business_name'] as String?,
      adresse: m['adresse'] as String?,
      verifie: (m['verifie'] as bool?) ?? false,
      disponible: (m['disponible'] as bool?) ?? false,
      noteMoyenne: (m['note_moyenne'] as num?)?.toDouble() ?? 0.0,
      clientsSatisfaits: (m['clients_satisfaits'] as num?)?.toInt() ?? 0,
      clientsInsatisfaits: (m['clients_insatisfaits'] as num?)?.toInt() ?? 0,
      missionsCompletees: (m['missions_completees'] as num?)?.toInt() ?? 0,
      statutMission: m['statut_mission'] as String?,
      finAbonnement: m['fin_abonnement'] != null
          ? DateTime.tryParse('${m['fin_abonnement']}')
          : null,
    );
  }
}