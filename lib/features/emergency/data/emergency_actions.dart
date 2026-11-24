import 'package:flutter/foundation.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Lance l'appel. Android : appel direct (permission CALL_PHONE), sinon le
/// composeur s'ouvre avec le numéro déjà saisi.
Future<bool> appelerNumero(String numero) async {
  final n = numero.replaceAll(RegExp(r'[^\d+*#]'), '');
  if (n.isEmpty) return false;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final ok = await FlutterPhoneDirectCaller.callNumber(n);
      if (ok == true) return true;
    } catch (_) {}
  }
  try {
    return await launchUrl(Uri(scheme: 'tel', path: n));
  } catch (_) {
    return false;
  }
}

String lienCarte(double lat, double lng) =>
    'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

/// SMS avec la position : passe par le réseau téléphonique, sans internet.
Future<bool> envoyerPositionSms({
  required String contact,
  required String situation,
  double? lat,
  double? lng,
}) async {
  final pos = (lat == null || lng == null)
      ? 'Position inconnue.'
      : 'Ma position : ${lienCarte(lat, lng)} '
            '(${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}).';
  final msg =
      'SOS : j\'ai besoin d\'aide ($situation). $pos '
      'Message envoyé depuis MONTOTEM.';
  final tel = contact.replaceAll(RegExp(r'[^\d+]'), '');
  try {
    return await launchUrl(
      Uri.parse('sms:$tel?body=${Uri.encodeComponent(msg)}'),
    );
  } catch (_) {
    return false;
  }
}

/// Ouvre une application de navigation (Google Maps, OsmAnd, Plans…).
Future<bool> ouvrirNavigation({
  required double lat,
  required double lng,
  String? libelle,
}) async {
  final nom = Uri.encodeComponent(libelle ?? 'Destination');
  final candidats = <Uri>[
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
      Uri.parse('https://maps.apple.com/?daddr=$lat,$lng&dirflg=d')
    else
      Uri.parse('geo:$lat,$lng?q=$lat,$lng($nom)'),
    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
  ];
  for (final u in candidats) {
    try {
      if (await launchUrl(u, mode: LaunchMode.externalApplication)) return true;
    } catch (_) {}
  }
  return false;
}

/// Proche à prévenir par SMS, enregistré sur le téléphone.
class SosContactStore {
  static const String _cle = 'sos_contact_phone';

  static Future<String?> lire() async =>
      (await SharedPreferences.getInstance()).getString(_cle);

  static Future<void> ecrire(String? valeur) async {
    final p = await SharedPreferences.getInstance();
    if (valeur == null || valeur.trim().isEmpty) {
      await p.remove(_cle);
    } else {
      await p.setString(_cle, valeur.trim());
    }
  }
}

/// Position GPS tolérante : ne lève jamais d'exception, marche sans internet.
class SosLocator {
  static Future<Position?> derniere() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  static Future<Position?> actuelle() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
