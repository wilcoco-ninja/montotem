import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/features/requests/domain/mission_item_model.dart';
import 'package:montotem/features/requests/domain/mission_model.dart';
import 'package:montotem/features/requests/domain/mission_payment_model.dart';

class MissionException implements Exception {
  const MissionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Missions de dépannage : tout passe par des fonctions SQL sécurisées.
/// Les prix viennent du catalogue du prestataire, jamais du client.
class MissionService {
  SupabaseClient get _sb => Supabase.instance.client;

  String? get currentUserId => _sb.auth.currentUser?.id;

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw MissionException(_message(e));
    } on MissionException {
      rethrow;
    } catch (_) {
      throw const MissionException(
          'Connexion impossible. Vérifiez votre réseau et réessayez.');
    }
  }

  Future<List<Mission>> mesMissions() => _run(() async {
        final data = await _sb.rpc('my_missions');
        return (data as List)
            .whereType<Map>()
            .map((e) => Mission.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });

  Future<Mission> obtenir(String id) => _run(() async {
        final data = await _sb.rpc('mission_to_json', params: {'p_id': id});
        if (data is! Map) throw const MissionException('Demande introuvable.');
        return Mission.fromJson(Map<String, dynamic>.from(data));
      });

  /// Prestations commandées (prix figés). Visible du client et du prestataire.
  Future<List<MissionItem>> prestations(String missionId) => _run(() async {
        final rows = await _sb
            .from('mission_items')
            .select('id, nom, prix_fcfa')
            .eq('mission_id', missionId)
            .order('created_at');
        return rows
            .map<MissionItem>(
                (r) => MissionItem.fromJson(Map<String, dynamic>.from(r)))
            .toList();
      });

  /// Crée une demande à partir de prestations du catalogue du prestataire.
  /// [prestationIds] : ids de `provider_catalog_items`. Les montants sont
  /// calculés et figés par le serveur.
  Future<String> creer({
    required String providerId,
    required String vehicle,
    required List<String> prestationIds,
    required double lat,
    required double lng,
    String? description,
    String? adresse,
  }) =>
      _run(() async {
        final id = await _sb.rpc('create_mission', params: {
          'p_provider': providerId,
          'p_vehicle': vehicle,
          'p_items': prestationIds,
          'p_description': description,
          'p_lat': lat,
          'p_lng': lng,
          'p_address': adresse,
        });
        return '$id';
      });

  /// action : accept | refuse | arrived | start_work | end_work
  /// Aucun montant : le prix de la réparation est celui des prestations.
  Future<void> agir(String id, String action) =>
      _run(() => _sb.rpc('mission_provider_action', params: {
            'p_mission': id,
            'p_action': action,
          }));

  /// Retourne le statut courant (« arrived » si l'arrivée vient d'être détectée).
  Future<String> envoyerPosition(String id, double lat, double lng) =>
      _run(() async {
        final s = await _sb.rpc('update_provider_position',
            params: {'p_mission': id, 'p_lat': lat, 'p_lng': lng});
        return '$s';
      });

  Future<void> annuler(String id, {String? motif}) => _run(() =>
      _sb.rpc('cancel_mission', params: {'p_mission': id, 'p_reason': motif}));

  Future<void> envoyerMessage(String id, String texte) => _run(() => _sb
      .rpc('send_mission_message', params: {'p_mission': id, 'p_body': texte}));

  Stream<List<Map<String, dynamic>>> messages(String id) => _sb
      .from('mission_messages')
      .stream(primaryKey: ['id'])
      .eq('mission_id', id)
      .order('created_at');

  /// Retourne les points d'étoiles gagnés.
  Future<int> laisserAvis(String id, int etoiles, String? commentaire) =>
      _run(() async {
        final r = await _sb.rpc('submit_review', params: {
          'p_mission': id,
          'p_stars': etoiles,
          'p_comment': commentaire,
        });
        return (r is Map ? (r['points'] as num?)?.toInt() : null) ?? 0;
      });

  Future<void> signaler({
    required String providerId,
    required String motif,
    String? missionId,
    String? details,
  }) =>
      _run(() => _sb.rpc('submit_provider_report', params: {
            'p_provider': providerId,
            'p_mission': missionId,
            'p_motif': motif,
            'p_details': details,
          }));

  // ── Paiements de mission ──────────────────────────────────────────────
  Future<List<MissionPayment>> paiements(String missionId) => _run(() async {
        final rows = await _sb
            .from('mission_payments')
            .select()
            .eq('mission_id', missionId)
            .order('created_at');
        return rows
            .map<MissionPayment>(
                (r) => MissionPayment.fromJson(Map<String, dynamic>.from(r)))
            .toList();
      });

  /// Le montant est calculé par le serveur. [kind] : trajet | reparation.
  Future<void> declarerPaiement({
    required String missionId,
    required String kind,
    required PayMethod methode,
    String? phone,
    String? reference,
  }) =>
      _run(() => _sb.rpc('declare_mission_payment', params: {
            'p_mission': missionId,
            'p_kind': kind,
            'p_operateur': methode.code,
            'p_phone': phone,
            'p_ref': reference,
          }));

  Future<void> confirmerPaiement(String paymentId) => _run(() =>
      _sb.rpc('confirm_mission_payment', params: {'p_payment': paymentId}));

  Future<void> refuserPaiement(String paymentId, String motif) =>
      _run(() => _sb.rpc('reject_mission_payment',
          params: {'p_payment': paymentId, 'p_reason': motif}));

  RealtimeChannel ecouterPaiements(String missionId, void Function() onChange) {
    final canal = _sb.channel('mission-pay-$missionId');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'mission_payments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'mission_id',
            value: missionId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return canal;
  }

  // ── Compte de réception du prestataire ────────────────────────────────
  Future<MomoAccount?> monMomo() => _run(() async {
        final uid = currentUserId;
        if (uid == null) return null;
        final row = await _sb
            .from('providers')
            .select('momo_operateur, momo_numero, momo_titulaire')
            .eq('id', uid)
            .maybeSingle();
        if (row == null || row['momo_numero'] == null) return null;
        return MomoAccount.fromJson({
          'operateur': row['momo_operateur'],
          'numero': row['momo_numero'],
          'titulaire': row['momo_titulaire'],
        });
      });

  /// Indicateurs du prestataire connecté (note, missions, disponibilité).
  Future<Map<String, dynamic>?> maStats() => _run(() async {
        final uid = currentUserId;
        if (uid == null) return null;
        final row = await _sb
            .from('providers')
            .select(
                'disponible, note_moyenne, missions_completees, clients_satisfaits, clients_insatisfaits, statut_validation')
            .eq('id', uid)
            .maybeSingle();
        return row == null ? null : Map<String, dynamic>.from(row);
      });

  Future<void> definirMomo({
    required String operateur,
    required String numero,
    String? titulaire,
  }) =>
      _run(() => _sb.rpc('set_provider_momo', params: {
            'p_operateur': operateur,
            'p_numero': numero,
            'p_titulaire': titulaire,
          }));

  Future<bool> disponible() => _run(() async {
        final uid = currentUserId;
        if (uid == null) return false;
        final row = await _sb
            .from('providers')
            .select('disponible')
            .eq('id', uid)
            .maybeSingle();
        return row?['disponible'] == true;
      });

  Future<void> definirDisponibilite(bool value) => _run(() async {
        final uid = currentUserId;
        if (uid == null) return;
        await _sb.from('providers').update({'disponible': value}).eq('id', uid);
      });

  RealtimeChannel ecouterMission(String id, void Function() onChange) {
    final canal = _sb.channel('mission-$id');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'missions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: id,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return canal;
  }

  /// Toutes mes missions (la sécurité RLS filtre côté serveur).
  RealtimeChannel ecouterMesMissions(void Function() onChange) {
    final canal = _sb.channel('my-missions-${currentUserId ?? 'anon'}');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'missions',
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

  String _message(PostgrestException e) {
    final m = e.message;
    if (m.contains('NON_CONNECTE')) return 'Session expirée. Reconnectez-vous.';
    if (m.contains('TROP_LOIN')) {
      return 'Rapprochez-vous du véhicule (moins de 500 m) pour signaler votre arrivée.';
    }
    if (m.contains('POSITION_INCONNUE')) {
      return 'Position GPS introuvable. Activez la localisation.';
    }
    if (m.contains('STATUT_INVALIDE')) {
      return 'Cette action n\'est plus possible : la demande a changé.';
    }
    if (m.contains('TROP_DE_DEMANDES')) {
      return 'Trop de demandes en cours. Patientez un moment.';
    }
    if (m.contains('WALLET_BLOQUE')) {
      return 'Votre wallet est bloqué : rechargez-le pour reprendre les demandes.';
    }
    if (m.contains('COMPTE_SUSPENDU')) {
      return 'Votre compte est suspendu. Contactez le support MONTOTEM.';
    }
    if (m.contains('PRESTATAIRE_NON_VALIDE')) {
      return 'Votre dossier doit être validé avant de passer en ligne.';
    }
    if (m.contains('PRESTATAIRE_INDISPONIBLE')) {
      return 'Ce dépanneur n\'est pas disponible pour le moment.';
    }
    if (m.contains('PAIEMENT_MOBILE_INDISPONIBLE')) {
      return 'Ce dépanneur n\'a pas encore configuré son paiement Mobile Money.';
    }
    if (m.contains('VEHICULE_NON_PRIS_EN_CHARGE')) {
      return 'Ce dépanneur ne prend pas en charge ce type de véhicule.';
    }
    if (m.contains('VEHICULE_INVALIDE')) return 'Type de véhicule invalide.';
    if (m.contains('PRESTATIONS_OBLIGATOIRES')) {
      return 'Choisissez au moins une prestation (8 maximum).';
    }
    if (m.contains('PRESTATION_INTROUVABLE')) {
      return 'Une prestation n\'est plus proposée. Rouvrez la fiche du dépanneur.';
    }
    if (m.contains('HORS_RAYON')) {
      return 'Vous êtes hors du rayon d\'intervention de ce dépanneur.';
    }
    if (m.contains('FRAIS_NON_PAYES')) {
      return 'Le client n\'a pas encore payé le déplacement.';
    }
    if (m.contains('MESSAGE_INVALIDE')) {
      return 'Message invalide (1 à 500 caractères).';
    }
    if (m.contains('NOTE_INVALIDE')) return 'Choisissez une note de 1 à 5.';
    if (m.contains('MOTIF_INVALIDE')) {
      return 'Choisissez un motif de signalement.';
    }
    if (m.contains('PRESTATAIRE_INTROUVABLE')) {
      return 'Ce prestataire n\'est plus disponible.';
    }
    if (m.contains('AVIS_DEJA_ENVOYE')) {
      return 'Vous avez déjà donné votre avis.';
    }
    if (m.contains('DEJA_DECLARE')) {
      return 'Un paiement est déjà déclaré pour cette étape.';
    }
    if (m.contains('RIEN_A_PAYER')) {
      return 'Aucun montant à payer pour le moment.';
    }
    if (m.contains('REFERENCE_DEJA_UTILISEE')) {
      return 'Cette référence de transaction a déjà été utilisée.';
    }
    if (m.contains('REFERENCE_INVALIDE')) {
      return 'Saisissez la référence reçue par SMS (4 caractères minimum).';
    }
    if (m.contains('TELEPHONE_INVALIDE')) {
      return 'Numéro de téléphone invalide.';
    }
    if (m.contains('OPERATEUR_INVALIDE')) {
      return 'Ce moyen de paiement n\'est pas accepté par le prestataire.';
    }
    if (m.contains('MOTIF_OBLIGATOIRE')) return 'Indiquez un motif.';
    if (m.contains('INTROUVABLE')) return 'Demande introuvable.';
    return 'Opération impossible. Réessayez.';
  }
}
