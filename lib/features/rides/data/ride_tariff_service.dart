import 'dart:convert';
import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/core/storage/local_cache.dart';
import 'package:montotem/features/rides/domain/ride_tariff.dart';

/// Service de chargement des tarifs de course depuis Supabase / Cache local.
class RideTariffService {
  SupabaseClient get _sb => Supabase.instance.client;

  static const String _cleCache = 'ride_tariffs';

  Future<RideTariffs> charger() async {
    try {
      final rows = await _sb
          .from('app_config')
          .select('key, value_int')
          .inFilter('key', RideTariffs.cles);
      final tarifs = RideTariffs.fromRows(rows as List<dynamic>);
      await LocalCache.instance.ecrire(_cleCache, jsonEncode(tarifs.toRows()));
      return tarifs;
    } catch (e) {
      developer.log('Tarifs courses : repli',
          error: e, name: 'RideTariffService');
      final brut = LocalCache.instance.lire(_cleCache);
      if (brut != null) {
        try {
          final decoded = jsonDecode(brut);
          if (decoded is List) {
            return RideTariffs.fromRows(decoded);
          }
        } catch (_) {}
      }
      return const RideTariffs();
    }
  }
}
