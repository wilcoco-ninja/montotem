import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

class EarningsException implements Exception {
  const EarningsException(this.message);
  final String message;

  @override
  String toString() => message;
}

class EarningsDay {
  const EarningsDay({
    required this.date,
    required this.gross,
    required this.commission,
  });

  final DateTime date;
  final int gross;
  final int commission;
}

/// Synthèse des gains du prestataire connecté (RPC provider_earnings_summary).
class EarningsSummary {
  const EarningsSummary({
    required this.days,
    required this.ridesCashCount,
    required this.ridesCashFcfa,
    required this.ridesMomoCount,
    required this.ridesMomoFcfa,
    required this.travelGrossFcfa,
    required this.repairGrossFcfa,
    required this.grossFcfa,
    required this.commissionFcfa,
    required this.netFcfa,
    required this.series,
  });

  final int days;
  final int ridesCashCount;
  final int ridesCashFcfa;
  final int ridesMomoCount;
  final int ridesMomoFcfa;
  final int travelGrossFcfa;
  final int repairGrossFcfa;
  final int grossFcfa;
  final int commissionFcfa;
  final int netFcfa;

  /// Une entrée par jour, du plus ancien au plus récent.
  final List<EarningsDay> series;

  factory EarningsSummary.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;

    final serie = ((j['series'] as List?) ?? const [])
        .whereType<Map>()
        .map<EarningsDay>((e) {
          final m = Map<String, dynamic>.from(e);
          return EarningsDay(
            date: DateTime.tryParse('${m['day']}') ?? DateTime.now(),
            gross: (m['gross'] as num?)?.toInt() ?? 0,
            commission: (m['commission'] as num?)?.toInt() ?? 0,
          );
        })
        .toList();

    return EarningsSummary(
      days: n('days'),
      ridesCashCount: n('rides_cash_count'),
      ridesCashFcfa: n('rides_cash_fcfa'),
      ridesMomoCount: n('rides_momo_count'),
      ridesMomoFcfa: n('rides_momo_fcfa'),
      travelGrossFcfa: n('travel_gross_fcfa'),
      repairGrossFcfa: n('repair_gross_fcfa'),
      grossFcfa: n('gross_fcfa'),
      commissionFcfa: n('commission_fcfa'),
      netFcfa: n('net_fcfa'),
      series: serie,
    );
  }
}

class ProviderEarningsService {
  SupabaseClient get _sb => Supabase.instance.client;

  Future<EarningsSummary> resume(int jours) async {
    try {
      final data = await _sb.rpc(
        'provider_earnings_summary',
        params: {'p_days': jours},
      );
      if (data is! Map) {
        throw const EarningsException('Réponse invalide du serveur.');
      }
      return EarningsSummary.fromJson(Map<String, dynamic>.from(data));
    } on PostgrestException catch (e) {
      developer.log(
        'provider_earnings_summary',
        error: e,
        name: 'ProviderEarningsService',
      );
      final m = e.message;
      if (m.contains('NON_CONNECTE')) {
        throw const EarningsException('Session expirée. Reconnectez-vous.');
      }
      if (m.contains('PAS_PRESTATAIRE')) {
        throw const EarningsException('Dossier prestataire introuvable.');
      }
      throw const EarningsException('Impossible de charger vos gains.');
    } on EarningsException {
      rethrow;
    } catch (e) {
      developer.log(
        'provider_earnings_summary inattendu',
        error: e,
        name: 'ProviderEarningsService',
      );
      throw const EarningsException(
        'Connexion impossible. Vérifiez votre réseau.',
      );
    }
  }
}
