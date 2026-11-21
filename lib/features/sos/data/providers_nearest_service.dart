import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/features/tracking/domain/prestataire_model.dart';

class ProvidersNearestService {
  SupabaseClient get _sb => Supabase.instance.client;

  Future<List<Prestataire>> chercher({
    required LatLng position,
    String? kind,
    String? vehicule,
    double rayonKm = 15,
    int limite = 3,
  }) async {
    try {
      final data = await _sb.rpc('providers_nearest', params: {
        'p_lat': position.latitude,
        'p_lng': position.longitude,
        'p_kind': kind,
        'p_vehicle': vehicule,
        'p_radius_km': rayonKm,
        'p_limit': limite,
      });
      if (data is! List) return const [];
      return data.whereType<Map>().map((e) {
        final j = Map<String, dynamic>.from(e);
        return Prestataire(
          id: '${j['id']}',
          nom: '${j['nom'] ?? 'Prestataire'}',
          metier: '${j['metier'] ?? ''}',
          latitude: (j['latitude'] as num?)?.toDouble() ?? 0,
          longitude: (j['longitude'] as num?)?.toDouble() ?? 0,
          noteMoyenne: (j['note_moyenne'] as num?)?.toDouble() ?? 0,
          disponible: j['disponible'] == true,
          telephone: j['telephone'] as String?,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }
}
