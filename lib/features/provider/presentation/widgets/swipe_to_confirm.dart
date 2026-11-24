import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// Glissière « Glisser pour confirmer » (style Uber Driver).
///
/// Le geste évite les appuis accidentels pendant un déplacement. Pour les
/// lecteurs d'écran, un simple double-appui déclenche l'action.
class SwipeToConfirm extends StatefulWidget {
  const SwipeToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.icon = Icons.keyboard_double_arrow_right_rounded,
    this.color = AppColors.navy,
    this.enabled = true,
    this.loading = false,
    this.disabledLabel,
  });

  final String label;
  final VoidCallback onConfirmed;
  final IconData icon;
  final Color color;
  final bool enabled;
  final bool loading;

  /// Texte affiché quand la glissière est désactivée.
  final String? disabledLabel;

  @override
  State<SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<SwipeToConfirm> {
  static const double _knob = 60;
  static const double _pad = 4;
  static const double _hauteur = 68;

  double _drag = 0;
  bool _dragging = false;

  bool get _actif => widget.enabled && !widget.loading;

  void _fin(double max) {
    if (!_actif) return;
    final valide = _drag >= max * 0.85;
    if (!valide) {
      setState(() {
        _dragging = false;
        _drag = 0;
      });
      return;
    }
    setState(() {
      _dragging = false;
      _drag = max;
    });
    HapticFeedback.heavyImpact();
    widget.onConfirmed();
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _drag = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actif = _actif;
    final fond = actif
        ? widget.color
        : scheme.onSurface.withValues(alpha: 0.12);
    final texte = actif
        ? Colors.white
        : scheme.onSurface.withValues(alpha: 0.75);
    final libelle = (!widget.enabled && widget.disabledLabel != null)
        ? widget.disabledLabel!
        : widget.label;

    return Semantics(
      button: true,
      enabled: actif,
      label: widget.label,
      onTap: actif ? widget.onConfirmed : null,
      child: LayoutBuilder(
        builder: (context, c) {
          final maxDrag = (c.maxWidth - _knob - _pad * 2).clamp(1.0, 2000.0);

          return Container(
            height: _hauteur,
            decoration: BoxDecoration(
              color: fond,
              borderRadius: BorderRadius.circular(_hauteur / 2),
            ),
            child: Stack(
              children: [
                if (actif)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: _pad + _knob + _drag,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(_hauteur / 2),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: _knob + _pad * 2 + 6,
                      right: 16,
                    ),
                    child: Center(
                      child: widget.loading
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              libelle,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: texte,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                height: 1.2,
                              ),
                            ),
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: _dragging
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  left: _pad + _drag,
                  top: _pad,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: actif
                        ? (_) => setState(() => _dragging = true)
                        : null,
                    onHorizontalDragUpdate: actif
                        ? (d) => setState(() {
                            _drag = (_drag + d.delta.dx)
                                .clamp(0.0, maxDrag)
                                .toDouble();
                          })
                        : null,
                    onHorizontalDragEnd: actif ? (_) => _fin(maxDrag) : null,
                    onHorizontalDragCancel: actif ? () => _fin(maxDrag) : null,
                    child: Container(
                      width: _knob,
                      height: _knob,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.icon,
                        size: 32,
                        color: actif
                            ? widget.color
                            : scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
