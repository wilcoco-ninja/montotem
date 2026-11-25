import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:montotem/core/theme/app_colors.dart';

/// Thème Material 3 de MONTOTEM (clair + sombre).
///
/// Toutes les couleurs viennent de [AppColors] (source unique, AAA validé).
/// Les constantes `AppTheme.primaryColor`, `errorColor`, etc. sont conservées
/// pour ne casser aucun écran existant : elles pointent vers la nouvelle
/// palette.
///
/// Compatibilité anciennes versions d'OS :
///  - InkRipple (et non InkSparkle, qui dépend de shaders Android 12+) ;
///  - transitions de page : celles par défaut de Flutter (ne pas les
///    redéfinir ici) ;
///  - style de barre d'état explicite pour rester lisible partout.
class AppTheme {
  AppTheme._();

  // ── Palette (alias vers AppColors) ───────────────────────────────────────
  static const Color primaryColor = AppColors.navy;
  static const Color primaryDark = Color(0xFF071A33);
  static const Color primaryLight = AppColors.navyOnDark;

  static const Color secondaryColor = AppColors.success;
  static const Color secondaryDark = AppColors.successText;

  static const Color warningColor = AppColors.amber;
  static const Color successColor = AppColors.success;
  static const Color errorColor = AppColors.emergency;

  // ── Rayons harmonisés (boutons 16, cartes 20) ────────────────────────────
  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 20;

  // ── Tailles tactiles (confort sur la route / en mouvement) ───────────────
  /// Surface de frappe minimale absolue.
  static const double minTap = 52;

  /// Hauteur standard des boutons.
  static const double buttonHeight = 56;

  static TextTheme _textTheme(Brightness brightness) {
    final base = ThemeData(brightness: brightness).textTheme;
    final ink = brightness == Brightness.light
        ? AppColors.inkLight
        : AppColors.inkDark;
    // La police est appliquée style par style (évite le conflit de types
    // TextTheme selon la version de google_fonts/Flutter).
    TextStyle? f(TextStyle? s) =>
        s == null ? null : GoogleFonts.plusJakartaSans(textStyle: s);

    return base
        .copyWith(
          displayLarge: f(base.displayLarge),
          displayMedium: f(base.displayMedium),
          displaySmall: f(base.displaySmall),
          headlineLarge: f(base.headlineLarge),
          headlineMedium: f(base.headlineMedium),
          headlineSmall: f(base.headlineSmall),
          titleLarge: f(base.titleLarge),
          titleMedium: f(base.titleMedium),
          titleSmall: f(base.titleSmall),
          bodyLarge: f(base.bodyLarge),
          bodyMedium: f(base.bodyMedium),
          bodySmall: f(base.bodySmall),
          labelLarge: f(base.labelLarge),
          labelMedium: f(base.labelMedium),
          labelSmall: f(base.labelSmall),
        )
        .apply(bodyColor: ink, displayColor: ink);
  }

  static ThemeData get lightTheme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final bg = isLight ? AppColors.bgLight : AppColors.bgDark;
    final surface = isLight ? AppColors.surfaceLight : AppColors.surfaceDark;
    final accent = isLight ? AppColors.navy : AppColors.navyOnDark;
    final onAccent = isLight ? Colors.white : AppColors.navy;
    final ink = isLight ? AppColors.inkLight : AppColors.inkDark;
    final textSecondary = isLight
        ? AppColors.textSecondaryLight
        : AppColors.textSecondaryDark;
    final textTertiary = isLight
        ? AppColors.textTertiaryLight
        : AppColors.textTertiaryDark;
    final danger = isLight
        ? AppColors.emergencyStrong
        : AppColors.emergencyTextDark;
    final line = isLight
        ? AppColors.navy.withValues(alpha: 0.16)
        : Colors.white.withValues(alpha: 0.18);

    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.navy,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary: onAccent,
          secondary: AppColors.success,
          onSecondary: Colors.white,
          tertiary: AppColors.amber,
          onTertiary: AppColors.navy,
          error: danger,
          onError: isLight ? Colors.white : AppColors.navy,
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: textSecondary,
        );

    final textTheme = _textTheme(brightness);

    OutlineInputBorder border(Color c, [double w = 1.2]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusMd),
      borderSide: BorderSide(color: c, width: w),
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusMd),
    );

    // Overlay (hover / pressed / focus) commun aux boutons
    WidgetStateProperty<Color?> overlay(Color base) =>
        WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.pressed)) {
            return base.withValues(alpha: 0.16);
          }
          if (s.contains(WidgetState.hovered)) {
            return base.withValues(alpha: 0.08);
          }
          if (s.contains(WidgetState.focused)) {
            return base.withValues(alpha: 0.14);
          }
          return null;
        });

    final overlayStyle =
        (isLight ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light)
            .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: bg,
              systemNavigationBarIconBrightness: isLight
                  ? Brightness.dark
                  : Brightness.light,
            );

    final btnText = GoogleFonts.plusJakartaSans(
      fontWeight: FontWeight.w800,
      fontSize: 16,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      materialTapTargetSize: MaterialTapTargetSize.padded,

      // ── AppBar plate et épurée ─────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: overlayStyle,
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        iconTheme: IconThemeData(color: ink, size: 26),
      ),

      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
        thumbColor: WidgetStatePropertyAll(ink.withValues(alpha: 0.35)),
      ),

      // ── Cartes (« SoftCards » : profondeur élégante) ───────────────────
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shadowColor: AppColors.navy.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: line),
        ),
      ),

      // ── Boutons : ≥ 56 dp, rayon 16, ombre discrète ────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, buttonHeight)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
          shape: WidgetStatePropertyAll(shape),
          elevation: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? 0
                : s.contains(WidgetState.pressed)
                ? 0
                : s.contains(WidgetState.hovered)
                ? 4
                : 2,
          ),
          shadowColor: WidgetStatePropertyAll(
            AppColors.navy.withValues(alpha: isLight ? 0.35 : 0.6),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? accent.withValues(alpha: 0.30)
                : accent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? onAccent.withValues(alpha: 0.7)
                : onAccent,
          ),
          overlayColor: overlay(onAccent),
          iconSize: const WidgetStatePropertyAll(22),
          textStyle: WidgetStatePropertyAll(btnText),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, buttonHeight),
          shape: shape,
          textStyle: btnText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, buttonHeight)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
          shape: WidgetStatePropertyAll(shape),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? ink.withValues(alpha: 0.38)
                : (isLight ? AppColors.navy : Colors.white),
          ),
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(
              color:
                  s.contains(WidgetState.focused) ||
                      s.contains(WidgetState.hovered)
                  ? accent
                  : accent.withValues(alpha: 0.65),
              width: 1.6,
            ),
          ),
          overlayColor: overlay(accent),
          iconSize: const WidgetStatePropertyAll(22),
          textStyle: WidgetStatePropertyAll(btnText),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, minTap)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          shape: WidgetStatePropertyAll(shape),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? ink.withValues(alpha: 0.38)
                : (isLight ? AppColors.navy : AppColors.navyOnDark),
          ),
          overlayColor: overlay(accent),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(minTap, minTap)),
          shape: WidgetStatePropertyAll(shape),
          overlayColor: overlay(accent),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, minTap)),
          shape: WidgetStatePropertyAll(shape),
          side: WidgetStatePropertyAll(BorderSide(color: line, width: 1.4)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? accent.withValues(alpha: 0.16)
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? ink : textSecondary,
          ),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
      // Avant : fond turquoise + texte blanc (2,3:1). Désormais bleu nuit.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: onAccent,
        elevation: 5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),

      // ── Champs de saisie ───────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: border(line),
        enabledBorder: border(textTertiary.withValues(alpha: 0.7)),
        focusedBorder: border(accent, 2.4),
        errorBorder: border(danger, 1.8),
        focusedErrorBorder: border(danger, 2.4),
        disabledBorder: border(line.withValues(alpha: 0.08)),
        labelStyle: TextStyle(color: textSecondary, fontSize: 15),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (s) => TextStyle(
            color: s.contains(WidgetState.error)
                ? danger
                : s.contains(WidgetState.focused)
                ? (isLight ? AppColors.navy : AppColors.navyOnDark)
                : textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        hintStyle: TextStyle(color: textTertiary, fontSize: 15),
        helperStyle: TextStyle(color: textSecondary, fontSize: 13.5),
        errorStyle: TextStyle(
          color: danger,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
        errorMaxLines: 3,
        prefixIconColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.error)
              ? danger
              : s.contains(WidgetState.focused)
              ? accent
              : textSecondary,
        ),
        suffixIconColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.focused) ? accent : textSecondary,
        ),
      ),

      // ── Divers ─────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: accent.withValues(alpha: 0.08),
        selectedColor: accent.withValues(alpha: 0.22),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: ink,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        side: BorderSide(color: line),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: isLight ? AppColors.navy : AppColors.navyOnDark,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 8,
        shape: shape,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: isLight ? AppColors.navy : AppColors.inkDark,
        contentTextStyle: TextStyle(
          color: isLight ? Colors.white : AppColors.navy,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
        actionTextColor: isLight ? AppColors.navyOnDark : AppColors.navy,
        shape: shape,
        elevation: 6,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.withValues(alpha: isLight ? 0.14 : 0.24),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w700,
            color: s.contains(WidgetState.selected) ? ink : textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 28,
            color: s.contains(WidgetState.selected) ? ink : textSecondary,
          ),
        ),
      ),
    );
  }
}
