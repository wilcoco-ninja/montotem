import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'totem_palette.dart';

/// Les pictogrammes MonTotem, dessinés en code (aucun fichier image :
/// zéro octet à télécharger, nets à toutes les tailles, fonctionnent
/// hors ligne, adaptés au mode sombre et au mode éco).
///
/// Ils remplacent les icônes Material génériques que tous les concurrents
/// utilisent : une moto à casque jaune, un tricycle de fret, un triangle de
/// panne, un signal barré, une batterie qui se vide, un phare SOS qui pulse,
/// et le totem de la marque.
enum TotemGlyph {
  zemidjan,
  kloboto,
  depannage,
  panne,
  sos,
  batterie,
  horsLigne,
  remorquage,
  pneu,
  mark,
}

class TotemIcon extends StatefulWidget {
  const TotemIcon(
    this.glyph, {
    super.key,
    this.size = 28,
    this.color,
    this.accent,
    this.level = 1.0,
    this.semanticLabel,
  });

  final TotemGlyph glyph;
  final double size;

  /// Couleur du trait (par défaut : couleur d'icône du thème).
  final Color? color;

  /// Couleur d'accent (casque, remplissage, onde SOS…).
  final Color? accent;

  /// Niveau de charge de 0 à 1 (pour [TotemGlyph.batterie]).
  final double level;
  final String? semanticLabel;

  @override
  State<TotemIcon> createState() => _TotemIconState();
}

class _TotemIconState extends State<TotemIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Le phare SOS ne pulse que si les animations sont autorisées
    // (désactivées en mode éco-batterie et dans les réglages d'accessibilité).
    final animer =
        widget.glyph == TotemGlyph.sos &&
        !MediaQuery.disableAnimationsOf(context);
    if (animer && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!animer && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color =
        widget.color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    final accent =
        widget.accent ??
        (widget.glyph == TotemGlyph.sos ? Totem.urgence : Totem.safran);

    return Semantics(
      image: true,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _TotemPainter(
          glyph: widget.glyph,
          color: color,
          accent: accent,
          level: widget.level.clamp(0.0, 1.0).toDouble(),
          pulse: _pulse,
        ),
      ),
    );
  }
}

class _TotemPainter extends CustomPainter {
  _TotemPainter({
    required this.glyph,
    required this.color,
    required this.accent,
    required this.level,
    required this.pulse,
  }) : super(repaint: pulse);

  final TotemGlyph glyph;
  final Color color;
  final Color accent;
  final double level;
  final Animation<double> pulse;

  Paint _trait(Color c, [double w = 3]) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint _plein(Color c) => Paint()
    ..color = c
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48);
    final trait = _trait(color);

    switch (glyph) {
      case TotemGlyph.zemidjan:
        // Roues
        canvas.drawCircle(const Offset(11, 35), 7, trait);
        canvas.drawCircle(const Offset(37, 35), 7, trait);
        // Cadre + fourche
        final cadre = Path()
          ..moveTo(11, 35)
          ..lineTo(20, 26)
          ..lineTo(31, 26)
          ..lineTo(37, 35);
        canvas.drawPath(cadre, trait);
        canvas.drawLine(const Offset(31, 26), const Offset(28, 16), trait);
        canvas.drawLine(const Offset(25, 16), const Offset(33, 16), trait);
        // Selle
        canvas.drawLine(
          const Offset(13, 23),
          const Offset(23, 23),
          _trait(color, 4.5),
        );
        // Pilote : casque safran + buste
        canvas.drawCircle(const Offset(18, 11.5), 4.8, _plein(accent));
        canvas.drawLine(const Offset(18, 17), const Offset(21, 23), trait);
        // Bloc moteur + pot d'échappement : c'est une moto, pas un vélo
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(19, 26, 11, 7),
            const Radius.circular(2),
          ),
          _plein(color),
        );
        canvas.drawLine(const Offset(8, 31), const Offset(13, 36), trait);
        break;

      case TotemGlyph.kloboto:
        // Roues : une devant, une sous la benne
        canvas.drawCircle(const Offset(9, 36), 6, trait);
        canvas.drawCircle(const Offset(36, 36), 6, trait);
        // Cabine / guidon
        final cabine = Path()
          ..moveTo(9, 36)
          ..lineTo(14, 21)
          ..lineTo(20, 21);
        canvas.drawPath(cabine, trait);
        canvas.drawLine(const Offset(14, 21), const Offset(13, 13), trait);
        canvas.drawLine(const Offset(10, 13), const Offset(17, 13), trait);
        // Benne de fret
        final benne = RRect.fromRectAndRadius(
          const Rect.fromLTWH(20, 13, 26, 18),
          const Radius.circular(3),
        );
        canvas.drawRRect(benne, _plein(accent.withValues(alpha: 0.38)));
        canvas.drawRRect(benne, trait);
        canvas.drawLine(const Offset(27, 13), const Offset(27, 31), trait);
        break;

      case TotemGlyph.depannage:
        // Clé à molette : mâchoire ouverte vers le haut à droite
        final tete = Rect.fromCircle(center: const Offset(32, 16), radius: 8);
        canvas.drawArc(tete, -0.285, 6.283 - 1.1, false, _trait(color, 4));
        canvas.drawLine(
          const Offset(26, 22),
          const Offset(10, 38),
          _trait(color, 5.5),
        );
        canvas.drawCircle(const Offset(9, 39), 2.6, _plein(accent));
        // Petite étincelle d'intervention
        canvas.drawLine(
          const Offset(38, 36),
          const Offset(44, 36),
          _trait(accent, 3),
        );
        canvas.drawLine(
          const Offset(41, 33),
          const Offset(41, 39),
          _trait(accent, 3),
        );
        break;

      case TotemGlyph.panne:
        final tri = Path()
          ..moveTo(24, 6)
          ..lineTo(44, 40)
          ..lineTo(4, 40)
          ..close();
        canvas.drawPath(tri, _trait(color, 3.2));
        canvas.drawLine(
          const Offset(24, 18),
          const Offset(24, 29),
          _trait(accent, 4),
        );
        canvas.drawCircle(const Offset(24, 34.5), 2.3, _plein(accent));
        break;

      case TotemGlyph.sos:
        // Phare : deux ondes qui s'élargissent autour d'un cœur plein
        const c = Offset(24, 24);
        final t = pulse.value;
        for (var i = 0; i < 2; i++) {
          final p = (t + i * 0.5) % 1.0;
          canvas.drawCircle(
            c,
            9 + p * 14,
            _trait(accent.withValues(alpha: (1 - p) * 0.6), 2.6),
          );
        }
        canvas.drawCircle(c, 9, _plein(accent));
        canvas.drawCircle(c, 3.4, _plein(Colors.white));
        break;

      case TotemGlyph.batterie:
        final corps = RRect.fromRectAndRadius(
          const Rect.fromLTWH(4, 14, 35, 21),
          const Radius.circular(4.5),
        );
        canvas.drawRRect(corps, _trait(color, 3));
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(40.5, 20.5, 4, 8),
            const Radius.circular(1.6),
          ),
          _plein(color),
        );
        final w = 29 * level;
        if (w > 0.5) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(7.5, 17.5, w, 14),
              const Radius.circular(2),
            ),
            _plein(level <= 0.2 ? Totem.urgenceClair : accent),
          );
        }
        break;

      case TotemGlyph.horsLigne:
        for (var i = 0; i < 4; i++) {
          final x = 9.0 + i * 10;
          final h = 8.0 + i * 7;
          canvas.drawLine(Offset(x, 39), Offset(x, 39 - h), _trait(color, 4.4));
        }
        canvas.drawLine(
          const Offset(5, 7),
          const Offset(43, 43),
          _trait(accent, 3.6),
        );
        break;

      case TotemGlyph.remorquage:
        // Dépanneuse : cabine, plateau, flèche et crochet
        canvas.drawCircle(const Offset(12, 36), 5, trait);
        canvas.drawCircle(const Offset(36, 36), 5, trait);
        final cab = Path()
          ..moveTo(5, 33)
          ..lineTo(5, 25)
          ..lineTo(10, 25)
          ..lineTo(15, 16)
          ..lineTo(25, 16)
          ..lineTo(25, 33);
        canvas.drawPath(cab, trait);
        canvas.drawLine(const Offset(25, 33), const Offset(7, 33), trait);
        final plateau = RRect.fromRectAndRadius(
          const Rect.fromLTWH(25, 26, 19, 7),
          const Radius.circular(1.5),
        );
        canvas.drawRRect(plateau, _plein(accent.withValues(alpha: 0.38)));
        canvas.drawRRect(plateau, trait);
        canvas.drawLine(
          const Offset(33, 26),
          const Offset(40, 11),
          _trait(color, 3.4),
        );
        canvas.drawLine(
          const Offset(40, 11),
          const Offset(40, 19),
          _trait(accent, 2.6),
        );
        canvas.drawCircle(const Offset(40, 22), 2.6, _trait(accent, 2.4));
        break;

      case TotemGlyph.pneu:
        canvas.drawCircle(const Offset(24, 24), 15, _trait(color, 7));
        canvas.drawCircle(const Offset(24, 24), 7, _trait(accent, 2.6));
        canvas.drawCircle(const Offset(24, 24), 2, _plein(accent));
        for (var i = 0; i < 8; i++) {
          final a = i * 3.14159265 / 4;
          canvas.drawLine(
            Offset(24 + 10.5 * math.cos(a), 24 + 10.5 * math.sin(a)),
            Offset(24 + 19.5 * math.cos(a), 24 + 19.5 * math.sin(a)),
            _trait(color, 2),
          );
        }
        break;

      case TotemGlyph.mark:
        // Le totem : trois blocs empilés, deux yeux sur chacun.
        final couleurs = [Totem.lagunePale, Totem.safran, Totem.laterite];
        for (var i = 0; i < 3; i++) {
          final y = 3.0 + i * 14.8;
          final bloc = RRect.fromRectAndRadius(
            Rect.fromLTWH(11, y, 26, 13),
            Radius.circular(i == 0 ? 8 : 3.5),
          );
          canvas.drawRRect(bloc, _plein(couleurs[i]));
          canvas.drawCircle(Offset(19, y + 6.5), 1.7, _plein(Totem.nuit));
          canvas.drawCircle(Offset(29, y + 6.5), 1.7, _plein(Totem.nuit));
        }
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TotemPainter old) =>
      old.glyph != glyph ||
      old.color != color ||
      old.accent != accent ||
      old.level != level;
}
