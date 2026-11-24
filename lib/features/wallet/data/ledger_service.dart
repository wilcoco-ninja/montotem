import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/features/wallet/domain/devise.dart';

/// Une écriture du grand livre append-only `ledger_entries` (script 12) :
/// chaque mouvement d'argent du prestataire, horodaté, immuable, avec
/// l'état des deux poches APRÈS opération (payable MoMo / dette cash).
/// Montants en unités mineures (int) — jamais en double.
class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.devise,
    required this.kind,
    required this.amountMinor,
    required this.payableAfter,
    required this.debtAfter,
    this.clientRequestId,
    this.referenceId,
    this.note,
    required this.createdAt,
  });

  final int id;

  /// Devise de l'écriture (mirroir de `ledger_entries.devise_code`,
  /// script finance/11). XOF pour le Bénin.
  final Devise devise;

  /// Code brut en base : `cash_encaisse`, `commission_cash`,
  /// `commission_momo`, `commission_travel`, `momo_paiement`, `topup`,
  /// `debit_commission`, `ajustement`, `remboursement`.
  final String kind;

  /// Montant signé en unités mineures (négatif = sortie / dette accrue).
  final int amountMinor;

  /// Solde MoMo retirable après l'opération.
  final int payableAfter;

  /// Dette de commission cash après l'opération.
  final int debtAfter;

  /// Anti double-débit : identifiant de requête client idempotent.
  final String? clientRequestId;

  /// Référence source (ride id, ref transaction, etc.).
  final String? referenceId;

  final String? note;

  final DateTime createdAt;

  factory LedgerEntry.fromMap(Map<String, dynamic> m) {
    return LedgerEntry(
      id: (m['id'] as num).toInt(),
      devise: Devise.depuisCode(m['devise_code'] as String?),
      kind: (m['kind'] as String?) ?? 'ajustement',
      amountMinor: (m['amount_minor'] as num?)?.toInt() ?? 0,
      payableAfter: (m['payable_after'] as num?)?.toInt() ?? 0,
      debtAfter: (m['debt_after'] as num?)?.toInt() ?? 0,
      clientRequestId: m['client_request_id'] as String?,
      referenceId: m['reference_id'] as String?,
      note: m['note'] as String?,
      createdAt:
          DateTime.tryParse((m['created_at'] as String?) ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}

extension LedgerEntryLibelles on LedgerEntry {
  bool get estDebit => amountMinor < 0;

  String get libelle => switch (kind) {
    'cash_encaisse' => 'Cash encaissé',
    'commission_cash' => 'Commission course cash',
    'commission_momo' => 'Commission Mobile Money',
    'commission_travel' => 'Commission frais déplacement',
    'momo_paiement' => 'Paiement Mobile Money',
    'topup' => 'Recharge du wallet',
    'debit_commission' => 'Paiement de ma commission',
    'remboursement' => 'Remboursement',
    'ajustement' => 'Ajustement administrateur',
    _ => kind,
  };

  /// Montant signé : "+2 500 FCFA", "-350 FCFA", "0 FCFA".
  String amountFormatter() {
    final abs = Money.zero(devise).fromMinor(amountMinor.abs()).formatter();
    if (amountMinor < 0) return '-$abs';
    if (amountMinor > 0) return '+$abs';
    return abs;
  }

  /// Solde de poche affiché (jamais négatif à l'écran).
  String soldeFormatter(int minor) =>
      Money.zero(devise).fromMinor(minor < 0 ? 0 : minor).formatter();

  IconData get icone => switch (kind) {
    'cash_encaisse' => Icons.payments_rounded,
    'commission_cash' => Icons.receipt_long_rounded,
    'commission_momo' => Icons.receipt_long_rounded,
    'commission_travel' => Icons.alt_route_rounded,
    'momo_paiement' => Icons.account_balance_wallet_rounded,
    'topup' => Icons.add_card_rounded,
    'debit_commission' => Icons.currency_exchange_rounded,
    'remboursement' => Icons.replay_rounded,
    'ajustement' => Icons.tune_rounded,
    _ => Icons.receipt_outlined,
  };
}

/// Lecture du grand livre personnel du prestataire connecté.
/// La RLS `ledger_lecture_proprio` (script 12) ne renvoie que les
/// écritures du provider connecté — le service ne filtre rien lui-même.
class LedgerService {
  const LedgerService();

  /// Dernières écritures, de la plus récente à la plus ancienne.
  Future<List<LedgerEntry>> charger({int limite = 300}) async {
    final res = await Supabase.instance.client
        .from('ledger_entries')
        .select()
        .order('id', ascending: false)
        .limit(limite);
    final rows = res as List;
    return [
      for (final r in rows)
        LedgerEntry.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }
}
