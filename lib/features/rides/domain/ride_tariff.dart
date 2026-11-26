/// Modèle de tarification des courses, piloté par `app_config`.
///
/// Les clés `ride_<service>_base_fcfa` et `ride_<service>_per_km_fcfa` sont
/// la source officielle ; elles sont modifiables depuis l'écran admin
/// « Tarifs & prix » (F-19). Le serveur recalcule de toute façon un prix
/// minimum identique dans create_ride, donc estimation et facturation
/// restent cohérentes.
class RideTariff {
  const RideTariff({
    required this.baseFcfa,
    required this.kmFcfa,
    this.minuteFcfa = 0,
    this.minFcfa = 100,
    this.maxSurgePct = 40,
  });

  final int baseFcfa;
  final int kmFcfa;
  final int minuteFcfa;
  final int minFcfa;
  final int maxSurgePct;

  int estimer(
    int distanceMeters, {
    int durationSeconds = 0,
    double surgeMultiplier = 1.0,
  }) {
    final km = distanceMeters / 1000.0;
    final minutes = durationSeconds / 60.0;
    final effectiveSurge = surgeMultiplier.clamp(
      1.0,
      1.0 + (maxSurgePct / 100.0),
    );

    final brut =
        (baseFcfa + (km * kmFcfa) + (minutes * minuteFcfa)) * effectiveSurge;
    return brut.round().clamp(minFcfa, 500000);
  }

  factory RideTariff.fromJson(Map json) {
    return RideTariff(
      baseFcfa: (json['base_fcfa'] as num?)?.toInt() ?? 300,
      kmFcfa: (json['km_fcfa'] as num?)?.toInt() ?? 150,
      minuteFcfa: (json['minute_fcfa'] as num?)?.toInt() ?? 0,
      minFcfa: (json['min_fcfa'] as num?)?.toInt() ?? 100,
      maxSurgePct: (json['max_surge_pct'] as num?)?.toInt() ?? 40,
    );
  }
}

class RideTariffs {
  const RideTariffs({
    this.zemidjan = const RideTariff(
      baseFcfa: 300,
      kmFcfa: 150,
    ),
    this.cloboto = const RideTariff(
      baseFcfa: 500,
      kmFcfa: 200,
    ),
    this.kloboto = const RideTariff(
      baseFcfa: 700,
      kmFcfa: 300,
    ),
  });

  final RideTariff zemidjan;
  final RideTariff cloboto;
  final RideTariff kloboto;

  /// Tarif applicable selon le type de course choisi.
  RideTariff pour(dynamic kind) {
    final code = kind.toString().toLowerCase();
    if (code.contains('fret') || code.contains('kloboto')) return kloboto;
    if (code.contains('passenger') || code.contains('cloboto')) return cloboto;
    return zemidjan;
  }

  /// Clés `app_config` (base + /km pour les 3 services de transport).
  static const List<String> cles = [
    'ride_zemidjan_base_fcfa',
    'ride_zemidjan_per_km_fcfa',
    'ride_cloboto_base_fcfa',
    'ride_cloboto_per_km_fcfa',
    'ride_kloboto_base_fcfa',
    'ride_kloboto_per_km_fcfa',
  ];

  factory RideTariffs.fromRows(List rows) {
    const def = RideTariffs();
    var zem = def.zemidjan;
    var clo = def.cloboto;
    var klo = def.kloboto;

    for (final row in rows) {
      if (row is! Map) continue;
      final key = '${row['key'] ?? ''}';
      final val = (row['value_int'] as num?)?.toInt();
      if (val == null) continue;
      switch (key) {
        case 'ride_zemidjan_base_fcfa':
          zem = RideTariff(baseFcfa: val, kmFcfa: zem.kmFcfa);
        case 'ride_zemidjan_per_km_fcfa':
          zem = RideTariff(baseFcfa: zem.baseFcfa, kmFcfa: val);
        case 'ride_cloboto_base_fcfa':
          clo = RideTariff(baseFcfa: val, kmFcfa: clo.kmFcfa);
        case 'ride_cloboto_per_km_fcfa':
          clo = RideTariff(baseFcfa: clo.baseFcfa, kmFcfa: val);
        case 'ride_kloboto_base_fcfa':
          klo = RideTariff(baseFcfa: val, kmFcfa: klo.kmFcfa);
        case 'ride_kloboto_per_km_fcfa':
          klo = RideTariff(baseFcfa: klo.baseFcfa, kmFcfa: val);
      }
    }
    return RideTariffs(zemidjan: zem, cloboto: clo, kloboto: klo);
  }

  List<Map<String, Object?>> toRows() => [
    {
      'key': 'ride_zemidjan_base_fcfa',
      'value_int': zemidjan.baseFcfa,
    },
    {
      'key': 'ride_zemidjan_per_km_fcfa',
      'value_int': zemidjan.kmFcfa,
    },
    {
      'key': 'ride_cloboto_base_fcfa',
      'value_int': cloboto.baseFcfa,
    },
    {
      'key': 'ride_cloboto_per_km_fcfa',
      'value_int': cloboto.kmFcfa,
    },
    {
      'key': 'ride_kloboto_base_fcfa',
      'value_int': kloboto.baseFcfa,
    },
    {
      'key': 'ride_kloboto_per_km_fcfa',
      'value_int': kloboto.kmFcfa,
    },
  ];
}
