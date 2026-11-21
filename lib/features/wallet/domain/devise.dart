import 'package:flutter/foundation.dart';

/// Modes d'arrondi par devise — miroir exact de `devises.rounding_mode`
/// (script SQL finance/11 : ROUND | FLOOR | CEIL).
enum ArrondiMode {
  arrondi,
  plancher,
  plafond;

  static ArrondiMode depuisCode(String? code) =>
      switch (code?.toUpperCase()) {
        'FLOOR' => ArrondiMode.plancher,
        'CEIL' => ArrondiMode.plafond,
        _ => ArrondiMode.arrondi,
      };
}

/// Devise référentielle — miroir exact de la table PostgreSQL `devises`
/// (script finance/11). `minorUnits` : 0 (XOF/XAF, unité entière) ou 2
/// (NGN/KES/GHS, kobo/cents/pesewas). Les montants sont TOUJOURS manipulés
/// en unités mineures entières, jamais en double.
@immutable
class Devise {
  const Devise({
    required this.code,
    required this.libelle,
    required this.minorUnits,
    required this.arrondi,
    required this.symbole,
  });

  final String code;
  final String libelle;
  final int minorUnits;
  final ArrondiMode arrondi;
  final String symbole;

  static const XOF = Devise(
    code: 'XOF',
    libelle: 'Franc CFA (UEMOA)',
    minorUnits: 0,
    arrondi: ArrondiMode.arrondi,
    symbole: 'FCFA',
  );
  static const XAF = Devise(
    code: 'XAF',
    libelle: 'Franc CFA (CEMAC)',
    minorUnits: 0,
    arrondi: ArrondiMode.arrondi,
    symbole: 'FCFA',
  );
  static const NGN = Devise(
    code: 'NGN',
    libelle: 'Naira nigérian',
    minorUnits: 2,
    arrondi: ArrondiMode.plancher,
    symbole: '₦',
  );
  static const KES = Devise(
    code: 'KES',
    libelle: 'Shilling kényan',
    minorUnits: 2,
    arrondi: ArrondiMode.arrondi,
    symbole: 'KSh',
  );
  static const GHS = Devise(
    code: 'GHS',
    libelle: 'Cedi ghanéen',
    minorUnits: 2,
    arrondi: ArrondiMode.arrondi,
    symbole: 'GH₵',
  );

  static const List<Devise> toutes = [XOF, XAF, NGN, KES, GHS];

  static Devise? _parCode(String? code) {
    final c = code?.toUpperCase().trim() ?? '';
    for (final d in toutes) {
      if (d.code == c) return d;
    }
    return null;
  }

  static Devise get defaut => XOF;

  /// Devise par code avec repli sûr sur XOF (le serveur reste la référence) ;
  /// un `minorUnits` / `rounding_mode` venant de la table `devises` a la
  /// priorité s'il est fourni.
  static Devise depuisCode(String? code,
      {int? minorUnits, String? roundingMode}) {
    final base = _parCode(code) ?? defaut;
    if (minorUnits == null && roundingMode == null) return base;
    final unites = (minorUnits == 0 || minorUnits == 2)
        ? minorUnits
        : base.minorUnits;
    final mode = roundingMode == null
        ? base.arrondi
        : ArrondiMode.depuisCode(roundingMode);
    return Devise(
      code: base.code,
      libelle: base.libelle,
      minorUnits: unites,
      arrondi: mode,
      symbole: base.symbole,
    );
  }

  /// Devise d'une ville : miroir exact de la table `zones` (script finance/11).
  /// Ville inconnue ⇒ XOF (défaut du projet, jamais un taux côté client).
  static Devise depuisVille(String? ville) {
    final v = ville?.toLowerCase().trim() ?? '';
    if (v.isEmpty) return XOF;
    const nigerian = ['lagos', 'badagry', 'ilorin'];
    const kenyans = ['nairobi', 'mombasa'];
    const ghaneens = ['accra', 'kumasi', 'ho'];
    if (nigerian.contains(v)) return NGN;
    if (kenyans.contains(v)) return KES;
    if (ghaneens.contains(v)) return GHS;
    // Bénin + toute autre ville non répertoriée : XOF.
    return XOF;
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'libelle': libelle,
        'minor_units': minorUnits,
        'rounding_mode': arrondi.name,
        'symbole': symbole,
      };

  @override
  bool operator ==(Object other) =>
      other is Devise && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

/// Montant multi-devise exprimé en unités mineures (int uniquement,
/// jamais en double flottant).
@immutable
class Money implements Comparable<Money> {
  const Money._(this.minorUnits, this.devise);

  final int minorUnits;
  final Devise devise;

  static Money zero(Devise devise) => Money._(0, devise);

  Money fromMinor(int minor) => Money._(minor, devise);

  /// Construction sans perte depuis un entier "majeur" + partie mineure.
  /// Ex. : Money.depuisParties(1, 50, Devise.NGN) = 150 kobo.
  static Money depuisParties(int majeur, int mineur, Devise devise) {
    final facteur = devise.minorUnits == 0 ? 1 : 100;
    return Money._(majeur.abs() * facteur + mineur * (majeur < 0 ? -1 : 1),
        devise);
  }

  int get signe => minorUnits.sign;

  bool get estNegatif => minorUnits < 0;

  bool get estZero => minorUnits == 0;

  /// Partie entière (truncation vers zéro) en unités majeures.
  int get entier {
    if (devise.minorUnits == 0) return minorUnits;
    final facteur = 100;
    final negatif = minorUnits < 0;
    final abs = minorUnits.abs();
    final e = abs ~/ facteur;
    return negatif ? -e : e;
  }

  /// Partie mineure positive (0..99 pour 2 décimales, 0 pour XOF).
  int get partieMineure {
    if (devise.minorUnits == 0) return 0;
    final abs = minorUnits.abs();
    return abs % 100;
  }

  Money operator +(Money autre) =>
      Money._(minorUnits + _verifier(autre).minorUnits, devise);

  Money operator -() => Money._(-minorUnits, devise);

  Money operator -(Money autre) =>
      Money._(minorUnits - _verifier(autre).minorUnits, devise);

  /// Multiply par un facteur entier (quantité, etc.) — jamais par un double.
  Money fois(int facteur) => Money._(minorUnits * facteur, devise);

  /// Pourcentage avec l'arrondi explicite de la devise (miroir serveur).
  /// [taux] en pour-cent entier (ex. 15 = 15 %).
  Money pourcent(int taux) {
    final brut = switch (devise.arrondi) {
      ArrondiMode.plancher => (minorUnits * taux) ~/ 100,
      ArrondiMode.plafond => (minorUnits * taux / 100).ceil(),
      ArrondiMode.arrondi => _roundHalfUp(minorUnits * taux, 100),
    };
    return Money._(brut, devise);
  }

  /// Appliqué au centième pour éviter la dérive flottante : (a * b / 100)
  /// équivaut ici à (a * b / c) en entiers avec arrondi 0,5 vers +∞.
  static int _roundHalfUp(int numerateur, int denominateur) {
    final negatif = numerateur < 0;
    final absN = numerateur.abs();
    final q = absN ~/ denominateur;
    final reste2 = (absN % denominateur) * 2;
    final v = reste2 >= denominateur ? q + 1 : q;
    return negatif ? -v : v;
  }

  Money _verifier(Money autre) {
    if (autre.devise != devise) {
      throw ArgumentError(
          'Devises incompatibles : ${devise.code} vs ${autre.devise.code}');
    }
    return autre;
  }

  @override
  int compareTo(Money autre) {
    _verifier(autre);
    return minorUnits.compareTo(autre.minorUnits);
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.minorUnits == minorUnits &&
      other.devise == devise;

  @override
  int get hashCode => Object.hash(minorUnits, devise);

  String get code => devise.code;

  @override
  String toString() => formatter();
}

extension MoneyFormat on Money {
  /// "2 500 FCFA", "1 234,56 ₦". Séparateur de milliers = espace,
  /// séparateur décimal = virgule (usage Bénin/Afrique de l'Ouest).
  String formatter() {
    final negatif = minorUnits < 0;
    final abs = minorUnits.abs();
    final d = devise;
    final String corps;
    if (d.minorUnits == 0) {
      corps = _grp(abs);
    } else {
      final e = abs ~/ 100;
      final m = (abs % 100).toString().padLeft(2, '0');
      corps = '${_grp(e)},$m';
    }
    final signe = negatif ? '-' : '';
    final espace = d.symbole.startsWith(RegExp(r'[A-Za-z]')) ? ' ' : '';
    return '$signe$corps$espace${d.symbole}';
  }

  String _grp(int n) {
    final s = n.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}
