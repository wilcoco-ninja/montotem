import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../power/power_mode_controller.dart';

/// Position GPS simple (le GPS fonctionne SANS internet).
typedef TotemPosition = ({double lat, double lng});

/// Détresse hors ligne : un SMS part par le réseau téléphonique, pas par
/// internet. Il fonctionne donc quand l'app ne peut plus rien charger.
///
/// Le texte est volontairement sans accents spéciaux ni emojis : un SMS
/// 100 % « alphabet standard » tient en un seul message (160 caractères
/// par segment) au lieu de se couper en plusieurs.
class DistressService {
  DistressService._();

  static const String _cleContact = 'totem_contact_confiance';

  // ── Contact de confiance ──────────────────────────────────────────────
  static Future<String> contact() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_cleContact) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> enregistrerContact(String numero) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final propre = numero.replaceAll(RegExp(r'[^0-9+]'), '');
      if (propre.isEmpty) {
        await prefs.remove(_cleContact);
      } else {
        await prefs.setString(_cleContact, propre);
      }
    } catch (e) {
      developer.log('Contact', error: e, name: 'DistressService');
    }
  }

  // ── Position ──────────────────────────────────────────────────────────
  /// Position actuelle (GPS, sans internet) ; à défaut, dernière connue.
  static Future<TotemPosition?> position() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }

      try {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
        return (lat: p.latitude, lng: p.longitude);
      } catch (_) {
        if (kIsWeb) return null;
        final p = await Geolocator.getLastKnownPosition();
        if (p == null) return null;
        return (lat: p.latitude, lng: p.longitude);
      }
    } catch (e) {
      developer.log('Position', error: e, name: 'DistressService');
      return null;
    }
  }

  // ── Message ───────────────────────────────────────────────────────────
  static String composerMessage({
    TotemPosition? pos,
    int? batterie,
    DateTime? maintenant,
  }) {
    final t = maintenant ?? DateTime.now();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final b = StringBuffer(
      'SOS MonTotem. Je suis en panne et j\'ai besoin d\'aide. ',
    );
    if (pos != null) {
      final lat = pos.lat.toStringAsFixed(5);
      final lng = pos.lng.toStringAsFixed(5);
      b.write('Ma position: https://maps.google.com/?q=$lat,$lng ');
    } else {
      b.write('Position GPS indisponible, rappelez-moi. ');
    }
    if (batterie != null) b.write('Batterie: $batterie%. ');
    b.write('Heure: $hh:$mm.');
    return b.toString();
  }

  /// Ouvre l'application SMS avec le message prêt à envoyer.
  static Future<bool> ouvrirSms({
    String numero = '',
    required String corps,
  }) async {
    final sep = defaultTargetPlatform == TargetPlatform.iOS ? '&' : '?';
    final uri = Uri.parse(
      'sms:$numero${sep}body=${Uri.encodeComponent(corps)}',
    );
    try {
      return await launchUrl(uri);
    } catch (e) {
      developer.log('Ouverture SMS', error: e, name: 'DistressService');
      return false;
    }
  }

  /// Parcours complet « j'ai besoin d'aide MAINTENANT » : position GPS,
  /// niveau de batterie, SMS prêt à partir vers le contact de confiance.
  static Future<void> envoyerDetresse(
    BuildContext context,
    PowerModeController power,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Recherche de votre position GPS…'),
        duration: Duration(seconds: 3),
      ),
    );

    final pos = await position();
    final corps = composerMessage(
      pos: pos,
      batterie: power.batterieConnue ? power.niveau : null,
    );
    final numero = await contact();
    final ok = await ouvrirSms(numero: numero, corps: corps);

    if (!ok) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d\'ouvrir les SMS. Appelez les secours depuis l\'écran SOS.',
          ),
          duration: Duration(seconds: 6),
        ),
      );
    }
  }
}
