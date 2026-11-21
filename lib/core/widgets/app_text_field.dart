
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Champ de saisie unifiÃƒÂ© MONTOTEM.
///
/// GÃƒÂ¨re : icÃƒÂ´ne de prÃƒÂ©fixe, bascule afficher/masquer pour les mots de passe,
/// suffixe personnalisÃƒÂ©, texte d'aide, erreurs, mode lecture seule.
/// Le style (bordures, focus colorÃƒÂ©, erreurs) vient du thÃƒÂ¨me.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.helper,
    this.icon,
    this.suffix,
    this.obscure = false,
    this.enabled = true,
    this.readOnly = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.maxLength,
    this.autofillHints,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? helper;
  final IconData? icon;
  final Widget? suffix;
  final bool obscure;
  final bool enabled;
  final bool readOnly;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final int? maxLength;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;
  final bool autofocus;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    final Widget? suffix = widget.obscure
        ? IconButton(
            tooltip: _hidden ? 'Afficher' : 'Masquer',
            icon: Icon(
              _hidden
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () => setState(() => _hidden = !_hidden),
          )
        : (widget.readOnly
            ? const Icon(Icons.lock_outline, size: 18)
            : widget.suffix);

    return TextFormField(
      controller: widget.controller,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      obscureText: _hidden,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      textAlign: widget.textAlign,
      // Un champ masquÃƒÂ© ne peut avoir qu'une seule ligne (sinon exception).
      maxLines: widget.obscure ? 1 : widget.maxLines,
      maxLength: widget.maxLength,
      autofillHints: widget.autofillHints,
      inputFormatters: widget.inputFormatters,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helper,
        counterText: '',
        prefixIcon: widget.icon != null ? Icon(widget.icon, size: 22) : null,
        suffixIcon: suffix,
        fillColor: widget.readOnly
            ? Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.5)
            : null,
      ),
    );
  }
}
