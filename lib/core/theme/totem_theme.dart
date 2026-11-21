
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'totem_palette.dart';

/// Construit un thÃƒÂ¨me Material 3 complet ÃƒÂ  partir d'une [TotemSkin].
class TotemTheme {
  TotemTheme._();

  static final Map<String, ThemeData> _cache = {};

  static ThemeData of(TotemSkin skin) =>
      _cache.putIfAbsent(skin.name, () => build(skin));

  static ThemeData build(TotemSkin s) {
    final dark = s.dark;
    final eco = s.name == Totem.eco.name;

    final scheme = ColorScheme(
      brightness: s.brightness,
      primary: s.primary,
      onPrimary: s.onPrimary,
      secondary: s.accent,
      onSecondary: s.onAccent,
      error: s.danger,
      onError: dark ? Colors.black : Colors.white,
      surface: s.surface,
      onSurface: s.ink,
      onSurfaceVariant: s.inkSoft,
      outline: s.line,
      outlineVariant: s.line,
      surfaceContainerHighest: s.field,
    );

    final base = ThemeData(brightness: s.brightness, useMaterial3: true);

    // Utilisation de 'as dynamic' pour ÃƒÂ©viter le conflit de type TextTheme avec material_ui
    final fonted = s.bevel
        ? GoogleFonts.barlowTextTheme(base.textTheme as dynamic) as dynamic
        : GoogleFonts.plusJakartaSansTextTheme(base.textTheme as dynamic)
            as dynamic;

    final text = (fonted as dynamic).apply(
      fontSizeFactor: s.bevel ? 1.06 : 1.0,
      bodyColor: s.ink,
      displayColor: s.ink,
    );

    final OutlinedBorder btnShape = s.bevel
        ? BeveledRectangleBorder(borderRadius: BorderRadius.circular(s.radius))
        : const StadiumBorder();

    final TextStyle btnText = (s.bevel
            ? GoogleFonts.barlow(fontWeight: FontWeight.w800, fontSize: 19)
            : GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800, fontSize: 16.5))
        .copyWith(letterSpacing: s.bevel ? 0.8 : 0);

    OutlineInputBorder border(Color c, [double w = 1.4]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(s.radius),
          borderSide: BorderSide(color: c, width: w),
        );

    final overlayStyle =
        (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
            .copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: s.bg,
      systemNavigationBarIconBrightness:
          dark ? Brightness.light : Brightness.dark,
    );

    WidgetStateProperty<Color?> overlay(Color c) =>
        WidgetStateProperty.resolveWith((st) {
          if (st.contains(WidgetState.pressed)) {
            return c.withValues(alpha: 0.18);
          }
          if (st.contains(WidgetState.hovered)) {
            return c.withValues(alpha: 0.08);
          }
          if (st.contains(WidgetState.focused)) {
            return c.withValues(alpha: 0.16);
          }
          return null;
        });

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: s.bg,
      textTheme: text as TextTheme,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: s.bg,
        foregroundColor: s.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: overlayStyle,
        iconTheme: IconThemeData(color: s.ink, size: 26),
        titleTextStyle: (text as dynamic).titleLarge?.copyWith(
              color: s.ink,
              fontWeight: FontWeight.w800,
            ),
      ),
      cardTheme: CardThemeData(
        color: s.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: s.bevel
            ? BeveledRectangleBorder(
                borderRadius: BorderRadius.circular(s.radius + 4),
                side: BorderSide(color: s.line),
              )
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(s.radius + 2),
                side: BorderSide(color: s.line),
              ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(64, s.buttonHeight)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          ),
          shape: WidgetStatePropertyAll(btnShape),
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith((st) =>
              st.contains(WidgetState.disabled)
                  ? s.primary.withValues(alpha: 0.30)
                  : s.primary),
          foregroundColor: WidgetStateProperty.resolveWith((st) =>
              st.contains(WidgetState.disabled)
                  ? s.onPrimary.withValues(alpha: 0.7)
                  : s.onPrimary),
          overlayColor: overlay(s.onPrimary),
          iconSize: const WidgetStatePropertyAll(24),
          textStyle: WidgetStatePropertyAll(btnText),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(64, s.buttonHeight),
          shape: btnShape,
          backgroundColor: s.primary,
          foregroundColor: s.onPrimary,
          textStyle: btnText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(64, s.buttonHeight)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 26, vertical: 14),
          ),
          shape: WidgetStatePropertyAll(btnShape),
          foregroundColor: WidgetStateProperty.resolveWith((st) =>
              st.contains(WidgetState.disabled)
                  ? s.ink.withValues(alpha: 0.38)
                  : (dark ? s.ink : s.primary)),
          side: WidgetStateProperty.resolveWith((st) => BorderSide(
                color: st.contains(WidgetState.disabled)
                    ? s.line
                    : s.primary.withValues(alpha: 0.85),
                width: 1.8,
              )),
          overlayColor: overlay(s.primary),
          iconSize: const WidgetStatePropertyAll(24),
          textStyle: WidgetStatePropertyAll(btnText),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
          shape: WidgetStatePropertyAll(btnShape),
          foregroundColor: WidgetStateProperty.resolveWith((st) =>
              st.contains(WidgetState.disabled)
                  ? s.ink.withValues(alpha: 0.38)
                  : s.primary),
          overlayColor: overlay(s.primary),
          textStyle: WidgetStatePropertyAll(
              btnText.copyWith(fontSize: s.bevel ? 17 : 15.5)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(52, 52)),
          overlayColor: overlay(s.primary),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: s.primary,
        foregroundColor: s.onPrimary,
        elevation: eco ? 0 : 3,
        shape: btnShape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.field,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: border(s.fieldLine),
        enabledBorder: border(s.fieldLine),
        focusedBorder: border(s.primary, 2.6),
        errorBorder: border(s.danger, 1.8),
        focusedErrorBorder: border(s.danger, 2.6),
        disabledBorder: border(s.line),
        labelStyle: TextStyle(color: s.inkSoft, fontSize: 16),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((st) => TextStyle(
              color: st.contains(WidgetState.error)
                  ? s.danger
                  : st.contains(WidgetState.focused)
                      ? s.primary
                      : s.inkSoft,
              fontWeight: FontWeight.w800,
            )),
        hintStyle: TextStyle(color: s.inkSoft.withValues(alpha: 0.85)),
        helperStyle: TextStyle(color: s.inkSoft, fontSize: 13.5),
        errorStyle: TextStyle(
            color: s.danger, fontSize: 14, fontWeight: FontWeight.w700),
        errorMaxLines: 3,
        prefixIconColor: WidgetStateColor.resolveWith(
            (st) => st.contains(WidgetState.focused) ? s.primary : s.inkSoft),
        suffixIconColor: WidgetStateColor.resolveWith(
            (st) => st.contains(WidgetState.focused) ? s.primary : s.inkSoft),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: s.primary.withValues(alpha: 0.10),
        selectedColor: s.primary.withValues(alpha: 0.28),
        labelStyle:
            TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: s.ink),
        side: BorderSide(color: s.line),
        shape: const StadiumBorder(),
      ),
      dividerTheme: DividerThemeData(color: s.line, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: s.primary,
        textColor: s.ink,
        minVerticalPadding: 8,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: s.primary,
        collapsedIconColor: s.inkSoft,
        textColor: s.ink,
        collapsedTextColor: s.ink,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: const Border(),
        collapsedShape: const Border(),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((st) =>
            st.contains(WidgetState.selected) ? s.onPrimary : s.inkSoft),
        trackColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected) ? s.primary : s.field),
        trackOutlineColor: WidgetStateProperty.resolveWith((st) =>
            st.contains(WidgetState.selected) ? s.primary : s.fieldLine),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: s.primary),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? s.field : s.ink,
        contentTextStyle: TextStyle(
          color: dark ? s.ink : s.bg,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
        actionTextColor: dark ? s.primary : s.accent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(s.radius)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(s.radius + 4)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(s.radius + 8)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: s.primary.withValues(alpha: 0.24),
        labelTextStyle: WidgetStateProperty.resolveWith((st) => TextStyle(
              fontSize: 14,
              fontWeight: st.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: st.contains(WidgetState.selected) ? s.ink : s.inkSoft,
            )),
        iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(
              size: 27,
              color: st.contains(WidgetState.selected) ? s.ink : s.inkSoft,
            )),
      ),
    );
  }
}
