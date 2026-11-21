import 'package:flutter/foundation.dart';

import 'package:montotem/core/utils/travel_fee.dart';
import 'package:montotem/features/wallet/domain/devise.dart';

/// "-2 500 FCFA" : TravelFee.fcfa ne gère pas les montants négatifs.
String formaterFcfaSigne(int montant) =>
    '${montant < 0 ? '-' : ''}${TravelFee.fcfa(montant.abs())}';

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse('$v')?.toLocal();

int _entier(dynamic v, [int defaut = 0]) => (v as num?)?.toInt() ?? defaut;

/// Wallet prestataire — miroir du double ledger (scripts finance/12 et 13) :
///   - balanceFcfa          : solde historique (compatibilité écrans
///                            existants, dette = balance < 0) ;
///   - payableBalance       : argent Mobile Money encaissé par MonTotem,
///                            retirable vers MoMo / banque ;
///   - cashCommissionDebt   : dette de commission sur courses CASH (le pro
///                            garde 100 % du cash, la dette augmente) ;
///   - creditLimit          : plafond de dette cash (0 = plafond global
///                            app_config.cash_credit_limit_fcfa).
@immutable
class Wallet {
  const Wallet({
    required this.providerId,
    required this.balanceFcfa,
    required this.blocked,
    this.deviseCode = 'XOF',
    this.payableBalance = 0,
    this.cashCommissionDebt = 0,
    this.creditLimit = 0,
    this.blockReason,
    this.blockedAt,
    this.updatedAt,
  });

  factory Wallet.vide(String providerId) =>
      Wallet(providerId: providerId, balanceFcfa: 0, blocked: false);

  factory Wallet.fromJson(Map<String, dynamic> j) => Wallet(
        providerId: '${j['provider_id']}',
        balanceFcfa: _entier(j['balance_fcfa']),
        blocked: j['blocked'] == true,
        deviseCode: j['devise_code'] == null
            ? 'XOF'
            : '${j['devise_code']}'.toUpperCase(),
        payableBalance: _entier(j['payable_balance']),
        cashCommissionDebt: _entier(j['cash_commission_debt']),
        creditLimit: _entier(j['credit_limit']),
        blockReason: j['block_reason'] as String?,
        blockedAt: _date(j['blocked_at']),
        updatedAt: _date(j['updated_at']),
      );

  final String providerId;
  final int balanceFcfa;
  final bool blocked;
  final String deviseCode;
  final int payableBalance;
  final int cashCommissionDebt;
  final int creditLimit;
  final String? blockReason;
  final DateTime? blockedAt;
  final DateTime? updatedAt;

  /// Devise de la zone du prestataire (référence serveur `devises`,
  /// XOF par défaut). Doc uniquement : les comparaisons de soldes restent
  /// en FCFA tant que payable/dette ne sont mélangées à aucun autre montant.
  Devise get devise => Devise.depuisCode(deviseCode);

  /// Solde MoMo disponible (payable_balance, unités mineures de la devise).
  Money get soldePayable => Money.zero(devise).fromMinor(payableBalance);

  /// Dette de commission cash.
  Money get detteCash => Money.zero(devise).fromMinor(cashCommissionDebt);

  /// Plafond effectif : celui du prestataire si renseigné, sinon le plafond
  /// global fourni par [cashCreditLimitGlobal] (app_config côté serveur).
  int plafondCash(int cashCreditLimitGlobal) =>
      creditLimit > 0 ? creditLimit : cashCreditLimitGlobal;

  /// Miroir client du RPC serveur `est_bloque_cash` (script finance/13) :
  /// le serveur refusera les nouvelles commandes cash quand
  /// dette >= plafond.
  bool estBloqueCash(int cashCreditLimitGlobal) =>
      cashCommissionDebt >= plafondCash(cashCreditLimitGlobal);

  Map<String, dynamic> toJson() => {
        'provider_id': providerId,
        'balance_fcfa': balanceFcfa,
        'blocked': blocked,
        'devise_code': deviseCode,
        'payable_balance': payableBalance,
        'cash_commission_debt': cashCommissionDebt,
        'credit_limit': creditLimit,
        'block_reason': blockReason,
        'blocked_at': blockedAt?.toUtc().toIso8601String(),
        'updated_at': updatedAt?.toUtc().toIso8601String(),
      };
}

@immutable
class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.kind,
    required this.amountFcfa,
    required this.balanceAfter,
    required this.createdAt,
    this.rideId,
    this.reference,
    this.note,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> j) =>
      WalletTransaction(
        id: _entier(j['id']),
        kind: '${j['kind']}',
        amountFcfa: _entier(j['amount_fcfa']),
        balanceAfter: _entier(j['balance_after']),
        createdAt: _date(j['created_at']) ?? DateTime.now(),
        rideId: j['ride_id'] == null ? null : '${j['ride_id']}',
        reference: j['reference'] as String?,
        note: j['note'] as String?,
      );

  final int id;

  /// commission_cash | commission_momo | commission_travel | topup |
  /// adjustment | refund
  final String kind;
  final int amountFcfa;
  final int balanceAfter;
  final DateTime createdAt;
  final String? rideId;
  final String? reference;
  final String? note;

  bool get estCredit => amountFcfa > 0;

  /// Commission prélevée par MonTotem (quel qu'en soit le type).
  bool get estCommission => kind.startsWith('commission_');

  /// Commission liée à un paiement CASH du client : dette du pro du même
  /// coup. Certain à 100 % pour 'commission_cash'. Pour 'commission_travel',
  /// l'origine (course:% / trajet:%) est tranchée côté serveur par
  /// `_commission_est_cash` (script finance/12) — le client ne présume pas.
  bool get estCommissionCash => kind == 'commission_cash';

  String get libelle => switch (kind) {
        'commission_cash' => 'Commission course cash',
        'commission_momo' => 'Commission course Mobile Money',
        'commission_travel' => 'Commission frais de déplacement',
        'topup' => 'Recharge',
        'adjustment' => 'Ajustement',
        'refund' => 'Remboursement',
        _ => 'Mouvement',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'amount_fcfa': amountFcfa,
        'balance_after': balanceAfter,
        'created_at': createdAt.toUtc().toIso8601String(),
        'ride_id': rideId,
        'reference': reference,
        'note': note,
      };
}

/// Résultat du calcul d'une commission : montant encaissé, part MonTotem,
/// part nette du prestataire. Arrondi identique au serveur (round, 0,5 vers
/// le haut). API historique conservée (montantFcfa / pct / netFcfa).
@immutable
class CommissionCalcul {
  const CommissionCalcul({
    required this.montantFcfa,
    required this.pct,
    required this.commissionFcfa,
  });

  final int montantFcfa;
  final int pct;
  final int commissionFcfa;

  int get netFcfa => montantFcfa - commissionFcfa;
}

/// Résultat du calcul multi-devise (couche additive) : montant en unités
/// mineures de la devise, commission arrondie selon la règle de la devise
/// (miroir du RPC `calculer_commission`, script finance/13).
@immutable
class CommissionDevise {
  const CommissionDevise({
    required this.devise,
    required this.montantMinor,
    required this.pct,
    required this.commissionMinor,
  });

  final Devise devise;

  /// Montant total payé par le client, en unités mineures (bigint côté SQL).
  final int montantMinor;

  /// Pourcentage appliqué (null si commission forfaitaire côté serveur).
  final int pct;
  final int commissionMinor;

  Money get montant => Money.zero(devise).fromMinor(montantMinor);
  Money get commission => Money.zero(devise).fromMinor(commissionMinor);
  int get netMinor => montantMinor - commissionMinor;
  Money get net => Money.zero(devise).fromMinor(netMinor);
}

/// Règles du wallet (table app_config, modifiables côté serveur).
@immutable
class WalletConfig {
  const WalletConfig({
    this.commissionCashPct = 15,
    this.commissionMomoPct = 15,
    this.commissionTravelPct = 15,
    this.seuilBlocageFcfa = -2000,
    this.cashCreditLimitFcfa = 5000,
  });

  factory WalletConfig.fromRows(List<dynamic> rows) {
    var cash = 15;
    var momo = 15;
    var travel = 15;
    var seuil = -2000;
    var plafond = 5000;
    for (final r in rows.whereType<Map>()) {
      final valeur = (r['value_int'] as num?)?.toInt();
      if (valeur == null) continue;
      switch (r['key']) {
        case 'commission_cash_pct':
          cash = valeur;
        case 'commission_momo_pct':
          momo = valeur;
        case 'commission_travel_pct':
          travel = valeur;
        case 'wallet_block_threshold_fcfa':
          seuil = valeur;
        case 'cash_credit_limit_fcfa':
          plafond = valeur;
      }
    }
    return WalletConfig(
      commissionCashPct: cash,
      commissionMomoPct: momo,
      commissionTravelPct: travel,
      seuilBlocageFcfa: seuil,
      cashCreditLimitFcfa: plafond,
    );
  }

  final int commissionCashPct;
  final int commissionMomoPct;
  final int commissionTravelPct;
  final int seuilBlocageFcfa;

  /// Plafond global de dette cash (app_config, surchargeable par
  /// prestataire via wallets.credit_limit — décision serveur, script 13).
  final int cashCreditLimitFcfa;

  /// Taux appliqué aux courses (cash par défaut, historique).
  int get commissionPct => commissionCashPct;

  /// Taux d'une course selon son mode de paiement.
  int commissionPourCourse({required bool mobileMoney}) =>
      mobileMoney ? commissionMomoPct : commissionCashPct;

  static CommissionCalcul _calculer(int montantFcfa, int pct) {
    final montant = montantFcfa < 0 ? 0 : montantFcfa;
    final p = pct.clamp(0, 100);
    return CommissionCalcul(
      montantFcfa: montant,
      pct: p,
      commissionFcfa: (montant * p / 100).round(),
    );
  }

  CommissionCalcul calculerCourse(int prixFcfa, {required bool mobileMoney}) =>
      _calculer(prixFcfa, commissionPourCourse(mobileMoney: mobileMoney));

  CommissionCalcul calculerTrajet(int fraisFcfa) =>
      _calculer(fraisFcfa, commissionTravelPct);

  /// Calcul ESTIMÉ multi-devise en unités mineures (XOF = int directs,
  /// NGN/KES = sous-unités). Aperçu uniquement : le calcul définitif reste
  /// serveur (RPC `calculer_commission`, script finance/13), avec les règles
  /// hybrides (montant_fixe, plancher/plafond) impossibles à reconstituer
  /// côté client.
  CommissionDevise calculerCourseEnDevise(
    int montantMinor,
    Devise devise, {
    required bool mobileMoney,
  }) {
    final p = commissionPourCourse(mobileMoney: mobileMoney).clamp(0, 100);
    final montant =
        Money.zero(devise).fromMinor(montantMinor < 0 ? 0 : montantMinor);
    return CommissionDevise(
      devise: devise,
      montantMinor: montant.minorUnits,
      pct: p,
      commissionMinor: montant.pourcent(p).minorUnits,
    );
  }

  CommissionDevise calculerTrajetEnDevise(int montantMinor, Devise devise) {
    final p = travelPctClamp;
    final montant =
        Money.zero(devise).fromMinor(montantMinor < 0 ? 0 : montantMinor);
    return CommissionDevise(
      devise: devise,
      montantMinor: montant.minorUnits,
      pct: p,
      commissionMinor: montant.pourcent(p).minorUnits,
    );
  }

  int get travelPctClamp => commissionTravelPct.clamp(0, 100);

  List<Map<String, dynamic>> toRows() => [
        {'key': 'commission_cash_pct', 'value_int': commissionCashPct},
        {'key': 'commission_momo_pct', 'value_int': commissionMomoPct},
        {'key': 'commission_travel_pct', 'value_int': commissionTravelPct},
        {'key': 'wallet_block_threshold_fcfa', 'value_int': seuilBlocageFcfa},
        {'key': 'cash_credit_limit_fcfa', 'value_int': cashCreditLimitFcfa},
      ];
}
