
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TextSizeLevel {
  normal(1.0, 'Normal'),
  grand(1.25, 'Grand'),
  tresGrand(1.5, 'TrÃƒÂ¨s grand');

  const TextSizeLevel(this.factor, this.libelle);
  final double factor;
  final String libelle;
}

/// Taille du texte choisie par l'utilisateur, appliquÃƒÂ©e globalement dans
/// MonTotemApp (en plus de la taille de police du systÃƒÂ¨me).
///
/// Ã‚Â« Normal Ã‚Â» par dÃƒÂ©faut : l'interface client n'a plus de bouton de taille
/// du texte, elle suit simplement le rÃƒÂ©glage du tÃƒÂ©lÃƒÂ©phone.
class AccessibilityController extends ChangeNotifier {
  static const String _key = 'a11y_text_level';

  TextSizeLevel _level = TextSizeLevel.normal;
  TextSizeLevel get level => _level;
  double get factor => _level.factor;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final i = prefs.getInt(_key);
    if (i != null && i >= 0 && i < TextSizeLevel.values.length) {
      _level = TextSizeLevel.values[i];
      notifyListeners();
    }
  }

  Future<void> setLevel(TextSizeLevel level) async {
    if (level == _level) return;
    _level = level;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, level.index);
  }
}

Future<void> showAccessibilitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => const _AccessibilitySheet(),
  );
}

class _AccessibilitySheet extends StatelessWidget {
  const _AccessibilitySheet();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AccessibilityController>();
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Taille du texte',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Choisissez la taille la plus confortable pour vous.',
              style: TextStyle(
                fontSize: 15,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 16),
            for (final level in TextSizeLevel.values) ...[
              _LevelTile(
                level: level,
                selected: level == controller.level,
                onTap: () => controller.setLevel(level),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final TextSizeLevel level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected ? scheme.primary.withValues(alpha: 0.10) : null,
          border: Border.all(
            color: selected
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.2),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(level.factor)),
                child: Text(
                  '${level.libelle} : Appeler le dÃƒÂ©panneur',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? scheme.primary : null,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}
