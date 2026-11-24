import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// File d'attente hors ligne (outbox) pour le reseau mobile instable (3G).
///
/// Principe : quand le client soumet une demande (course, SOS depannage) sans
/// reseau, la demande est rangee localement dans une boite Hive et rejouee
/// automatiquement des que la connexion revient. Chaque demande porte une
/// reference unique [clientRequestId] posee a l'enregistrement, reutilisable
/// pour l'anti-redoublon cote serveur.
///
/// Antiredoublon cote client : le rejeu n'est declenche QUE si la premiere
/// tentative n'a jamais quitte le telephone (reseau absent avant l'appel).
/// Un echec en pleine conversation serveur reste une erreur visible, jamais
/// mise en file : aucune demande ne peut ainsi etre jouee deux fois.
///
/// Contrat des handlers enregistres via [enregistrerHandler] :
/// - le handler execute la soumission reelle puis retourne `true` (tache
///   consommee) ;
/// - en cas d'echec metier definitif (refus serveur explicite, ex.
///   COURSE_EN_COURS), le handler retourne `false` : la tache est retiree,
///   jamais rejouee ;
/// - en cas de coupure en pleine conversation, le handler leve une exception
///   : la tache est conservee et reessaiee avec delai exponentiel.
class OutboxService {
  OutboxService._();

  static final OutboxService instance = OutboxService._();

  static const String _nomBoite = 'montotem_outbox';

  /// Au-dela de 6 tentatives reseau echouees, la tache devient consultable
  /// mais n'est plus rejouee seule : elle evitera de peser sans fin sur la
  /// batterie et les donnees mobiles.
  static const int _essaisMax = 6;

  static int _aleatoire = 0;

  Box<String>? _boite;
  StreamSubscription<dynamic>? _reseauSouscription;
  final Map<String, Future<bool> Function(Map<String, dynamic>)> _handlers =
      <String, Future<bool> Function(Map<String, dynamic>)>{};
  final StreamController<int> _compteur = StreamController<int>.broadcast();

  bool get pret => _boite != null && _boite!.isOpen;

  bool get ecouteActive => _reseauSouscription != null;

  Future<void> init() async {
    if (pret) return;
    try {
      await Hive.initFlutter();
      _boite = await Hive.openBox<String>(_nomBoite);
    } catch (e) {
      developer.log('Ouverture boite outbox', error: e, name: 'OutboxService');
    }
    _publier();
  }

  /// Enregistre le handler qui sait rejouer [kind].
  /// A appeler apres [init] (composition racine, main.dart).
  void enregistrerHandler(
    String kind,
    Future<bool> Function(Map<String, dynamic> payload) handler,
  ) {
    _handlers[kind] = handler;
  }

  /// Reference unique pour une demande en file (anti-redoublon).
  static String nouvelleReference(String prefixe) {
    _aleatoire++;
    final suffixe = _aleatoire % 10000;
    return '$prefixe-${DateTime.now().millisecondsSinceEpoch}-$suffixe';
  }

  /// Met une demande en file. Ecrase sans douleur une entree de meme
  /// reference (nouvelle tentative de la meme demande).
  Future<void> enregistrer({
    required String kind,
    required String clientRequestId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      if (!pret) return;
      final entree = <String, dynamic>{
        'kind': kind,
        'req': clientRequestId,
        'p': payload,
        'cree': DateTime.now().millisecondsSinceEpoch,
        'essais': 0,
        'dernier': 0,
      };
      await _boite!.put(clientRequestId, jsonEncode(entree));
    } catch (e) {
      developer.log('Ajout outbox $kind', error: e, name: 'OutboxService');
    }
    _publier();
  }

  /// Nombre de demandes en attente d'envoi.
  int nombreEnAttente() {
    try {
      return pret ? _boite!.length : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Flux du nombre de demandes en attente (pour les rubans UI).
  Stream<int> get nombreAttenteStream => _compteur.stream;

  /// Rejoue les taches dues. Retourne le nombre de taches consommees.
  /// Deux protections :
  /// - reseau absent : aucun appel (on conserve tout) ;
  /// - delai exponentiel (30 s x 2^essais, plafonne a 10 min).
  Future<int> traiter() async {
    if (!pret || _handlers.isEmpty) return 0;
    if (await reseauIndisponible()) return 0;
    final maintenant = DateTime.now().millisecondsSinceEpoch;
    final dues = <String, Map<String, dynamic>>{};
    try {
      for (final cle in _boite!.keys.cast<String>()) {
        final brut = _boite!.get(cle);
        if (brut == null) continue;
        final e = Map<String, dynamic>.from(jsonDecode(brut) as Map);
        final essais = (e['essais'] as num?)?.toInt() ?? 0;
        if (essais >= _essaisMax) continue;
        final dernier = (e['dernier'] as num?)?.toInt() ?? 0;
        final delaiBase = 30000;
        final facteur = 1 << (essais >= 5 ? 5 : essais);
        final echeance = dernier + delaiBase * facteur;
        if (essais > 0 && maintenant < echeance) continue;
        dues[cle] = e;
      }
    } catch (e) {
      developer.log('Lecture outbox', error: e, name: 'OutboxService');
      return 0;
    }
    var consommees = 0;
    for (final f in dues.entries) {
      final cle = f.key;
      final e = f.value;
      final kind = '${e['kind']}';
      final handler = _handlers[kind];
      if (handler == null) continue;
      final payload = e['p'] is Map
          ? Map<String, dynamic>.from(e['p'] as Map)
          : <String, dynamic>{};
      bool ok;
      try {
        ok = await handler(payload);
      } catch (e) {
        // Echec transitoire (reseau) : conserve, reessaie plus tard.
        developer.log('Rejeu differe $kind', error: e, name: 'OutboxService');
        await _incrementer(cle, e);
        continue;
      }
      if (ok) {
        try {
          await _boite!.delete(cle);
        } catch (_) {}
        consommees++;
      } else {
        // Echec metier definitif : on retire la tache.
        try {
          await _boite!.delete(cle);
        } catch (_) {}
        developer.log(
          'Tache $kind rejettee par le serveur (retiree)',
          name: 'OutboxService',
        );
      }
    }
    _publier();
    return consommees;
  }

  /// Demarre l'ecoute du reseau : chaque retour de connexion declenche le
  /// rejeu (avec un petit delai pour laisser Android finir son basculement).
  /// Un premier rejeu est aussi lance a l'ouverture : les demandes mises en
  /// file pendant une session precedente partent sans attendre un evenement
  /// de connectivite.
  void demarrer() {
    if (ecouteActive) return;
    try {
      _reseauSouscription = Connectivity().onConnectivityChanged
          .map<bool>(_sansReseau)
          .distinct()
          .listen((bool horsLigne) {
            if (!horsLigne) {
              Future<void>.delayed(const Duration(seconds: 2), () {
                traiter();
              });
            }
          });
    } catch (e) {
      developer.log(
        'Ecoute connectivite impossible',
        error: e,
        name: 'OutboxService',
      );
    }
    traiter();
  }

  static bool _sansReseau(dynamic r) {
    if (r is List) return r.every((e) => e == ConnectivityResult.none);
    return r == ConnectivityResult.none;
  }

  /// true quand le telephone n'a aucun reseau de donnees.
  static Future<bool> reseauIndisponible() async {
    try {
      final dynamic r = await Connectivity().checkConnectivity();
      return _sansReseau(r);
    } catch (_) {
      return false;
    }
  }

  Future<void> _incrementer(String cle, Object erreur) async {
    try {
      final brut = _boite!.get(cle);
      if (brut == null) return;
      final e = Map<String, dynamic>.from(jsonDecode(brut) as Map);
      e['essais'] = ((e['essais'] as num?)?.toInt() ?? 0) + 1;
      e['dernier'] = DateTime.now().millisecondsSinceEpoch;
      e['err'] = '$erreur'.length > 200
          ? '$erreur'.substring(0, 200)
          : '$erreur';
      await _boite!.put(cle, jsonEncode(e));
    } catch (e) {
      developer.log('Mise a jour outbox', error: e, name: 'OutboxService');
    }
    _publier();
  }

  void _publier() {
    if (_compteur.isClosed) return;
    _compteur.add(nombreEnAttente());
  }

  /// A appeler a la deconnexion : aucune demande d'un compte ne doit etre
  /// rejouee depuis le compte suivant sur le meme telephone.
  Future<void> effacerDonneesUtilisateur() async {
    try {
      if (pret) await _boite!.clear();
    } catch (e) {
      developer.log('Vidage outbox', error: e, name: 'OutboxService');
    }
    _publier();
  }
}
