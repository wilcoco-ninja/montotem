
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_space.dart';
import 'app_theme.dart';

class _Palette {
  const _Palette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.field,
    required this.fieldLine,
    required this.ink,
    required this.inkSoft,
    required this.primary,
    required this.onPrimary,
    required this.line,
    required this.danger,
    required this.radius,
    required this.buttonHeight,
    this.pill = false,
    this.dense = false,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color field;
  final Color fieldLine;
  final Color ink;
  final Color inkSoft;
  final Color primary;
  final Color onPrimary;
  final Color line;
  final Color danger;
  final double radius;
  final double buttonHeight;

  /// Boutons en forme de pilule (client).
  final bool pill;

  /// Champs et boutons compacts (console admin).
  final bool dense;
}

/// ThÃƒÂ¨me Material de chaque espace. Part du thÃƒÂ¨me commun [AppTheme]
/// (police, accessibilitÃƒÂ©, tailles tactiles) et change l'identitÃƒÂ© :
/// couleurs, rayons, boutons, champs.
///
/// Palette Ã‚Â« Totem Ã‚Â» (voir totem_palette.dart) : tous les couples
/// texte / fond sont ÃƒÂ  7:1 minimum (AAA).
class SpaceTheme {
  SpaceTheme._();

  static final Map<String, ThemeData> _cache = {};

  /// [platform] n'a d'effet que pour le client (clair ou sombre selon le
  /// systÃƒÂ¨me) ; le prestataire est toujours sombre, l'admin toujours clair.
  static ThemeData of(AppSpace space, Brightness platform) {
    final key =
        space == AppSpace.client ? 'client-${platform.name}' : space.name;
    return _cache.putIfAbsent(key, () => _build(_palette(space, platform)));
  }

  static _Palette _palette(AppSpace space, Brightness platform) {
    switch (space) {
      case AppSpace.client:
        return platform == Brightness.dark ? _clientDark : _clientLight;
      case AppSpace.provider:
        return _provider;
      case AppSpace.driver:
        return _provider;
      case AppSpace.admin:
        return _admin;
    }
  }

  // Client, de jour : sable d'harmattan + bleu lagune.
  static const _clientLight = _Palette(
    brightness: Brightness.light,
    bg: SpaceColors.clientBg,
    surface: Color(0xFFFFFFFF),
    field: Color(0xFFFFFFFF),
    fieldLine: Color(0xFF7A8591),
    ink: Color(0xFF142130), // 15,0:1 sur sable
    inkSoft: Color(0xFF41505F), // 7,6:1 sur sable
    primary: SpaceColors.clientPrimary,
    onPrimary: Colors.white,
    line: Color(0xFFE6DDCB),
    danger: Color(0xFFA31515),
    radius: 18,
    buttonHeight: 58,
    pill: true,
  );

  // Client, de nuit : bleu lagune profond + cyan lumineux.
  static const _clientDark = _Palette(
    brightness: Brightness.dark,
    bg: SpaceColors.clientBgDark,
    surface: SpaceColors.clientSurfaceDark,
    field: Color(0xFF152C42),
    fieldLine: Color(0xFF6B8CA8),
    ink: Color(0xFFE8F1F8), // 16,3:1
    inkSoft: Color(0xFFB3C4D4), // 9,1:1
    primary: SpaceColors.clientPrimarySoft,
    onPrimary: Color(0xFF05202B), // 8,7:1 sur cyan
    line: Color(0xFF25405A),
    danger: Color(0xFFFF9C94),
    radius: 18,
    buttonHeight: 58,
    pill: true,
  );

  static const _provider = _Palette(
    brightness: Brightness.dark,
    bg: SpaceColors.proBg,
    surface: SpaceColors.proSurface,
    field: SpaceColors.proSurfaceAlt,
    fieldLine: Color(0xFF55657A),
    ink: SpaceColors.proInk,
    inkSoft: SpaceColors.proInkSoft,
    primary: SpaceColors.proAccent,
    onPrimary: SpaceColors.proOnAccent,
    line: SpaceColors.proLine,
    danger: Color(0xFFFF9C94),
    radius: 10,
    buttonHeight: 56,
  );

  static const _admin = _Palette(
    brightness: Brightness.light,
    bg: SpaceColors.adminBg,
    surface: Color(0xFFFFFFFF),
    field: Color(0xFFFFFFFF),
    fieldLine: Color(0xFF7B8794),
    ink: SpaceColors.adminInk,
    inkSoft: SpaceColors.adminInkSoft,
    primary: SpaceColors.adminPrimary,
    onPrimary: Colors.white,
    line: SpaceColors.adminLine,
    danger: Color(0xFFA31515),
    radius: 6,
    buttonHeight: 46,
    dense: true,
  );

  static ThemeData _build(_Palette p) {
    final base = p.brightness == Brightness.dark
        ? AppTheme.darkTheme
        : AppTheme.lightTheme;

    final scheme = base.colorScheme.copyWith(
      primary: p.primary,
      onPrimary: p.onPrimary,
      surface: p.surface,
      onSurface: p.ink,
      onSurfaceVariant: p.inkSoft,
      error: p.danger,
      outline: p.line,
      outlineVariant: p.line,
      surfaceContainerHighest: p.field,
    );

    final OutlinedBorder shape = p.pill
        ? const StadiumBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(p.radius));

    final label = (base.textTheme.labelLarge ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w800,
      fontSize: p.dense ? 14.5 : 16.5,
    );

    OutlineInputBorder border(Color c, [double w = 1.3]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(p.radius),
          borderSide: BorderSide(color: c, width: w),
        );

    final overlay = (p.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(statusBarColor: Colors.transparent);

    final outlinedFg = p.brightness == Brightness.dark ? p.ink : p.primary;

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      textTheme: base.textTheme.apply(bodyColor: p.ink, displayColor: p.ink),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: p.bg,
        foregroundColor: p.ink,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: p.ink, size: 26),
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(color: p.ink),
        systemOverlayStyle: overlay,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(p.radius + 2),
          side: BorderSide(color: p.line),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(64, p.buttonHeight)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          shape: WidgetStatePropertyAll(shape),
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.disabled)
                  ? p.primary.withValues(alpha: 0.35)
                  : p.primary),
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.disabled)
                  ? p.onPrimary.withValues(alpha: 0.7)
                  : p.onPrimary),
          overlayColor:
              WidgetStatePropertyAll(p.onPrimary.withValues(alpha: 0.12)),
          iconSize: const WidgetStatePropertyAll(22),
          textStyle: WidgetStatePropertyAll(label),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(64, p.buttonHeight),
          shape: shape,
          backgroundColor: p.primary,
          foregroundColor: p.onPrimary,
          textStyle: label,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(64, p.buttonHeight)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          shape: WidgetStatePropertyAll(shape),
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.disabled)
                  ? p.ink.withValues(alpha: 0.38)
                  : outlinedFg),
          side: WidgetStateProperty.resolveWith((s) => BorderSide(
                color: s.contains(WidgetState.disabled)
                    ? p.line
                    : p.primary.withValues(alpha: 0.75),
                width: 1.5,
              )),
          overlayColor:
              WidgetStatePropertyAll(p.primary.withValues(alpha: 0.10)),
          iconSize: const WidgetStatePropertyAll(22),
          textStyle: WidgetStatePropertyAll(label),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          shape: WidgetStatePropertyAll(shape),
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.disabled)
                  ? p.ink.withValues(alpha: 0.38)
                  : p.primary),
          overlayColor:
              WidgetStatePropertyAll(p.primary.withValues(alpha: 0.10)),
          textStyle: WidgetStatePropertyAll(label.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: p.dense ? 14 : 15,
          )),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(p.radius + 4),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.field,
        isDense: p.dense,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: p.dense ? 14 : 18,
        ),
        border: border(p.fieldLine),
        enabledBorder: border(p.fieldLine),
        focusedBorder: border(p.primary, 2.2),
        errorBorder: border(p.danger, 1.6),
        focusedErrorBorder: border(p.danger, 2.2),
        disabledBorder: border(p.fieldLine.withValues(alpha: 0.4)),
        labelStyle: TextStyle(color: p.inkSoft, fontSize: 15),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((s) => TextStyle(
              color: s.contains(WidgetState.error)
                  ? p.danger
                  : s.contains(WidgetState.focused)
                      ? p.primary
                      : p.inkSoft,
              fontWeight: FontWeight.w700,
            )),
        hintStyle: TextStyle(
          color: p.inkSoft.withValues(alpha: 0.8),
          fontSize: 15,
        ),
        helperStyle: TextStyle(color: p.inkSoft, fontSize: 13),
        errorStyle: TextStyle(
          color: p.danger,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
        errorMaxLines: 3,
        prefixIconColor:
            WidgetStateColor.resolveWith((s) => s.contains(WidgetState.error)
                ? p.danger
                : s.contains(WidgetState.focused)
                    ? p.primary
                    : p.inkSoft),
        suffixIconColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.focused) ? p.primary : p.inkSoft),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.primary.withValues(alpha: 0.10),
        selectedColor: p.primary.withValues(alpha: 0.26),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14.5,
          color: p.ink,
        ),
        side: BorderSide(color: p.line),
        shape: const StadiumBorder(),
      ),
      dividerTheme: DividerThemeData(color: p.line, thickness: 1, space: 1),
      listTileTheme: base.listTileTheme.copyWith(iconColor: p.primary),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: p.brightness == Brightness.dark ? p.field : p.ink,
        contentTextStyle: TextStyle(
          color: p.brightness == Brightness.dark ? p.ink : p.bg,
          fontWeight: FontWeight.w700,
          fontSize: 15.5,
        ),
        actionTextColor:
            p.brightness == Brightness.dark ? p.primary : p.surface,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(p.radius + 4),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(p.radius + 6),
          ),
        ),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        height: p.dense ? 64 : 76,
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.primary.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 13.5,
              fontWeight: s.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: s.contains(WidgetState.selected) ? p.ink : p.inkSoft,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              size: 26,
              color: s.contains(WidgetState.selected) ? p.ink : p.inkSoft,
            )),
      ),
    );
  }
}
