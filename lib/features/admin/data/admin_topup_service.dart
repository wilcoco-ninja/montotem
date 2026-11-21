import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Recharges de wallet déclarées par les prestataires (côté administrateur).
/// La sécurité repose sur la RLS et sur les RPC `admin_*` (is_admin()).
class AdminTopupService {
  SupabaseClient get _sb => Supabase.instance.client;

  Future<List<Map<String, dynamic>>> lister({String? statut}) async {
    try {
      var requete = _sb.from('wallet_topup_requests').select(
            '*, providers(business_name, metier, ville, '
            'profiles!providers_id_fkey(first_name, last_name, phone))',
          );
      if (statut != null) {
        requete = requete.eq('statut', statut);
      }
      final rows =
          await requete.order('created_at', ascending: false).limit(200);
      return rows
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();
    } on PostgrestException catch (e) {
      developer.log('Recharges admin', error: e, name: 'AdminTopupService');
      throw Exception('Impossible de charger les recharges.');
    }
  }

  Future<void> valider(String id) => _revoir(id, approuver: true);

  Future<void> refuser(String id, String motif) =>
      _revoir(id, approuver: false, motif: motif);

  Future<void> _revoir(
    String id, {
    required bool approuver,
    String? motif,
  }) async {
    try {
      await _sb.rpc('admin_review_wallet_topup', params: {
        'p_request_id': id,
        'p_approve': approuver,
        'p_reason': motif,
      });
    } on PostgrestException catch (e) {
      developer.log('Revue recharge', error: e, name: 'AdminTopupService');
      throw Exception(_msg(e));
    }
  }

  RealtimeChannel ecouter(void Function() onChange) {
    final canal = _sb.channel('admin-wallet-topups');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallet_topup_requests',
          callback: (_) => onChange(),
        )
        .subscribe();
    return canal;
  }

  Future<void> arreter(RealtimeChannel canal) async {
    try {
      await _sb.removeChannel(canal);
    } catch (_) {}
  }

  String _msg(PostgrestException e) {
    final m = e.message;
    if (m.contains('INTERDIT')) return 'Action réservée à l\'administrateur.';
    if (m.contains('DEJA_TRAITEE')) return 'Cette demande a déjà été traitée.';
    if (m.contains('INTROUVABLE')) return 'Demande ou prestataire introuvable.';
    if (m.contains('MOTIF_OBLIGATOIRE')) return 'Un motif est obligatoire.';
    if (m.contains('MONTANT_INVALIDE')) return 'Montant invalide.';
    if (e.code == '23505' || m.contains('duplicate key')) {
      return 'Cette référence a déjà été créditée.';
    }
    return 'Serveur injoignable ou opération refusée.';
  }
}
