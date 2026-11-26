import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Coût en points d'étoiles pour ouvrir un coffre.
const int kCoutCoffre = 15;

class FunException implements Exception {
  const FunException(this.message);

  /// Message lisible, déjà en français.
  final String message;

  @override
  String toString() => message;
}

/// Coffres d'étoiles : solde et dépense des points.
/// La dépense passe par la fonction SQL `depenser_etoiles` (F-18), qui
/// vérifie le solde côté serveur et inscrit l'opération dans le registre.
class FunService {
  SupabaseClient get _sb => Supabase.instance.client;

  /// Solde actuel de points d'étoiles du client connecté.
  Future<int> soldeEtoiles() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return 0;
    try {
      final row = await _sb
          .from('profiles')
          .select('star_points')
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return 0;
      return (row['star_points'] as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      developer.log('Solde étoiles', error: e, name: 'FunService');
      throw const FunException(
        'Solde indisponible. Vérifiez votre réseau et réessayez.',
      );
    }
  }

  /// Ouvre un coffre : dépense [cout] points (15 par défaut) via la fonction
  /// SQL côté serveur, puis renvoie le nouveau solde.
  Future<int> ouvrirCoffre({int cout = kCoutCoffre}) async {
    try {
      final solde = await _sb.rpc('depenser_etoiles', params: {'p_cout': cout});
      return (solde as num?)?.toInt() ?? 0;
    } on PostgrestException catch (e) {
      // L'exception SQL remonte avec son code métier dans le message.
      final brut = '${e.message} ${e.details ?? ''}';
      if (brut.contains('ETOILES_INSUFISANTES')) {
        throw const FunException(
          "Il vous manque des étoiles pour ce coffre. Gagnez-en en laissant "
          'des avis après vos courses !',
        );
      }
      if (brut.contains('NON_CONNECTE')) {
        throw const FunException('Connectez-vous pour ouvrir un coffre.');
      }
      developer.log('Ouverture coffre', error: e, name: 'FunService');
      throw const FunException(
        'Ouverture impossible. Vérifiez votre réseau et réessayez.',
      );
    }
  }
}
