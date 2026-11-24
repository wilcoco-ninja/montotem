import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/models/app_user.dart';
import 'package:montotem/features/tracking/domain/prestataire_model.dart';
import 'package:montotem/features/admin/domain/admin_stats_model.dart';

class AdminService {
  AdminService();

  SupabaseClient get _sb => Supabase.instance.client;

  Future<AdminDashboardStats> obtenirStatistiques() async {
    try {
      final data = await _sb.rpc('admin_dashboard_stats');
      if (data is! Map) throw const FormatException('Réponse stats invalide.');
      return AdminDashboardStats.fromJson(Map<String, dynamic>.from(data));
    } on PostgrestException catch (e) {
      developer.log('Stats admin', error: e, name: 'AdminService');
      throw Exception('Erreur stats : ${_msg(e)}');
    }
  }

  Future<List<AppUser>> obtenirUtilisateurs({
    int page = 0,
    int taille = 200,
  }) async {
    try {
      final rows = await _sb
          .from('profiles')
          .select(
            'id, phone, role, inscription_complete, first_name, '
            'last_name, photo_profil_url, '
            'providers!providers_id_fkey(business_name, metier, ville, '
            'statut_validation, latitude, longitude, fin_abonnement)',
          )
          .order('created_at', ascending: false)
          .range(page * taille, (page + 1) * taille - 1);
      return rows.map<AppUser>((row) {
        final presta = _un(row['providers']);
        return AppUser.fromJson({
          'id': row['id'],
          'phone': (row['phone'] as String?) ?? '',
          'role': row['role'],
          'inscription_complete': row['inscription_complete'] ?? false,
          'first_name': row['first_name'],
          'last_name': row['last_name'],
          'is_approved': presta?['statut_validation'] == 'approved',
          'photo_profil_url': row['photo_profil_url'],
          'prestataire': presta,
        });
      }).toList();
    } on PostgrestException catch (e) {
      developer.log('Utilisateurs admin', error: e, name: 'AdminService');
      throw Exception('Erreur utilisateurs : ${_msg(e)}');
    }
  }

  Future<List<Map<String, dynamic>>> obtenirPrestatairesBrut({
    bool pendingOnly = false,
  }) async {
    try {
      var query = _sb
          .from('providers')
          .select(
            '*, profiles!providers_id_fkey(first_name, last_name, phone, email, photo_profil_url)',
          );
      if (pendingOnly) {
        query = query.eq('statut_validation', 'pending');
      }
      final rows = await query.order('created_at', ascending: false);

      return rows.map<Map<String, dynamic>>((row) {
        final profil = _un(row['profiles']) ?? <String, dynamic>{};
        return {
          'id': row['id'],
          'business_name': row['business_name'],
          'metier': row['metier'],
          'ville': row['ville'],
          'ifu': row['ifu'],
          'photo_cni_url': row['photo_cni_url'],
          'latitude': row['latitude'],
          'longitude': row['longitude'],
          'disponible': row['disponible'],
          'statut_validation': row['statut_validation'],
          'rejection_reason': row['rejection_reason'],
          'note_moyenne': row['note_moyenne'],
          'clients_satisfaits': row['clients_satisfaits'],
          'clients_insatisfaits': row['clients_insatisfaits'],
          'missions_completees': row['missions_completees'],
          'statut_mission': row['statut_mission'],
          'id_document_type': row['id_document_type'],
          'id_document_number': row['id_document_number'],
          'photo_cni_back_url': row['photo_cni_back_url'],
          'photo_garage_url': row['photo_garage_url'],
          'garage_description': row['garage_description'],
          'id_checks': row['id_checks'],
          'identity_submitted_at': row['identity_submitted_at'],
          'user': {
            ...profil,
            'is_approved': row['statut_validation'] == 'approved',
          },
        };
      }).toList();
    } on PostgrestException catch (e) {
      developer.log('Prestataires admin', error: e, name: 'AdminService');
      throw Exception('Erreur prestataires : ${_msg(e)}');
    }
  }

  Future<List<Prestataire>> obtenirPrestataires({
    bool pendingOnly = false,
  }) async {
    final rows = await obtenirPrestatairesBrut(pendingOnly: pendingOnly);
    return rows.map((map) {
      final user =
          (map['user'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final firstName = (user['first_name'] as String?) ?? '';
      final lastName = (user['last_name'] as String?) ?? '';
      final fullName = '$firstName $lastName'.trim();

      return Prestataire(
        id: '${map['id']}',
        nom: fullName.isNotEmpty
            ? fullName
            : (user['phone'] as String?) ?? 'Prestataire',
        metier: (map['metier'] as String?) ?? '',
        latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
        telephone: user['phone'] as String?,
        photoUrl: user['photo_profil_url'] as String?,
        businessName: map['business_name'] as String?,
        adresse: map['ville'] as String?,
        verifie: (user['is_approved'] as bool?) ?? false,
        disponible: (map['disponible'] as bool?) ?? false,
        noteMoyenne: (map['note_moyenne'] as num?)?.toDouble() ?? 0.0,
        clientsSatisfaits: (map['clients_satisfaits'] as num?)?.toInt() ?? 0,
        clientsInsatisfaits:
            (map['clients_insatisfaits'] as num?)?.toInt() ?? 0,
        missionsCompletees: (map['missions_completees'] as num?)?.toInt() ?? 0,
        statutMission: map['statut_mission'] as String?,
      );
    }).toList();
  }

  Future<void> approuverPrestataire(String id) =>
      _definirStatut(id, 'approved');

  Future<void> rejeterPrestataire(String id, {String? motif}) => _definirStatut(
    id,
    'rejected',
    motif: (motif == null || motif.trim().isEmpty)
        ? 'Dossier non conforme'
        : motif.trim(),
  );

  Future<void> _definirStatut(String id, String statut, {String? motif}) async {
    try {
      await _sb.rpc(
        'admin_set_provider_status',
        params: {'p_provider_id': id, 'p_status': statut, 'p_reason': motif},
      );
    } on PostgrestException catch (e) {
      developer.log('Statut prestataire', error: e, name: 'AdminService');
      throw Exception(_msg(e));
    }
  }

  Future<List<Map<String, dynamic>>> obtenirDemandesAbonnement({
    String? statut,
  }) async {
    try {
      var query = _sb
          .from('subscription_requests')
          .select(
            '*, providers(business_name, metier, ville, statut_validation, '
            'profiles!providers_id_fkey(first_name, last_name, phone, email))',
          );
      if (statut != null) {
        query = query.eq('statut', statut);
      }
      final rows = await query.order('created_at', ascending: false);
      return rows
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e))
          .toList();
    } on PostgrestException catch (e) {
      developer.log('Demandes abonnement', error: e, name: 'AdminService');
      throw Exception('Erreur paiements : ${_msg(e)}');
    }
  }

  Future<void> validerAbonnement(String requestId) =>
      _revoir(requestId, approuver: true);

  Future<void> refuserAbonnement(String requestId, String motif) =>
      _revoir(requestId, approuver: false, motif: motif);

  Future<void> _revoir(
    String requestId, {
    required bool approuver,
    String? motif,
  }) async {
    try {
      await _sb.rpc(
        'admin_review_subscription',
        params: {
          'p_request_id': requestId,
          'p_approve': approuver,
          'p_reason': motif,
        },
      );
    } on PostgrestException catch (e) {
      developer.log('Revue abonnement', error: e, name: 'AdminService');
      throw Exception(_msg(e));
    }
  }

  RealtimeChannel ecouterNotificationsAdmin(
    void Function(Map<String, dynamic> notification) onNouvelle,
  ) {
    final canal = _sb.channel('admin-notifications');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'admins_only',
            value: true,
          ),
          callback: (payload) => onNouvelle(payload.newRecord),
        )
        .subscribe();
    return canal;
  }

  Future<void> arreterEcoute(RealtimeChannel canal) async {
    try {
      await _sb.removeChannel(canal);
    } catch (_) {}
  }

  Map<String, dynamic>? _un(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is List && v.isNotEmpty && v.first is Map) {
      return Map<String, dynamic>.from(v.first as Map);
    }
    return null;
  }

  String _msg(PostgrestException e) {
    final m = e.message;
    if (m.contains('INTERDIT')) return 'Action réservée à l\'administrateur.';
    if (m.contains('DEJA_TRAITEE')) return 'Cette demande a déjà été traitée.';
    if (m.contains('INTROUVABLE')) return 'Élément introuvable.';
    if (m.contains('MOTIF_OBLIGATOIRE')) return 'Un motif est obligatoire.';
    if (m.contains('STATUT_INVALIDE')) return 'Statut invalide.';
    if (m.contains('IDENTITE_INCOMPLETE')) {
      return 'Dossier d\'identité incomplet : approbation impossible.';
    }
    return 'Serveur injoignable ou opération refusée.';
  }
}
