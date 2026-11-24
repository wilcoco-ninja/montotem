import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:montotem/features/emergency/domain/emergency_models.dart';

/// Numéros d'urgence par pays. Fonctionne sans réseau : fichier livré avec
/// l'application (54 pays d'Afrique), copie locale de la table serveur,
/// choix de l'utilisateur.
class EmergencyNumbersRepository {
  EmergencyNumbersRepository._();
  static final EmergencyNumbersRepository instance =
      EmergencyNumbersRepository._();

  static const String _kPays = 'sos_country_code';
  static const String _kPaysLat = 'sos_country_lat';
  static const String _kPaysLng = 'sos_country_lng';
  static const String _kPaysDate = 'sos_country_date';
  static const String _kCache = 'sos_numbers_cache';
  static const Distance _distance = Distance();

  /// Si le fichier embarqué est illisible : le Bénin (numéros officiels).
  static const CountryNumbers _secours = CountryNumbers(
    code: 'BJ',
    nom: 'Bénin',
    police: '117',
    fire: '118',
    ambulance: '112',
    general: '112',
    minLat: 6.04,
    maxLat: 12.34,
    minLng: 0.67,
    maxLng: 3.9,
    confiance: Confiance.officiel,
  );

  final Map<String, CountryNumbers> _map = {'BJ': _secours};
  List<CountryNumbers> _pays = const [_secours];

  String? _choix;
  double? _choixLat;
  double? _choixLng;
  DateTime? _choixDate;
  bool _pret = false;

  List<CountryNumbers> get pays => List.unmodifiable(_pays);

  /// Code choisi par l'utilisateur (null = détection automatique).
  String? get choixManuel => _choix;

  Future<void> init() async {
    if (_pret) return;
    try {
      final brut = await rootBundle.loadString('assets/emergency_numbers.json');
      _appliquer(jsonDecode(brut) as List);
    } catch (e) {
      developer.log('fichier numéros', error: e, name: 'EmergencyNumbers');
    }
    final prefs = await SharedPreferences.getInstance();
    _choix = prefs.getString(_kPays);
    _choixLat = prefs.getDouble(_kPaysLat);
    _choixLng = prefs.getDouble(_kPaysLng);
    final d = prefs.getString(_kPaysDate);
    _choixDate = d == null ? null : DateTime.tryParse(d);
    final cache = prefs.getString(_kCache);
    if (cache != null) {
      try {
        _appliquer(jsonDecode(cache) as List);
      } catch (_) {}
    }
    _pret = true;
  }

  static String _cle(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll('ç', 'c')
      .replaceAll('à', 'a');

  void _appliquer(List liste) {
    for (final e in liste.whereType<Map>()) {
      final j = Map<String, dynamic>.from(e);
      var c = CountryNumbers.fromJson(j);
      if (c.code.length != 2) continue;
      // Une ligne sans niveau de confiance (ancienne copie) garde celui déjà connu.
      final avant = _map[c.code];
      if (j['confidence'] == null && avant != null) {
        c = c.avecConfiance(avant.confiance);
      }
      _map[c.code] = c;
    }
    _pays = _map.values.toList()
      ..sort((a, b) => _cle(a.nom).compareTo(_cle(b.nom)));
  }

  /// Met à jour la liste depuis le serveur. N'échoue jamais.
  Future<void> synchroniser() async {
    try {
      final data = await Supabase.instance.client
          .rpc('get_emergency_numbers')
          .timeout(const Duration(seconds: 6));
      if (data is! List) return;
      _appliquer(data);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCache, jsonEncode(data));
    } catch (e) {
      developer.log(
        'synchronisation numéros',
        error: e,
        name: 'EmergencyNumbers',
      );
    }
  }

  /// Un choix manuel reste valable à moins de 200 km du lieu où il a été fait
  /// (24 h s'il a été fait sans position) : un voyageur qui change de pays
  /// n'appelle pas le numéro de l'ancien pays.
  bool _choixValide(double? lat, double? lng) {
    if (_choix == null) return false;
    final date = _choixDate;
    if (date == null) return false;
    if (_choixLat == null || _choixLng == null) {
      return DateTime.now().difference(date) < const Duration(hours: 24);
    }
    if (lat == null || lng == null) {
      return DateTime.now().difference(date) < const Duration(days: 7);
    }
    return _distance.as(
          LengthUnit.Kilometer,
          LatLng(_choixLat!, _choixLng!),
          LatLng(lat, lng),
        ) <
        200;
  }

  /// Ordre : choix de l'utilisateur, zone GPS (avec pays candidats près d'une
  /// frontière), pays du téléphone, numéro international.
  ResolutionPays resolution({double? lat, double? lng}) {
    if (_choixValide(lat, lng)) {
      final saved = _choix!;
      if (saved == '--') {
        return const ResolutionPays(CountryNumbers.universel, choisi: true);
      }
      final p = _map[saved];
      if (p != null) return ResolutionPays(p, choisi: true);
    }

    final locale = PlatformDispatcher.instance.locale.countryCode
        ?.toUpperCase();

    if (lat != null && lng != null) {
      final candidats = _pays.where((p) => p.contient(lat, lng)).toList()
        ..sort((a, b) => a.surface.compareTo(b.surface));
      if (candidats.length == 1) {
        return ResolutionPays(candidats.first, candidats: candidats);
      }
      if (candidats.length > 1) {
        final parLocale = candidats.where((p) => p.code == locale);
        final retenu = parLocale.isNotEmpty ? parLocale.first : candidats.first;
        return ResolutionPays(retenu, candidats: candidats);
      }
    }

    final p = locale == null ? null : _map[locale];
    if (p != null) return ResolutionPays(p);
    return const ResolutionPays(CountryNumbers.universel);
  }

  CountryNumbers resoudre({double? lat, double? lng}) =>
      resolution(lat: lat, lng: lng).pays;

  Future<void> choisirPays(String? code, {double? lat, double? lng}) async {
    _choix = code;
    _choixLat = lat;
    _choixLng = lng;
    _choixDate = code == null ? null : DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove(_kPays);
      await prefs.remove(_kPaysLat);
      await prefs.remove(_kPaysLng);
      await prefs.remove(_kPaysDate);
    } else {
      await prefs.setString(_kPays, code);
      await prefs.setString(_kPaysDate, _choixDate!.toIso8601String());
      if (lat != null && lng != null) {
        await prefs.setDouble(_kPaysLat, lat);
        await prefs.setDouble(_kPaysLng, lng);
      } else {
        await prefs.remove(_kPaysLat);
        await prefs.remove(_kPaysLng);
      }
    }
  }
}
