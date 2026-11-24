import 'package:flutter/foundation.dart';

int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

DateTime _jour(dynamic v) => DateTime.tryParse('$v') ?? DateTime.now();

/// Un jour de la synthèse prestataire : encaissé et commissions prélevées.
@immutable
class EarningsDay {
  const EarningsDay({
    required this.day,
    required this.grossFcfa,
    required this.commissionFcfa,
  });

  factory EarningsDay.fromJson(Map<String, dynamic> j) => EarningsDay(
    day: _jour(j['day']),
    grossFcfa: _int(j['gross']),
    commissionFcfa: _int(j['commission']),
  );

  final DateTime day;
  final int grossFcfa;
  final int commissionFcfa;
}

/// Réponse de la fonction SQL provider_earnings_summary.
@immutable
class EarningsSummary {
  const EarningsSummary({
    required this.days,
    required this.ridesCashCount,
    required this.ridesCashFcfa,
    required this.ridesMomoCount,
    required this.ridesMomoFcfa,
    required this.ridesCommissionFcfa,
    required this.travelGrossFcfa,
    required this.travelCommissionFcfa,
    required this.repairGrossFcfa,
    required this.grossFcfa,
    required this.commissionFcfa,
    required this.netFcfa,
    required this.walletBalanceFcfa,
    required this.walletBlocked,
    required this.series,
  });

  factory EarningsSummary.fromJson(Map<String, dynamic> j) => EarningsSummary(
    days: _int(j['days']),
    ridesCashCount: _int(j['rides_cash_count']),
    ridesCashFcfa: _int(j['rides_cash_fcfa']),
    ridesMomoCount: _int(j['rides_momo_count']),
    ridesMomoFcfa: _int(j['rides_momo_fcfa']),
    ridesCommissionFcfa: _int(j['rides_commission_fcfa']),
    travelGrossFcfa: _int(j['travel_gross_fcfa']),
    travelCommissionFcfa: _int(j['travel_commission_fcfa']),
    repairGrossFcfa: _int(j['repair_gross_fcfa']),
    grossFcfa: _int(j['gross_fcfa']),
    commissionFcfa: _int(j['commission_fcfa']),
    netFcfa: _int(j['net_fcfa']),
    walletBalanceFcfa: _int(j['wallet_balance_fcfa']),
    walletBlocked: j['wallet_blocked'] == true,
    series:
        (j['series'] as List?)
            ?.whereType<Map>()
            .map((e) => EarningsDay.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const [],
  );

  final int days;
  final int ridesCashCount;
  final int ridesCashFcfa;
  final int ridesMomoCount;
  final int ridesMomoFcfa;
  final int ridesCommissionFcfa;
  final int travelGrossFcfa;
  final int travelCommissionFcfa;
  final int repairGrossFcfa;
  final int grossFcfa;
  final int commissionFcfa;
  final int netFcfa;
  final int walletBalanceFcfa;
  final bool walletBlocked;
  final List<EarningsDay> series;
}

/// Un jour de la synthèse admin : commissions par type.
@immutable
class RevenueDay {
  const RevenueDay({
    required this.day,
    required this.cashFcfa,
    required this.momoFcfa,
    required this.travelFcfa,
  });

  factory RevenueDay.fromJson(Map<String, dynamic> j) => RevenueDay(
    day: _jour(j['day']),
    cashFcfa: _int(j['cash']),
    momoFcfa: _int(j['momo']),
    travelFcfa: _int(j['travel']),
  );

  final DateTime day;
  final int cashFcfa;
  final int momoFcfa;
  final int travelFcfa;

  int get totalFcfa => cashFcfa + momoFcfa + travelFcfa;
}

/// Réponse de la fonction SQL admin_revenue_summary.
@immutable
class RevenueSummary {
  const RevenueSummary({
    required this.days,
    required this.commissionCashFcfa,
    required this.commissionMomoFcfa,
    required this.commissionTravelFcfa,
    required this.commissionTotalFcfa,
    required this.topupsFcfa,
    required this.ridesCompleted,
    required this.ridesVolumeFcfa,
    required this.walletDebtFcfa,
    required this.providersBlocked,
    required this.series,
  });

  factory RevenueSummary.fromJson(Map<String, dynamic> j) => RevenueSummary(
    days: _int(j['days']),
    commissionCashFcfa: _int(j['commission_cash_fcfa']),
    commissionMomoFcfa: _int(j['commission_momo_fcfa']),
    commissionTravelFcfa: _int(j['commission_travel_fcfa']),
    commissionTotalFcfa: _int(j['commission_total_fcfa']),
    topupsFcfa: _int(j['topups_fcfa']),
    ridesCompleted: _int(j['rides_completed']),
    ridesVolumeFcfa: _int(j['rides_volume_fcfa']),
    walletDebtFcfa: _int(j['wallet_debt_fcfa']),
    providersBlocked: _int(j['providers_blocked']),
    series:
        (j['series'] as List?)
            ?.whereType<Map>()
            .map((e) => RevenueDay.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const [],
  );

  final int days;
  final int commissionCashFcfa;
  final int commissionMomoFcfa;
  final int commissionTravelFcfa;
  final int commissionTotalFcfa;
  final int topupsFcfa;
  final int ridesCompleted;
  final int ridesVolumeFcfa;
  final int walletDebtFcfa;
  final int providersBlocked;
  final List<RevenueDay> series;
}
