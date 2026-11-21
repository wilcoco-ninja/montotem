import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Numéro Mobile Money de MONTOTEM sur lequel un conducteur / dépanneur
/// envoie sa recharge de wallet (table `payment_settings`, remplie par
/// l'administrateur).
class PaymentAccount {
  const PaymentAccount({
    required this.operateur,
    required this.numero,
    required this.titulaire,
  });

  final String operateur; // mtn | moov | celtiis
  final String numero;
  final String titulaire;

  String get libelleOperateur => switch (operateur) {
        'mtn' => 'MTN MoMo',
        'moov' => 'Moov Money',
        'celtiis' => 'Celtiis Cash',
        _ => operateur.toUpperCase(),
      };

  factory PaymentAccount.fromJson(Map<String, dynamic> json) => PaymentAccount(
        operateur: '${json['operateur'] ?? ''}'.toLowerCase(),
        numero: '${json['numero'] ?? ''}',
        titulaire: '${json['titulaire'] ?? ''}',
      );
}

class PaymentAccountService {
  const PaymentAccountService();

  /// Ne lève jamais : liste vide si la table est inaccessible.
  Future<List<PaymentAccount>> obtenirComptesPaiement() async {
    try {
      final data = await Supabase.instance.client
          .from('payment_settings')
          .select()
          .eq('actif', true);
      return (data as List)
          .whereType<Map>()
          .map((e) => PaymentAccount.fromJson(Map<String, dynamic>.from(e)))
          .where((c) => c.numero.isNotEmpty && c.operateur.isNotEmpty)
          .toList();
    } catch (e) {
      developer.log('obtenirComptesPaiement',
          error: e, name: 'PaymentAccountService');
      return const [];
    }
  }
}