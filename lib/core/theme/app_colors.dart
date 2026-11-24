import 'package:flutter/material.dart';

/// Source UNIQUE des couleurs MONTOTEM (« Design 50 ans »).
///
/// Tous les ratios ci-dessous sont des ratios WCAG 2.x réellement calculés.
/// Règle d'or : un TEXTE de taille normale doit atteindre 7:1 (AAA) ;
/// seuls les aplats rouges d'urgence portant un texte GROS et GRAS (≥ 19 px,
/// seuil « large text » = 4,5:1) utilisent le rouge #D32F2F demandé.
class AppColors {
  AppColors._();

  // ── Structure : Bleu Nuit ────────────────────────────────────────────────
  static const Color navy = Color(0xFF0B2545); // 15,4:1 sur blanc
  static const Color navySoft = Color(0xFF13315C); // 12,9:1 sur blanc
  static const Color navyOnDark = Color(0xFFA9C8F5); // 10,1:1 sur bgDark

  // ── Fonds ────────────────────────────────────────────────────────────────
  static const Color bgLight = Color(0xFFF4F6F9); // gris ardoise très doux
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color bgDark = Color(0xFF0F1B2D);
  static const Color surfaceDark = Color(0xFF16263D);

  // ── Encre (texte) ────────────────────────────────────────────────────────
  static const Color inkLight = Color(0xFF14202E); // 15,2:1 sur bgLight
  static const Color textSecondaryLight = Color(0xFF3E4C5E); // 8,1:1
  static const Color textTertiaryLight = Color(
    0xFF46566B,
  ); // 6,9:1 sur bgLight, 7,5:1 sur blanc
  static const Color inkDark = Color(0xFFEAF0F7); // 15,1:1 sur bgDark
  static const Color textSecondaryDark = Color(0xFFBDC9D8); // 10,3:1
  static const Color textTertiaryDark = Color(0xFFAEBBCB); // 8,9:1

  // ── Fonctionnelles : aplats (fonds, icônes, remplissages) ────────────────
  /// Rouge signalétique d'urgence. Blanc dessus = 4,98:1 : AAA uniquement
  /// pour du texte GROS et GRAS (≥ 19 px). Pour un texte normal, utiliser
  /// [emergencyStrong].
  static const Color emergency = Color(0xFFD32F2F);

  /// Rouge d'urgence profond : blanc dessus = 7,85:1 (AAA tout texte) ;
  /// sur fond clair = 7,25:1 (AAA en texte rouge).
  static const Color emergencyStrong = Color(0xFFA31515);

  /// Vert succès. Blanc dessus = 5,13:1 (gros texte seulement).
  static const Color success = Color(0xFF2E7D32);

  /// Ambre / or : aplat, étoiles sur fond sombre. Texte navy dessus = 8,6:1.
  static const Color amber = Color(0xFFFFB300);

  /// Or foncé pour étoiles/icônes sur fond clair (5,9:1 sur blanc).
  static const Color gold = Color(0xFF8A5A00);

  /// ✅ NOUVEAU — Jaune signature MonTotem (zémidjan, SOS, catégories).
  /// Sur navy #0B2545 = 11,2:1 (AAA). Toujours avec du texte navy dessus.
  /// Source unique du jaune : ne plus jamais écrire `Color(0xFFFFC400)`.
  static const Color brandYellow = Color(0xFFFFC400);

  // ── Fonctionnelles : TEXTE (AAA) ─────────────────────────────────────────
  static const Color successText = Color(0xFF1B5E20); // 7,3:1 sur bgLight
  static const Color amberText = Color(0xFF6B4400); // 7,9:1 sur bgLight
  static const Color emergencyTextDark = Color(0xFFFF9C94); // 8,6:1 sur bgDark
  static const Color successTextDark = Color(0xFF8FD99A); // 10,3:1 sur bgDark
  static const Color amberTextDark = Color(0xFFFFD36B); // 12,2:1 sur bgDark

  // ── Alias hérités (ne pas utiliser dans le nouveau code) ─────────────────
  /// Ancien « vert d'action » → vert succès.
  static const Color action = success;
  static const Color actionDark = Color(0xFF1B5E20);

  // ── Bandeau informatif neutre (SurvivalShell) ─────────────────────────────────
  static const Color proSurface = navySoft;
  static const Color proInk = Colors.white;

  // ── Outils de contraste ──────────────────────────────────────────────────
  /// Ratio de contraste WCAG entre deux couleurs.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Assombrit (fond clair) ou éclaircit (fond sombre) [fg] jusqu'à atteindre
  /// [min] contre [bg]. Garantit la lisibilité AAA de n'importe quelle teinte
  /// sémantique utilisée comme TEXTE ou comme icône informative.
  static Color ensureContrast(Color fg, Color bg, {double min = 7.5}) {
    if (contrast(fg, bg) >= min) return fg;
    final target = bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    for (var t = 0.05; t <= 1.0; t += 0.05) {
      final c = Color.lerp(fg, target, t)!;
      if (contrast(c, bg) >= min) return c;
    }
    return target;
  }
}

extension AppTextColors on BuildContext {
  bool get _isDark => Theme.of(this).brightness == Brightness.dark;

  Color get textPrimary => Theme.of(this).colorScheme.onSurface;

  /// Texte secondaire : couleur PLEINE, ≥ 8:1 (plus d'opacité qui fait
  /// chuter le contraste selon le fond).
  Color get textSecondary =>
      _isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

  /// Légendes : jamais sous 7:1 sur le blanc.
  Color get textTertiary =>
      _isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;

  /// Version lisible (AAA) d'une couleur sémantique utilisée comme TEXTE
  /// ou icône informative, calculée contre la surface courante.
  Color readable(Color c) =>
      AppColors.ensureContrast(c, Theme.of(this).colorScheme.surface);
}
