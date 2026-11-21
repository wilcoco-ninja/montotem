
import 'package:flutter/material.dart';

/// Cercles concentriques (ondes de signal) : motif de l'espace client.
class RipplePainter extends CustomPainter {
  const RipplePainter({
    required this.color,
    this.center = const Offset(0.5, 0.5),
    this.rings = 6,
    this.gap = 38,
    this.stroke = 1.4,
  });

  final Color color;

  /// Centre en fraction de la taille (0..1).
  final Offset center;
  final int rings;
  final double gap;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width * center.dx, size.height * center.dy);
    for (var i = 1; i <= rings; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = color.withValues(alpha: color.a * (1 - (i - 1) / rings));
      canvas.drawCircle(c, gap * i, paint);
    }
  }

  @override
  bool shouldRepaint(RipplePainter old) =>
      old.color != color ||
      old.center != center ||
      old.rings != rings ||
      old.gap != gap ||
      old.stroke != stroke;
}

/// Quadrillage Ã‚Â« plan d'atelier Ã‚Â» : motif de l'espace prestataire.
class GridPainter extends CustomPainter {
  const GridPainter({required this.color, this.step = 36});

  final Color color;
  final double step;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(GridPainter old) => old.color != color || old.step != step;
}

/// Logotype Ã‚Â« montotem Ã‚Â» : Ã‚Â« mon Ã‚Â» lÃƒÂ©ger, Ã‚Â« totem Ã‚Â» en gras.
class Wordmark extends StatelessWidget {
  const Wordmark({
    super.key,
    required this.color,
    this.accent,
    this.size = 22,
  });

  final Color color;
  final Color? accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'MonTotem',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            color: color,
            fontSize: size,
            letterSpacing: -0.6,
            height: 1,
          ),
          children: [
            const TextSpan(
              text: 'mon',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            TextSpan(
              text: 'totem',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: accent ?? color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
