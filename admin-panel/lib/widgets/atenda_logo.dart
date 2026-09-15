import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_tokens.dart';

/// Isotipo + wordmark Atende Ai (vetor simples, sem só “A no quadrado”).
class AtendaLogo extends StatelessWidget {
  const AtendaLogo({
    super.key,
    this.height = 32,
    this.showWordmark = true,
    this.color = AppColors.primary,
    this.wordmarkColor = AppColors.text,
  });

  final double height;
  final bool showWordmark;
  final Color color;
  final Color wordmarkColor;

  @override
  Widget build(BuildContext context) {
    final markSize = height;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: markSize,
          height: markSize,
          child: CustomPaint(
            painter: _AtendaIsotypePainter(color: color),
          ),
        ),
        if (showWordmark) ...[
          SizedBox(width: height * 0.28),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Atende',
                  style: GoogleFonts.manrope(
                    color: wordmarkColor,
                    fontSize: height * 0.52,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    height: 1,
                  ),
                ),
                TextSpan(
                  text: ' Ai',
                  style: GoogleFonts.manrope(
                    color: color,
                    fontSize: height * 0.52,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AtendaIsotypePainter extends CustomPainter {
  _AtendaIsotypePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final fill = Paint()
      ..color = color.withValues(alpha: 0.16)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final cx = size.width * 0.5;
    final cy = size.height * 0.52;
    final r = size.width * 0.34;

    // Node cluster (network / conversation graph).
    final nodes = <Offset>[
      Offset(cx, cy - r * 0.85),
      Offset(cx - r * 0.78, cy + r * 0.35),
      Offset(cx + r * 0.78, cy + r * 0.35),
      Offset(cx, cy + r * 0.05),
    ];

    canvas.drawCircle(nodes[3], size.width * 0.18, fill);

    // Edges
    final edgeThin = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawLine(nodes[0], nodes[3], stroke);
    canvas.drawLine(nodes[1], nodes[3], stroke);
    canvas.drawLine(nodes[2], nodes[3], stroke);
    canvas.drawLine(nodes[0], nodes[1], edgeThin);
    canvas.drawLine(nodes[0], nodes[2], edgeThin);

    final nodePaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    for (final n in nodes) {
      canvas.drawCircle(n, size.width * 0.075, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AtendaIsotypePainter oldDelegate) =>
      oldDelegate.color != color;
}
