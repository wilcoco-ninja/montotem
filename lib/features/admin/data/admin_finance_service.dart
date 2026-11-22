import 'package:supabase_flutter/supabase_flutter.dart';

/// Pilotage finance cote administrateur : devises, zones, regles de
/// commission, plafond de dette cash (app_config) et grand livre
/// append-only.
///
/// Les ecritures et les reglages sensibles passent par des FONCTIONS RPC
/// securisees (garde `is_admin()`) :
///   - `admin_list_commission_rules` / `admin_upsert_commission_rule` /
///     `admin_delete_commission_rule` / `admin_commission_summary`
///     (script 043 - si absent, repli sur une lecture directe pour ne
///     jamais vider l'onglet Commissions) ;
///   - `admin_set_config` / `admin_ajuster_ledger` (script 14 - si absent,
///     l'erreur indique clairement le script a executer dans Supabase).
///
/// Les montants restent en unites mineures entieres (bigint cote
/// PostgreSQL, int cote Dart) : jamais de double flottant.
class AdminFinanceService {
  SupabaseClient get _sb => Supabase.instance.client;

  List<Map<String, dynamic>> _liste(dynamic rows) => (rows as List)
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  // -- DEVISES ET ZONES ------------------------------------------------------

  /// Referentiel des devises (script finance/11) : code, libelle,
  /// minor_units (0 ou 2), rounding_mode, symbole.
  Future<List<Map<String, dynamic>>> listerDevises() async {
    try {
      return _liste(
        await _sb.from('devises').select().order('position'),
      );
    } on PostgrestException catch (e) {
      throw Exception('Devises indisponibles : ${e.message}');
    }
  }

  /// Zones de service : pays / ville(s) -> devise_code (script finance/11).
  Future<List<Map<String, dynamic>>> listerZones() async {
    try {
      return _liste(
        await _sb.from('zones').select().order('code'),
      );
    } on PostgrestException catch (e) {
      throw Exception('Zones indisponibles : ${e.message}');
    }
  }

  // -- REGLES DE COMMISSION (script 043) -------------------------------------

  /// Toutes les regles de commission (RPC 043). Repli lecture directe si la
  /// fonction n'est pas deploree, pour ne jamais vider l'onglet.
  Future<List<Map<String, dynamic>>> listerReglesCommission() async {
    try {
      final data = await _sb.rpc('admin_list_commission_rules');
      return _liste(data);
    } on PostgrestException catch (e) {
      if (e.code == '42883' || e.code == 'PGRST202') {
        try {
          return _liste(
            await _sb
                .from('commission_rules')
                .select()
                .order('service_category')
                .order('provider_kind'),
          );
        } on PostgrestException catch (e2) {
          throw Exception(
            'Regles indisponibles : executez le script 043 '
            '(043_fn_admin_commission.sql) dans Supabase. (${e2.message})',
          );
        }
      }
      throw Exception('Regles de commission indisponibles : ${e.message}');
    }
  }

  /// Resume des taux en vigueur par categorie (RPC 043). Repli : carte vide,
  /// l'onglet Commissions reste utilisable avec la liste brute.
  Future<Map<String, dynamic>> resumeCommission() async {
    try {
      final data = await _sb.rpc('admin_commission_summary');
      return Map<String, dynamic>.from(data as Map);
    } on PostgrestException catch (e) {
      if (e.code == '42883' || e.code == 'PGRST202') return <String, dynamic>{};
      throw Exception('Resume commissions indisponible : ${e.message}');
    }
  }

  /// Cree ou met a jour une regle de commission (RPC 043).
  Future<void> enregistrerRegle({
    String? id,
    required String serviceCategory,
    required int pct,
    required bool actif,
    String? providerKind,
    String? vehicleType,
    String? note,
  }) async {
    try {
      await _sb.rpc('admin_upsert_commission_rule', params: {
        'p_id': id,
        'p_service_category': serviceCategory,
        'p_provider_kind': providerKind,
        'p_vehicle_type': vehicleType,
        'p_pct': pct,
        'p_actif': actif,
        'p_note': note,
      });
    } on PostgrestException catch (e) {
      if (e.code == '42883' || e.code == 'PGRST202') {
        throw Exception(
          'RPC admin_upsert_commission_rule introuvable : executez le '
          'script 043 dans Supabase puis reessayez.',
        );
      }
      throw Exception(_msgRegle(e));
    }
  }

  /// Supprime une regle de commission (RPC 043).
  Future<void> supprimerRegle(String id) async {
    try {
      await _sb.rpc('admin_delete_commission_rule', params: {
        'p_id': id,
      });
    } on PostgrestException catch (e) {
      if (e.code == '42883' || e.code == 'PGRST202') {
        throw Exception(
          'RPC admin_delete_commission_rule introuvable : executez le '
          'script 043 dans Supabase puis reessayez.',
        );
      }
      throw Exception(_msgRegle(e));
    }
  }

  String _msgRegle(PostgrestException e) {
    final m = e.message;
    if (m.contains('INTERDIT')) return 'Reserve a un compte administrateur.';
    if (m.contains('PCT_INVALIDE')) return 'Pourcentage invalide (0 a 100).';
    if (m.contains('SERVICE_INVALIDE')) {
      return 'Categorie de service inconnue du referentiel.';
    }
    return 'Operation impossible : $m';
  }

  // -- CONFIG (plafond dette cash, seuil de blocage) -------------------------

  /// Lecture des cles entieres d'app_config (sans RLS : lecture accessible).
  Future<Map<String, int>> chargerConfigCles(List<String> cles) async {
    try {
      final rows = await _sb
          .from('app_config')
          .select('key, value_int')
          .inFilter('key', cles);
      return {
        for (final r in _liste(rows))
          '${r['key']}': ((r['value_int'] as num?)?.toInt() ?? 0),
      };
    } on PostgrestException catch (e) {
      throw Exception('Configuration indisponible : ${e.message}');
    }
  }

  /// Ecrit une cle entiere d'app_config via `admin_set_config` (script 14).
  /// Repli : upsert direct (app_config n'a pas de RLS, mais la borne
  /// is_admin() du RPC reste preferenciale).
  Future<void> definirConfigInt(
    String cle,
    int valeur, {
    String? note,
  }) async {
    try {
      await _sb.rpc('admin_set_config', params: {
        'p_key': cle,
        'p_value_int': valeur,
        'p_note': note,
      });
    } on PostgrestException catch (e) {
      if (e.code == '42883' || e.code == 'PGRST202') {
        try {
          await _sb.from('app_config').upsert({
            'key': cle,
            'value_int': valeur,
            if (note != null) 'note': note,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
        } on PostgrestException catch (e2) {
          throw Exception(
            'Ecriture impossible (RPC admin_set_config absent, script 14) : '
            '${e2.message}',
          );
        }
      } else {
        throw Exception('Ecriture impossible : ${_msgConfig(e)}');
      }
    }
  }

  String _msgConfig(PostgrestException e) {
    final m = e.message;
    if (m.contains('INTERDIT')) return 'Reserve a un compte administrateur.';
    if (m.contains('CLE_INVALIDE')) return 'Cle de configuration invalide.';
    if (m.contains('VALEUR_INVALIDE') || m.contains('VALEUR_TROP_HAUTE')) {
      return 'Valeur refusee par le serveur (borne de securite).';
    }
    return m;
  }

  // -- GRAND LIVRE (litiges, ajustements admin) ------------------------------

  /// Dernieres ecritures du grand livre (tous prestataires, RLS admin).
  Future<List<Map<String, dynamic>>> chargerLedger({int limite = 300}) async {
    try {
      return _liste(
        await _sb
            .from('ledger_entries')
            .select('*, provider:providers(business_name, metier)')
            .order('id', ascending: false)
            .limit(limite),
      );
    } on PostgrestException catch (e) {
      if (_estRelationCasse(e)) {
        try {
          return _liste(
            await _sb
                .from('ledger_entries')
                .select()
                .order('id', ascending: false)
                .limit(limite),
          );
        } on PostgrestException catch (_) {}
      }
      throw Exception('Grand livre indisponible : ${e.message}');
    }
  }

  /// Liste legere des prestataires pour le dialogue d'ajustement.
  Future<List<Map<String, dynamic>>> listerPrestataires() async {
    try {
      return _liste(
        await _sb
            .from('providers')
            .select('id, business_name, metier, ville')
            .order('business_name')
            .limit(300),
      );
    } on PostgrestException catch (e) {
      throw Exception('Prestataires indisponibles : ${e.message}');
    }
  }

  /// Ajustement manuel du grand livre (script 14) : credit (> 0) ou debit
  /// (< 0) de la poche Mobile Money, genre `ajustement` ou `remboursement`.
  /// Le serveur recalcule payable_after / debt_after et verifie l'idempotence
  /// via client_request_id (anti double-clic).
  Future<void> ajusterLedger({
    required String providerId,
    required String deviseCode,
    required int montantMinor,
    required String kind,
    required String clientRequestId,
    String? note,
  }) async {
    try {
      await _sb.rpc('admin_ajuster_ledger', params: {
        'p_provider': providerId,
        'p_devise': deviseCode,
        'p_montant_minor': montantMinor,
        'p_kind': kind,
        'p_note': note,
        'p_client_request_id': clientRequestId,
      });
    } on PostgrestException catch (e) {
      if (e.code == '42883' || e.code == 'PGRST202') {
        throw Exception(
          'RPC admin_ajuster_ledger introuvable : executez le script 14 '
          '(pilotage admin) dans Supabase puis reessayez.',
        );
      }
      throw Exception(_msgLedger(e));
    }
  }

  String _msgLedger(PostgrestException e) {
    final m = e.message;
    if (m.contains('INTERDIT')) return 'Reserve a un compte administrateur.';
    if (m.contains('DOUBLON')) {
      return 'Ecriture deja enregistree (identifiant double).';
    }
    if (m.contains('GENRE_INVALIDE')) {
      return 'Seuls les genres ajustement et remboursement sont admis.';
    }
    if (m.contains('MONTANT_INVALIDE')) {
      return 'Montant hors bornes admises.';
    }
    if (m.contains('DEVISE_INVALIDE')) {
      return 'Devise inconnue du referentiel.';
    }
    if (m.contains('INTROUVABLE')) {
      return 'Prestataire ou wallet introuvable.';
    }
    return 'Operation impossible : $m';
  }

  bool _estRelationCasse(PostgrestException e) =>
      e.code == 'PGRST200' ||
      e.code == 'PGRST116' ||
      e.message.toLowerCase().contains('relationship') ||
      e.message.toLowerCase().contains('foreign key');
}
