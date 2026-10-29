import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Where the pointer is, both inside the area the cursor is painted over
/// ([local]) and on the screen ([global]).
typedef EraserPointer = ({Offset local, Offset global});

/// A circle that follows the pointer and shows the area the eraser affects.
///
/// Paint this over the canvas (inside an [IgnorePointer]). [radiusAt] turns
/// the eraser's size, which is in page units, into screen pixels for the
/// given global position, because that depends on zoom and on the page.
class EraserCursor extends StatelessWidget {
  const new({super.key, required this.pointer, required this.radiusAt});

  final ValueListenable<EraserPointer?> pointer;
  final double? Function(Offset global) radiusAt;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    return ValueListenableBuilder(
      valueListenable: pointer,
      builder: (context, pointer, _) {
        if (pointer == null) return const SizedBox.shrink();
        final radius = radiusAt(pointer.global);
        if (radius == null || radius <= 0) return const SizedBox.shrink();

        return CustomPaint(
          painter: _EraserCursorPainter(
            center: pointer.local,
            radius: radius,
            color: colorScheme.primary,
          ),
        );
      },
    );
  }
}

class _EraserCursorPainter extends CustomPainter {
  const _EraserCursorPainter({
    required this.center,
    required this.radius,
    required this.color,
  });

  final Offset center;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color.withValues(alpha: 0.12),
    );
    // A light ring under a dark ring, so the outline shows on any page color.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.8),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_EraserCursorPainter old) =>
      old.center != center || old.radius != radius || old.color != color;
}
