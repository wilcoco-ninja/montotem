import 'package:flutter/services.dart';

/// Validation de FORMAT de l'IFU (13 chiffres).
/// Aucune clé de contrôle : l'algorithme officiel doit être confirmé auprès
/// de la DGI avant d'être ajouté, sinon de vrais numéros seraient rejetés.
class IfuValidator {
  IfuValidator._();

  static final RegExp _format = RegExp(r'^\d{13}$');

  static String clean(String v) => v.replaceAll(RegExp(r'\s'), '');

  static String? validate(String? v, {required bool required}) {
    final s = clean(v ?? '');
    if (s.isEmpty) return required ? 'Requis' : null;
    if (!_format.hasMatch(s)) return 'L\'IFU compte 13 chiffres';
    return null;
  }

  static final List<TextInputFormatter> formatters = [
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(13),
  ];
}
