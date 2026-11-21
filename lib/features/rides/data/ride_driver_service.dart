import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/features/rides/domain/ride_model.dart';

/// État du prestataire connecté vu sous l'angle « conducteur de courses ».
class DriverInfo {
  const DriverInfo({
    required this.kind,
    required this.disponible,
    required this.statutValidation,
    required this.finAbonnement,
    required this.momoOperateur,
    required this.momoNumero,
  });

  final String? kind;
  final bool disponible;
  final String statutValidation;
  final DateTime? finAbonnement;
  final String? momoOperateur;
  final String? momoNumero;

  RideKind? get rideKind => switch (kind) {
        'zemidjan' => RideKind.zemidjan,
        'tricycle_fret' => RideKind.tricycleFret,
        _ => null,
      };

  /// Zémidjan ou Tricycle Fret.
  bool get conducteur => rideKind != null;

  bool get valide => statutValidation == 'approved';

  bool get abonnementActif =>
      finAbonnement != null && finAbonnement!.isAfter(DateTime.now());

  bool get momoConfigure => (momoNumero ?? '').isNotEmpty;

  bool peutRecevoir(RidePaymentMethod m) =>
      !m.mobileMoney || (momoConfigure && momoOperateur == m.code);
}

/// Lectures et mises à jour propres au conducteur. Ne lève jamais d'exception.
class RideDriverService {
  SupabaseClient get _sb => Supabase.instance.client;

  Future<DriverInfo?> charger() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _sb
          .from('providers')
          .select('provider_kind, disponible, statut_validation, '
              'fin_abonnement, momo_operateur, momo_numero')
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return null;
      return DriverInfo(
        kind: row['provider_kind'] as String?,
        disponible: row['disponible'] == true,
        // Évite la chaîne "null" quand le statut est absent.
        statutValidation: (row['statut_validation'] as String?) ?? 'pending',
        finAbonnement:
            DateTime.tryParse('${row['fin_abonnement'] ?? ''}')?.toLocal(),
        momoOperateur: row['momo_operateur'] as String?,
        momoNumero: row['momo_numero'] as String?,
      );
    } catch (e) {
      developer.log('Infos conducteur', error: e, name: 'RideDriverService');
      return null;
    }
  }

  /// Pourcentage de commission sur les courses cash (app_config).
  Future<int> commissionPct() async {
    try {
      final row = await _sb
          .from('app_config')
          .select('value_int')
          .eq('key', 'commission_cash_pct')
          .maybeSingle();
      final v = (row?['value_int'] as num?)?.toInt();
      return (v != null && v >= 0 && v <= 100) ? v : 15;
    } catch (_) {
      return 15;
    }
  }

  /// Met à jour la position du conducteur (le serveur limite à une mise à
  /// jour toutes les 15 s). Échec silencieux : la prochaine tentative suivra.
  Future<void> mettreAJourPosition(double lat, double lng) async {
    try {
      await _sb
          .rpc('update_driver_location', params: {'p_lat': lat, 'p_lng': lng});
    } catch (e) {
      developer.log('Position conducteur', error: e, name: 'RideDriverService');
    }
  }
}