import 'package:flutter/material.dart';

import 'totem_palette.dart';

/// Les QUATRE « mondes » de MONTOTEM. Chacun a sa propre identité visuelle,
/// sa propre porte d'entrée et son propre mode de connexion :
///
///  - client      : numéro de téléphone + code SMS (aucun mot de passe) ;
///  - driver      : conducteur Zémidjan / Cloboto / Kloboto, cockpit jaune ;
///  - prestataire : e-mail ou téléphone + mot de passe, dossier vérifié ;
///  - admin       : e-mail + mot de passe, console non liée au site public.
enum AppSpace { client, driver, provider, admin }

/// Couleurs propres à chaque espace (hors thème commun [AppColors]).
class SpaceColors {
  SpaceColors._();

  // ── Client : bleu lagune, fond sable d'harmattan ────────────────────────
  static const Color clientPrimary = Totem.lagune;
  static const Color clientPrimaryDeep = Color(0xFF073A50);
  static const Color clientPrimarySoft = Totem.lagunePale;
  static const Color clientBg = Totem.sable;
  static const Color clientBgDark = Totem.nuit;
  static const Color clientSurfaceDark = Color(0xFF0F2233);

  // ── Driver : cockpit asphalte noir + jaune safran ───────────────────────
  static const Color driverBg = Color(0xFF0D0F12);
  static const Color driverSurface = Color(0xFF161A20);
  static const Color driverSurfaceAlt = Color(0xFF1E242C);
  static const Color driverLine = Color(0xFF2A323C);
  static const Color driverAccent = Color(0xFFFFC400); // jaune safran
  static const Color driverOnAccent = Color(0xFF1A1400); // sur safran
  static const Color driverInk = Color(0xFFF5F7FA);
  static const Color driverInkSoft = Color(0xFFB8C2CF);

  // ── Prestataire : encre + orange signal (toujours sombre) ───────────────
  static const Color proBg = Color(0xFF0E1217);
  static const Color proSurface = Color(0xFF171D26);
  static const Color proSurfaceAlt = Color(0xFF1F2733);
  static const Color proLine = Color(0xFF2C3746);
  static const Color proAccent = Color(0xFFFF8A1F);
  static const Color proOnAccent = Color(0xFF1A1206);
  static const Color proInk = Color(0xFFF2F4F7);
  static const Color proInkSoft = Color(0xFFB4BFCC);

  // ── Admin : ardoise + vert-bleu sobre (toujours clair, dense) ───────────
  static const Color adminBg = Color(0xFFEDF0F4);
  static const Color adminPrimary = Color(0xFF0F4C5C);
  static const Color adminRail = Color(0xFF0B2F39);
  static const Color adminLine = Color(0xFFC9D1DB);
  static const Color adminInk = Color(0xFF16212B);
  static const Color adminInkSoft = Color(0xFF4A5868);
}

/// Détermine l'espace d'une adresse.
class AppSpaces {
  AppSpaces._();

  /// Règles, dans l'ordre :
  ///  1. `?space=client|driver|provider|admin` force l'espace ;
  ///  2. `/admin/...` → admin ;
  ///  3. `/driver/...`, `/register/driver...` → driver ;
  ///  4. `/provider/...`, `/pro/...`, `/register/provider...`,
  ///     `/register/transport...` ou `/register/...?role=provider`
  ///     → prestataire ;
  ///  5. tout le reste → client.
  static AppSpace fromUri(Uri uri) {
    final forced = uri.queryParameters['space'];
    if (forced == 'client') return AppSpace.client;
    if (forced == 'driver') return AppSpace.driver;
    if (forced == 'provider') return AppSpace.provider;
    if (forced == 'admin') return AppSpace.admin;

    final p = uri.path;
    if (p == '/admin' || p.startsWith('/admin/')) return AppSpace.admin;
    if (p == '/driver' || p.startsWith('/driver/')) return AppSpace.driver;
    if (p.startsWith('/register/driver')) return AppSpace.driver;
    if (p == '/provider' || p.startsWith('/provider/')) {
      return AppSpace.provider;
    }
    if (p == '/pro' || p.startsWith('/pro/')) return AppSpace.provider;
    if (p.startsWith('/register/provider')) return AppSpace.provider;
    if (p.startsWith('/register/transport')) return AppSpace.provider;
    if (p.startsWith('/register') &&
        uri.queryParameters['role'] == 'provider') {
      return AppSpace.provider;
    }
    return AppSpace.client;
  }

  /// Page de connexion propre à chaque espace (une porte par rôle).
  static String door(AppSpace space) => switch (space) {
        AppSpace.client => '/login',
        AppSpace.driver => '/driver/login',
        AppSpace.provider => '/pro/login',
        AppSpace.admin => '/admin/login',
      };
}