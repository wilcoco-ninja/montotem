/// Modèle de tarification pour les courses (version sans chevrons pour éviter toute corruption de copie)
class RideTariff {
  const RideTariff({
    required this.baseFcfa,
    required this.kmFcfa,
    required this.minuteFcfa,
    required this.minFcfa,
    required this.maxSurgePct,
  });

  final int baseFcfa;
  final int kmFcfa;
  final int minuteFcfa;
  final int minFcfa;
  final int maxSurgePct;

  int estimer(int distanceMeters,
      {int durationSeconds = 0, double surgeMultiplier = 1.0}) {
    final km = distanceMeters / 1000.0;
    final minutes = durationSeconds / 60.0;
    final effectiveSurge =
        surgeMultiplier.clamp(1.0, 1.0 + (maxSurgePct / 100.0));

    final brut =
        (baseFcfa + (km * kmFcfa) + (minutes * minuteFcfa)) * effectiveSurge;
    return brut.round().clamp(minFcfa, 500000);
  }

  factory RideTariff.fromJson(Map json) {
    return RideTariff(
      baseFcfa: (json['base_fcfa'] as num?)?.toInt() ?? 300,
      kmFcfa: (json['km_fcfa'] as num?)?.toInt() ?? 150,
      minuteFcfa: (json['minute_fcfa'] as num?)?.toInt() ?? 25,
      minFcfa: (json['min_fcfa'] as num?)?.toInt() ?? 500,
      maxSurgePct: (json['max_surge_pct'] as num?)?.toInt() ?? 40,
    );
  }
}

class RideTariffs {
  const RideTariffs({
    this.zemidjan = const RideTariff(
        baseFcfa: 250,
        kmFcfa: 120,
        minuteFcfa: 20,
        minFcfa: 400,
        maxSurgePct: 40),
    this.tricycleFret = const RideTariff(
        baseFcfa: 600,
        kmFcfa: 250,
        minuteFcfa: 40,
        minFcfa: 1000,
        maxSurgePct: 40),
  });

  final RideTariff zemidjan;
  final RideTariff tricycleFret;

  RideTariff pour(dynamic kind) {
    final code = kind.toString().toLowerCase();
    if (code.contains('tricycle') || code.contains('fret')) {
      return tricycleFret;
    }
    return zemidjan;
  }

  static const cles = ['zemidjan_tariff', 'tricycle_tariff'];

  factory RideTariffs.fromRows(List rows) {
    var zem = const RideTariff(
        baseFcfa: 250,
        kmFcfa: 120,
        minuteFcfa: 20,
        minFcfa: 400,
        maxSurgePct: 40);
    var tri = const RideTariff(
        baseFcfa: 600,
        kmFcfa: 250,
        minuteFcfa: 40,
        minFcfa: 1000,
        maxSurgePct: 40);

    for (final row in rows) {
      if (row is Map) {
        final key = '${row['key'] ?? ''}';
        final val = row['value_json'] ?? row['value_int'];
        if (key == 'zemidjan_tariff' && val is Map) {
          zem = RideTariff.fromJson(val);
        } else if (key == 'tricycle_tariff' && val is Map) {
          tri = RideTariff.fromJson(val);
        }
      }
    }
    return RideTariffs(zemidjan: zem, tricycleFret: tri);
  }

  List toRows() => [
        {
          'key': 'zemidjan_tariff',
          'value_json': {
            'base_fcfa': zemidjan.baseFcfa,
            'km_fcfa': zemidjan.kmFcfa,
            'minute_fcfa': zemidjan.minuteFcfa,
            'min_fcfa': zemidjan.minFcfa,
            'max_surge_pct': zemidjan.maxSurgePct,
          }
        },
        {
          'key': 'tricycle_tariff',
          'value_json': {
            'base_fcfa': tricycleFret.baseFcfa,
            'km_fcfa': tricycleFret.kmFcfa,
            'minute_fcfa': tricycleFret.minuteFcfa,
            'min_fcfa': tricycleFret.minFcfa,
            'max_surge_pct': tricycleFret.maxSurgePct,
          }
        },
      ];
}
