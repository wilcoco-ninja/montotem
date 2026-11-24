import 'package:flutter/foundation.dart';

/// Bornes alignées sur la contrainte SQL de wallet_topup_requests.
const int kRechargeMinFcfa = 500;
const int kRechargeMaxFcfa = 1000000;

enum StatutRecharge { enAttente, validee, refusee }

@immutable
class TopupRequest {
  const TopupRequest({
    required this.id,
    required this.amountFcfa,
    required this.operateur,
    required this.transactionRef,
    required this.statut,
    required this.createdAt,
    this.motifRefus,
  });

  factory TopupRequest.fromJson(Map<String, dynamic> j) => TopupRequest(
    id: '${j['id']}',
    amountFcfa: (j['amount_fcfa'] as num?)?.toInt() ?? 0,
    operateur: '${j['operateur'] ?? ''}',
    transactionRef: '${j['transaction_ref'] ?? ''}',
    statut: switch ('${j['statut']}') {
      'approved' => StatutRecharge.validee,
      'rejected' => StatutRecharge.refusee,
      _ => StatutRecharge.enAttente,
    },
    motifRefus: j['rejection_reason'] as String?,
    createdAt:
        DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
  );

  final String id;
  final int amountFcfa;
  final String operateur; // mtn | moov | celtiis
  final String transactionRef;
  final StatutRecharge statut;
  final String? motifRefus;
  final DateTime createdAt;

  String get libelleOperateur => switch (operateur) {
    'mtn' => 'MTN MoMo',
    'moov' => 'Moov Money',
    'celtiis' => 'Celtiis Cash',
    _ => operateur.toUpperCase(),
  };
}
