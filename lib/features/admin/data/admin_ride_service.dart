import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/features/rides/domain/ride_model.dart';

class AdminRideException implements Exception {
  const AdminRideException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Courses vues par l'administrateur. La sécurité repose sur les RPC
/// `admin_*` (is_admin()) et sur la RLS de la table `rides`.
class AdminRideService {
  SupabaseClient get _sb => Supabase.instance.client;

  Future<List<Ride>> lister({int limite = 150}) async {
    try {
      final data = await _sb.rpc('admin_rides', params: {'p_limit': limite});
      return (data as List)
          .whereType<Map>()
          .map((e) => Ride.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } on PostgrestException catch (e) {
      developer.log('Courses admin', error: e, name: 'AdminRideService');
      throw AdminRideException(_message(e));
    } catch (e) {
      developer.log('Courses admin', error: e, name: 'AdminRideService');
      throw const AdminRideException('Impossible de charger les courses.');
    }
  }

  Future<void> annuler(String id, String motif) async {
    try {
      await _sb.rpc(
        'admin_cancel_ride',
        params: {'p_ride': id, 'p_reason': motif},
      );
    } on PostgrestException catch (e) {
      developer.log('Annulation course', error: e, name: 'AdminRideService');
      throw AdminRideException(_message(e));
    } catch (_) {
      throw const AdminRideException('Serveur injoignable.');
    }
  }

  RealtimeChannel ecouter(void Function() onChange) {
    final canal = _sb.channel('admin-rides');
    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rides',
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
    if (m.contains('INTERDIT')) return 'Action réservée à l\'administrateur.';
    if (m.contains('MOTIF_OBLIGATOIRE')) return 'Un motif est obligatoire.';
    if (m.contains('STATUT_INVALIDE')) {
      return 'Cette course est déjà terminée ou annulée.';
    }
    if (m.contains('INTROUVABLE')) return 'Course introuvable.';
    return 'Serveur injoignable ou opération refusée.';
  }
}
