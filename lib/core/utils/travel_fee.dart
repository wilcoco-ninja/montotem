import 'dart:math' as math;

/// Calcul des frais de déplacement d'un prestataire.
///
/// frais = max(minimum, distance × tarif/km), arrondi aux 50 FCFA supérieurs.
/// Utilisé à la fois à l'inscription (simulateur) et sur la fiche prestataire
/// (estimation affichée au client avant qu'il ne contacte qui que ce soit).
class TravelFee {
  TravelFee._();

  static int estimate({
    required double km,
    required int tarifKmFcfa,
    required int minimumFcfa,
  }) {
    if (km.isNaN || km < 0) return minimumFcfa;
    final brut = km * tarifKmFcfa;
    final arrondi = ((brut / 50).ceil()) * 50;
    return math.max(arrondi, minimumFcfa);
  }

  /// "12 500 FCFA"
  static String fcfa(int v) {
    final s = v.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return '$b FCFA';
  }
}
