import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kkiapay_flutter_sdk/kkiapay_flutter_sdk.dart';

class PaymentResult {
  final bool success;
  final String? transactionId;
  final String? reference;
  final int? amount;
  final String? errorMessage;

  const PaymentResult.success({
    required this.transactionId,
    this.reference,
    this.amount,
  }) : success = true,
       errorMessage = null;

  const PaymentResult.failure(this.errorMessage)
    : success = false,
      transactionId = null,
      reference = null,
      amount = null;
}

class PaymentValidationException implements Exception {
  final String message;
  const PaymentValidationException(this.message);
  @override
  String toString() => message;
}

class PaymentService {
  static const bool _sandboxFromEnv = bool.fromEnvironment(
    'KKIAPAY_SANDBOX',
    defaultValue: true,
  );

  // Formats béninois à 8 ou 10 chiffres avec indicatif 229.
  static final RegExp _phoneRegex = RegExp(r'^229\d{8,10}$');

  void _log(String message) {
    if (kDebugMode) debugPrint('[PaymentService] $message');
  }

  String _genererReference() =>
      'MONTOTEM-${DateTime.now().millisecondsSinceEpoch}';

  /// Nettoie et normalise le numéro au format 229XXXXXXXX.
  String normaliserTelephone(String rawPhone) {
    String cleaned = rawPhone.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
    if (!cleaned.startsWith('229') &&
        (cleaned.length == 8 || cleaned.length == 10)) {
      cleaned = '229$cleaned';
    }
    return cleaned;
  }

  void _validerEntrees({required int amount, required String phone}) {
    if (amount <= 0) {
      throw const PaymentValidationException(
        'Le montant doit être supérieur à 0 FCFA.',
      );
    }
    if (!_phoneRegex.hasMatch(phone)) {
      throw const PaymentValidationException(
        'Numéro invalide. Format attendu : 229XXXXXXXX ou 22901XXXXXXXX.',
      );
    }
  }

  /// [reference] : référence serveur (RPC `create_payment_intent`). Elle est
  /// transmise à KKiaPay dans le champ `data` pour le rapprochement.
  Future<void>? lancerPaiement({
    required BuildContext context,
    required int amount,
    required String phone,
    required String name,
    required String apiKey,
    String? reference,
    String? email,
    String reason = 'Paiement MONTOTEM',
    String? callbackUrl,
    String? partnerId,
    bool? sandbox,
    void Function(String transactionId, int? amount)? onSuccess,
    void Function(String reason)? onFailure,
  }) {
    final phoneNormalise = normaliserTelephone(phone);

    try {
      _validerEntrees(amount: amount, phone: phoneNormalise);
    } on PaymentValidationException catch (e) {
      onFailure?.call(e.message);
      return null;
    }

    final ref = reference ?? _genererReference();
    _log('Ouverture paiement — ref=$ref, montant=$amount FCFA');

    void paymentCallback(Map<String, dynamic> response, BuildContext ctx) {
      final status = response['status'] as String?;
      switch (status) {
        case PAYMENT_SUCCESS:
          final transactionId = response['transactionId']?.toString() ?? '';
          final paidAmount =
              (response['requestData']?['amount'] as num?)?.toInt() ?? amount;
          _log('Paiement réussi — id=$transactionId');
          if (ctx.mounted && Navigator.canPop(ctx)) {
            Navigator.pop(ctx);
          }
          onSuccess?.call(transactionId, paidAmount);
          break;
        case PAYMENT_CANCELLED:
          _log('Paiement annulé par l\'utilisateur');
          if (ctx.mounted && Navigator.canPop(ctx)) {
            Navigator.pop(ctx);
          }
          onFailure?.call('Paiement annulé par l\'utilisateur');
          break;
        case PAYMENT_INIT:
        case PENDING_PAYMENT:
          _log('Événement KKiaPay: $status');
          break;
        default:
          _log('Événement KKiaPay non géré: $status');
          break;
      }
    }

    try {
      final kkiapay = KKiaPay(
        amount: amount,
        phone: phoneNormalise,
        name: name,
        email: email ?? '',
        reason: reason,
        data: ref,
        apikey: apiKey,
        sandbox: sandbox ?? _sandboxFromEnv,
        callback: paymentCallback,
        theme: '#226D68',
        paymentMethods: const ['momo', 'card'],
        countries: const ['BJ'],
        callbackUrl: callbackUrl,
        partnerId: partnerId,
      );
      return Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => kkiapay),
      );
    } catch (e) {
      _log('Erreur au lancement du paiement: $e');
      onFailure?.call(
        'Impossible d\'ouvrir le paiement. Vérifiez votre connexion.',
      );
      return null;
    }
  }

  Future<PaymentResult> payer({
    required BuildContext context,
    required int amount,
    required String phone,
    required String name,
    required String apiKey,
    String? reference,
    String? email,
    String reason = 'Paiement MONTOTEM',
    String? callbackUrl,
    String? partnerId,
    bool? sandbox,
  }) {
    final completer = Completer<PaymentResult>();

    final routeFuture = lancerPaiement(
      context: context,
      amount: amount,
      phone: phone,
      name: name,
      apiKey: apiKey,
      reference: reference,
      email: email,
      reason: reason,
      callbackUrl: callbackUrl,
      partnerId: partnerId,
      sandbox: sandbox,
      onSuccess: (transactionId, paidAmount) {
        if (!completer.isCompleted) {
          completer.complete(
            PaymentResult.success(
              transactionId: transactionId,
              reference: reference,
              amount: paidAmount,
            ),
          );
        }
      },
      onFailure: (message) {
        if (!completer.isCompleted) {
          completer.complete(PaymentResult.failure(message));
        }
      },
    );

    if (routeFuture == null) return completer.future;

    routeFuture.then((_) {
      if (!completer.isCompleted) {
        completer.complete(
          const PaymentResult.failure('Paiement interrompu ou annulé.'),
        );
      }
    });

    return completer.future;
  }
}
