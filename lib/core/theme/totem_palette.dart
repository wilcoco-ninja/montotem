import 'package:flutter/material.dart';

/// PALETTE « TOTEM » — l'identité visuelle originale de MonTotem.
///
/// Inspirée du Bénin, pas d'une application concurrente :
///  - Safran  : le jaune des chemises des Zémidjans de Cotonou ;
///  - Lagune  : le bleu profond du lac Nokoué et de la nuit sur l'eau ;
///  - Palme   : le vert des palmiers (tricycles Kloboto, transport de fret) ;
///  - Latérite: la terre rouge des pistes (décor, jamais du texte) ;
///  - Sable   : le fond chaud de l'harmattan (jour).
///
/// Tous les couples texte / fond ont été calculés (WCAG 2.x) : ≥ 7:1 (AAA).
class Totem {
  Totem._();

  // ── Couleurs de marque ────────────────────────────────────────────────
  static const Color safran = Color(0xFFFFC21A);
  static const Color onSafran = Color(0xFF1A1400); // sur safran : 11,3:1
  static const Color lagune = Color(0xFF0B4F6C); // blanc dessus : 8,9:1
  static const Color lagunePale = Color(0xFF5CC8E8);
  static const Color nuit = Color(0xFF08141F);
  static const Color palme = Color(0xFF3DDC97);
  static const Color onPalme = Color(0xFF052014); // sur palme : 9,7:1
  static const Color laterite = Color(0xFFD9542B); // décor uniquement
  static const Color sable = Color(0xFFFAF5EC);

  // ── Urgence ───────────────────────────────────────────────────────────
  static const Color urgence = Color(0xFFD32F2F); // gros texte blanc seulement
  static const Color urgenceProfond = Color(0xFFA31515); // blanc : 7,85:1
  static const Color urgenceClair =
      Color(0xFFFF9C94); // sur fond sombre : 9,2:1

  // ── Les « peaux » (skins) ─────────────────────────────────────────────

  /// Client, de jour : sable chaud + bleu lagune.
  static const TotemSkin clientJour = TotemSkin(
    name: 'client-jour',
    brightness: Brightness.light,
    bg: sable,
    surface: Color(0xFFFFFFFF),
    field: Color(0xFFFFFFFF),
    fieldLine: Color(0xFF7A8591),
    line: Color(0xFFE6DDCB),
    ink: Color(0xFF142130), // 15,0:1 sur sable
    inkSoft: Color(0xFF41505F), // 7,6:1 sur sable
    primary: lagune,
    onPrimary: Color(0xFFFFFFFF),
    accent: Color(0xFFFFB000),
    onAccent: onSafran,
    danger: urgenceProfond,
    radius: 18,
    buttonHeight: 58,
  );

  /// Client, de nuit : bleu lagune profond, cyan lumineux (OLED-friendly).
  static const TotemSkin clientNuit = TotemSkin(
    name: 'client-nuit',
    brightness: Brightness.dark,
    bg: nuit,
    surface: Color(0xFF0F2233),
    field: Color(0xFF152C42),
    fieldLine: Color(0xFF6B8CA8),
    line: Color(0xFF25405A),
    ink: Color(0xFFE8F1F8), // 16,3:1
    inkSoft: Color(0xFFB3C4D4), // 9,1:1
    primary: lagunePale, // sur nuit : 9,6:1
    onPrimary: Color(0xFF05202B), // sur cyan : 8,7:1
    accent: safran,
    onAccent: onSafran,
    danger: urgenceClair,
    radius: 18,
    buttonHeight: 58,
  );

  /// COCKPIT — conducteurs Zémidjan : asphalte noir + jaune safran,
  /// boutons à angles biseautés comme un panneau routier.
  static const TotemSkin cockpit = TotemSkin(
    name: 'cockpit-zemidjan',
    brightness: Brightness.dark,
    bg: Color(0xFF0D0F12),
    surface: Color(0xFF161A20),
    field: Color(0xFF1E242C),
    fieldLine: Color(0xFF6A7685),
    line: Color(0xFF2A323C),
    ink: Color(0xFFF5F7FA), // 17,9:1
    inkSoft: Color(0xFFB8C2CF), // 9,7:1
    primary: safran, // sur asphalte : 11,9:1
    onPrimary: onSafran,
    accent: palme,
    onAccent: onPalme,
    danger: urgenceClair,
    bevel: true,
    radius: 10,
    buttonHeight: 62,
  );

  /// COCKPIT — conducteurs Tricycle Kloboto (fret) : même asphalte,
  /// vert palme à la place du safran.
  static const TotemSkin cockpitPalme = TotemSkin(
    name: 'cockpit-kloboto',
    brightness: Brightness.dark,
    bg: Color(0xFF0D0F12),
    surface: Color(0xFF161A20),
    field: Color(0xFF1E242C),
    fieldLine: Color(0xFF6A7685),
    line: Color(0xFF2A323C),
    ink: Color(0xFFF5F7FA),
    inkSoft: Color(0xFFB8C2CF),
    primary: palme, // sur asphalte : 10,9:1
    onPrimary: onPalme,
    accent: safran,
    onAccent: onSafran,
    danger: urgenceClair,
    bevel: true,
    radius: 10,
    buttonHeight: 62,
  );

  /// ÉCO-BATTERIE : noir pur (un pixel noir OLED ne consomme rien),
  /// une seule couleur d'accent, aucun dégradé, aucune ombre.
  static const TotemSkin eco = TotemSkin(
    name: 'eco-batterie',
    brightness: Brightness.dark,
    bg: Color(0xFF000000),
    surface: Color(0xFF0A0A0A),
    field: Color(0xFF111111),
    fieldLine: Color(0xFF6E7681),
    line: Color(0xFF2B2B2B),
    ink: Color(0xFFEDEDED), // 17,9:1
    inkSoft: Color(0xFFA9B2BD), // 9,8:1
    primary: safran, // sur noir : 13,0:1
    onPrimary: onSafran,
    accent: safran,
    onAccent: onSafran,
    danger: urgenceClair,
    radius: 12,
    buttonHeight: 60,
  );
}

/// Ensemble cohérent de couleurs + formes pour un « monde » de l'application.
@immutable
class TotemSkin {
  const TotemSkin({
    required this.name,
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.field,
    required this.fieldLine,
    required this.line,
    required this.ink,
    required this.inkSoft,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.onAccent,
    required this.danger,
    this.bevel = false,
    this.radius = 16,
    this.buttonHeight = 58,
  });

  final String name;
  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color field;

  /// Bordure des champs (≥ 3:1 sur le fond du champ : contraste non textuel).
  final Color fieldLine;
  final Color line;
  final Color ink;
  final Color inkSoft;
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color onAccent;
  final Color danger;

  /// Angles biseautés (cockpit) au lieu de boutons en pilule.
  final bool bevel;
  final double radius;
  final double buttonHeight;

  bool get dark => brightness == Brightness.dark;
}
