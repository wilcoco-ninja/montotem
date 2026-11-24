enum PayMethod {
  mtn('mtn', 'MTN MoMo'),
  moov('moov', 'Moov Money'),
  celtiis('celtiis', 'Celtiis Cash'),
  especes('especes', 'Espèces');

  const PayMethod(this.code, this.libelle);
  final String code;
  final String libelle;

  bool get mobileMoney => this != PayMethod.especes;

  static PayMethod fromCode(String? c) => PayMethod.values.firstWhere(
    (m) => m.code == c,
    orElse: () => PayMethod.especes,
  );
}

/// Numéro Mobile Money du prestataire, visible du client pendant la mission.
class MomoAccount {
  const MomoAccount({
    required this.methode,
    required this.numero,
    this.titulaire,
  });

  final PayMethod methode;
  final String numero;
  final String? titulaire;

  factory MomoAccount.fromJson(Map<String, dynamic> j) => MomoAccount(
    methode: PayMethod.fromCode(j['operateur'] as String?),
    numero: '${j['numero'] ?? ''}',
    titulaire: j['titulaire'] as String?,
  );
}

enum PaymentStatus { enAttente, confirme, refuse }

class MissionPayment {
  const MissionPayment({
    required this.id,
    required this.missionId,
    required this.kind,
    required this.amountFcfa,
    required this.methode,
    required this.payerPhone,
    required this.status,
    required this.createdAt,
    this.reference,
    this.rejectReason,
  });

  final String id;
  final String missionId;
  final String kind; // trajet | reparation
  final int amountFcfa;
  final PayMethod methode;
  final String payerPhone;
  final String? reference;
  final PaymentStatus status;
  final String? rejectReason;
  final DateTime createdAt;

  String get libelleType =>
      kind == 'trajet' ? 'Frais de déplacement' : 'Réparation';

  factory MissionPayment.fromJson(Map<String, dynamic> j) {
    final PaymentStatus statut = j['confirmed_at'] != null
        ? PaymentStatus.confirme
        : (j['rejected_at'] != null
              ? PaymentStatus.refuse
              : PaymentStatus.enAttente);
    return MissionPayment(
      id: '${j['id']}',
      missionId: '${j['mission_id']}',
      kind: '${j['kind']}',
      amountFcfa: (j['amount_fcfa'] as num?)?.toInt() ?? 0,
      methode: PayMethod.fromCode(j['operateur'] as String?),
      payerPhone: '${j['payer_phone'] ?? ''}',
      reference: j['reference'] as String?,
      status: statut,
      rejectReason: j['reject_reason'] as String?,
      createdAt:
          DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
    );
  }
}
