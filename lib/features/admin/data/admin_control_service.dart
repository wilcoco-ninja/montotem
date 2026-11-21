import 'package:supabase_flutter/supabase_flutter.dart';

class AdminControlService {
  SupabaseClient get _sb => Supabase.instance.client;

  List<Map<String, dynamic>> _liste(dynamic rows) => (rows as List)
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  // ── MISSIONS ─────────────────────────────────────────────────────────────
  // Tente le join complet ; si la FK est renommée (PGRST200/PGRST116),
  // retombe sur un select simple pour ne JAMAIS vider l'onglet live.
  Future<List<Map<String, dynamic>>> missions() async {
    try {
      final rows = await _sb
          .from('missions')
          .select('*, '
              'client:profiles!missions_client_id_fkey(first_name,last_name,phone), '
              'provider:providers!missions_provider_id_fkey(business_name,metier)')
          .order('created_at', ascending: false)
          .limit(150);
      return _liste(rows);
    } on PostgrestException catch (e) {
      if (_estRelationCasse(e)) {
        try {
          final rows = await _sb
              .from('missions')
              .select()
              .order('created_at', ascending: false)
              .limit(150);
          return _liste(rows);
        } catch (_) {}
      }
      throw Exception('Missions indisponibles : ${e.message}');
    }
  }

  Future<List<Map<String, dynamic>>> recentes({int limite = 5}) async {
    try {
      final rows = await _sb
          .from('missions')
          .select('*, '
              'client:profiles!missions_client_id_fkey(first_name,last_name,phone), '
              'provider:providers!missions_provider_id_fkey(business_name,metier)')
          .order('created_at', ascending: false)
          .limit(limite);
      return _liste(rows);
    } on PostgrestException catch (e) {
      if (_estRelationCasse(e)) {
        return _liste(await _sb
            .from('missions')
            .select()
            .order('created_at', ascending: false)
            .limit(limite));
      }
      rethrow;
    }
  }

  // ── CHRONOLOGIE / MESSAGES / PAIEMENTS ───────────────────────────────────
  Future<List<Map<String, dynamic>>> evenements(String missionId) async =>
      _liste(await _sb
          .from('mission_events')
          .select()
          .eq('mission_id', missionId)
          .order('created_at'));

  Future<List<Map<String, dynamic>>> messages(String missionId) async =>
      _liste(await _sb
          .from('mission_messages')
          .select()
          .eq('mission_id', missionId)
          .order('created_at'));

  Future<List<Map<String, dynamic>>> paiements(String missionId) async =>
      _liste(await _sb
          .from('mission_payments')
          .select()
          .eq('mission_id', missionId)
          .order('created_at'));

  // ── FINANCES ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> finances(int jours) async {
    try {
      final data =
          await _sb.rpc('admin_finance_summary', params: {'p_days': jours});
      return Map<String, dynamic>.from(data as Map);
    } on PostgrestException catch (e) {
      throw Exception('Finances indisponibles : ${e.message}');
    }
  }

  // ── SIGNALEMENTS ─────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> signalements() async {
    try {
      final rows = await _sb
          .from('provider_reports')
          .select('*, '
              'reporter:profiles!provider_reports_reporter_id_fkey(first_name,last_name,phone), '
              'provider:providers!provider_reports_provider_id_fkey(business_name,metier)')
          .order('created_at', ascending: false)
          .limit(100);
      return _liste(rows);
    } on PostgrestException catch (e) {
      if (_estRelationCasse(e)) {
        return _liste(await _sb
            .from('provider_reports')
            .select()
            .order('created_at', ascending: false)
            .limit(100));
      }
      throw Exception('Signalements indisponibles : ${e.message}');
    }
  }

  Future<void> traiterSignalement(
    String id,
    String statut, {
    String? note,
    bool suspendre = false,
  }) async {
    try {
      await _sb.rpc('admin_resolve_report', params: {
        'p_report': id,
        'p_status': statut,
        'p_note': note,
        'p_suspend': suspendre,
      });
    } on PostgrestException catch (e) {
      throw Exception('Action impossible : ${e.message}');
    }
  }

  RealtimeChannel ecouter(String table, void Function() onChange,
      {String? nom}) {
    final canal = _sb.channel(nom ?? 'admin-ctl-$table');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
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

  bool _estRelationCasse(PostgrestException e) =>
      e.code == 'PGRST200' ||
      e.code == 'PGRST116' ||
      e.message.toLowerCase().contains('relationship') ||
      e.message.toLowerCase().contains('foreign key');
}
