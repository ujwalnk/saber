import 'package:flutter/material.dart';

/// Draws the eraser's footprint: a ring with a faint fill and a centre dot.
class EraserCursorPainter extends CustomPainter {
  const EraserCursorPainter({required this.circle, required this.color});

  final ({Offset center, double radius})? circle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final circle = this.circle;
    if (circle == null) return;
    canvas.drawCircle(
      circle.center,
      circle.radius,
      Paint()..color = color.withValues(alpha: 0.12),
    );
    canvas.drawCircle(
      circle.center,
      circle.radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(circle.center, 1.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(EraserCursorPainter old) =>
      old.circle != circle || old.color != color;
}
