import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Isotipo A geométrico linear (Brand Board V2.1).
/// Frame neutro; traços do A em cyan (identidade, sem contorno dominante).
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 32,
    this.color = AppColors.primary,
    this.frameColor = AppColors.border,
  });

  final double size;
  final Color color;
  final Color frameColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GeometricAPainter(color: color, frameColor: frameColor),
      ),
    );
  }
}

class _GeometricAPainter extends CustomPainter {
  _GeometricAPainter({required this.color, required this.frameColor});

  final Color color;
  final Color frameColor;

  @override
  void paint(Canvas canvas, Size size) {
    final frameStroke = Paint()
      ..color = frameColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final aStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.072
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final inset = size.width * 0.08;
    final radius = Radius.circular(size.width * 0.18);
    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2),
      radius,
    );
    canvas.drawRRect(frame, frameStroke);

    final left = size.width * 0.30;
    final right = size.width * 0.70;
    final top = size.height * 0.28;
    final bottom = size.height * 0.74;
    final midY = size.height * 0.56;

    final a = Path()
      ..moveTo(left, bottom)
      ..lineTo(size.width * 0.50, top)
      ..lineTo(right, bottom);
    canvas.drawPath(a, aStroke);
    canvas.drawLine(
      Offset(size.width * 0.38, midY),
      Offset(size.width * 0.62, midY),
      aStroke,
    );
  }

  @override
  bool shouldRepaint(covariant _GeometricAPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.frameColor != frameColor;
}
