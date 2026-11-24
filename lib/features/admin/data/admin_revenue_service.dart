import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Commissions MonTotem d'une journée.
class RevenueDay {
  const RevenueDay({
    required this.date,
    required this.cash,
    required this.momo,
    required this.travel,
  });

  final DateTime date;
  final int cash;
  final int momo;
  final int travel;

  int get total => cash + momo + travel;
}

/// Synthèse des revenus (RPC admin_revenue_summary).
class RevenueSummary {
  const RevenueSummary({
    required this.days,
    required this.commissionCash,
    required this.commissionMomo,
    required this.commissionTravel,
    required this.commissionTotal,
    required this.topups,
    required this.ridesCompleted,
    required this.ridesVolume,
    required this.walletDebt,
    required this.providersBlocked,
    required this.series,
  });

  final int days;
  final int commissionCash;
  final int commissionMomo;
  final int commissionTravel;
  final int commissionTotal;
  final int topups;
  final int ridesCompleted;
  final int ridesVolume;
  final int walletDebt;
  final int providersBlocked;
  final List<RevenueDay> series;

  factory RevenueSummary.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;

    final serie = ((j['series'] as List?) ?? const [])
        .whereType<Map>()
        .map<RevenueDay>((e) {
          final m = Map<String, dynamic>.from(e);
          return RevenueDay(
            date: DateTime.tryParse('${m['day']}') ?? DateTime.now(),
            cash: (m['cash'] as num?)?.toInt() ?? 0,
            momo: (m['momo'] as num?)?.toInt() ?? 0,
            travel: (m['travel'] as num?)?.toInt() ?? 0,
          );
        })
        .toList();

    return RevenueSummary(
      days: n('days'),
      commissionCash: n('commission_cash_fcfa'),
      commissionMomo: n('commission_momo_fcfa'),
      commissionTravel: n('commission_travel_fcfa'),
      commissionTotal: n('commission_total_fcfa'),
      topups: n('topups_fcfa'),
      ridesCompleted: n('rides_completed'),
      ridesVolume: n('rides_volume_fcfa'),
      walletDebt: n('wallet_debt_fcfa'),
      providersBlocked: n('providers_blocked'),
      series: serie,
    );
  }
}

/// Revenus de MonTotem = commissions prélevées sur les portefeuilles.
class AdminRevenueService {
  SupabaseClient get _sb => Supabase.instance.client;

  Future<RevenueSummary> resume(int jours) async {
    try {
      final data = await _sb.rpc(
        'admin_revenue_summary',
        params: {'p_days': jours},
      );
      if (data is! Map) throw const FormatException('Réponse invalide.');
      return RevenueSummary.fromJson(Map<String, dynamic>.from(data));
    } on PostgrestException catch (e) {
      developer.log(
        'admin_revenue_summary',
        error: e,
        name: 'AdminRevenueService',
      );
      if (e.message.contains('INTERDIT')) {
        throw Exception('Action réservée à l\'administrateur.');
      }
      throw Exception('Impossible de charger les revenus.');
    }
  }

  /// Remplace, dans les statistiques du tableau de bord, le revenu (30 jours)
  /// par les commissions et les « paiements à traiter » par les recharges en
  /// attente. Ne lève jamais : les valeurs d'origine sont conservées en cas
  /// d'échec.
  Future<void> completerStats(Map<String, dynamic> stats) async {
    try {
      final r = await resume(30);
      stats['revenue_30d_fcfa'] = r.commissionTotal;
    } catch (_) {}
    try {
      final rows = await _sb
          .from('wallet_topup_requests')
          .select('id')
          .eq('statut', 'awaiting_validation');
      stats['pending_payments'] = (rows as List).length;
    } catch (_) {}
  }
}
