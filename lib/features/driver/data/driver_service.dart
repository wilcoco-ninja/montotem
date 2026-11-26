import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/features/rides/domain/ride_model.dart';

class DriverException implements Exception {
  const DriverException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// État du conducteur connecté (Zémidjan / Tricycle Fret).
class DriverInfo {
  const DriverInfo({
    required this.kind,
    required this.disponible,
    required this.statutValidation,
    required this.momoOperateur,
    required this.momoNumero,
    required this.noteMoyenne,
    required this.missionsCompletees,
  });

  final String? kind;
  final bool disponible;
  final String statutValidation;
  final String? momoOperateur;
  final String? momoNumero;
  final double noteMoyenne;
  final int missionsCompletees;

  /// Le `RideKind` correspondant, ou null si ce n'est pas un conducteur.
  RideKind? get rideKind => switch (kind) {
    'zemidjan' => RideKind.zemidjan,
    'tricycle_passenger' => RideKind.tricyclePassagers,
    'tricycle_fret' => RideKind.tricycleFret,
    _ => null,
  };

  bool get conducteur => rideKind != null;
  bool get valide => statutValidation == 'approved';
  bool get momoConfigure => (momoNumero ?? '').isNotEmpty;

  bool peutRecevoir(RidePaymentMethod m) =>
      !m.mobileMoney || (momoConfigure && momoOperateur == m.code);
}

/// Service d'accès aux données du conducteur.
class DriverService {
  SupabaseClient get _sb => Supabase.instance.client;
  String? get currentUserId => _sb.auth.currentUser?.id;

  /// Charge l'état du conducteur connecté.
  Future<DriverInfo?> charger() async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final row = await _sb
          .from('providers')
          .select(
            'provider_kind, disponible, statut_validation, '
            'momo_operateur, momo_numero, note_moyenne, missions_completees',
          )
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return null;
      return DriverInfo(
        kind: row['provider_kind'] as String?,
        disponible: row['disponible'] == true,
        // Évite la chaîne "null" quand le statut est absent.
        statutValidation: (row['statut_validation'] as String?) ?? 'pending',
        momoOperateur: row['momo_operateur'] as String?,
        momoNumero: row['momo_numero'] as String?,
        noteMoyenne: (row['note_moyenne'] as num?)?.toDouble() ?? 0,
        missionsCompletees: (row['missions_completees'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      developer.log('Chargement conducteur', error: e, name: 'DriverService');
      return null;
    }
  }

  /// Met à jour la disponibilité (en ligne / hors ligne).
  Future<void> definirDisponibilite(bool value) async {
    final uid = currentUserId;
    if (uid == null) {
      throw const DriverException(
        'Session expirée. Veuillez vous reconnecter.',
      );
    }
    try {
      await _sb.from('providers').update({'disponible': value}).eq('id', uid);
    } catch (e) {
      developer.log(
        'Disponibilité conducteur',
        error: e,
        name: 'DriverService',
      );
      throw const DriverException(
        'Impossible de changer votre disponibilité. Vérifiez votre connexion.',
      );
    }
  }

  /// Met à jour la position du conducteur (limité à 1 fois / 15s par le serveur).
  Future<void> mettreAJourPosition(double lat, double lng) async {
    try {
      await _sb.rpc(
        'update_driver_location',
        params: {'p_lat': lat, 'p_lng': lng},
      );
    } catch (e) {
      developer.log('Position conducteur', error: e, name: 'DriverService');
    }
  }

  /// Enregistre le numéro Mobile Money du conducteur.
  Future<void> definirMomo({
    required String operateur,
    required String numero,
    String? titulaire,
  }) async {
    try {
      await _sb.rpc(
        'set_provider_momo',
        params: {
          'p_operateur': operateur,
          'p_numero': numero,
          'p_titulaire': titulaire,
        },
      );
    } catch (e) {
      developer.log(
        'Enregistrement Mobile Money',
        error: e,
        name: 'DriverService',
      );
      throw const DriverException(
        'Impossible d\'enregistrer le numéro Mobile Money. Réessayez.',
      );
    }
  }

  /// Récupère le wallet du conducteur.
  Future<Map<String, dynamic>?> wallet() async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final row = await _sb
          .from('wallets')
          .select('balance_fcfa, blocked, block_reason')
          .eq('provider_id', uid)
          .maybeSingle();
      return row;
    } catch (e) {
      developer.log('Wallet conducteur', error: e, name: 'DriverService');
      return null;
    }
  }

  /// Récupère l'historique des courses du conducteur.
  Future<List<Ride>> mesCourses() async {
    try {
      final data = await _sb.rpc('my_rides');
      final uid = currentUserId;
      return (data as List)
          .whereType<Map>()
          .map((e) => Ride.fromJson(Map<String, dynamic>.from(e)))
          .where((r) => r.providerId == uid)
          .toList();
    } catch (e) {
      developer.log('Courses conducteur', error: e, name: 'DriverService');
      return const [];
    }
  }
}
