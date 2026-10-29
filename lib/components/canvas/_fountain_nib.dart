import 'dart:math';
import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart';

/// The fountain pen's nib, ported 1:1 from the pen_pal prototype
/// (`NibModel` + `StrokePainter`).
///
/// Every number and every order of floating-point operations here is
/// deliberately identical to pen_pal so that the same pointer positions give
/// the same outline polygon, bit for bit. Do not "simplify" the arithmetic.
///
/// Width depends only on the movement direction relative to [nibAngle] and on
/// exponential smoothing. Stylus pressure is never used.
abstract final class FountainNib {
  /// Nib orientation in degrees (pen_pal "Nib Angle").
  static const double nibAngle = 25.0;

  /// pen_pal "Thin Width" / "Thick Width".
  static const double thinWidth = 0.9;
  static const double thickWidth = 1.5;

  /// pen_pal "Smoothing" (0 = none, 0.95 = heavy).
  static const double smoothing = 0.6;

  static const double _mediumWidth = (thinWidth + thickWidth) / 2.0;

  /// Per-point widths, exactly as pen_pal's `DrawingCanvas` produced them:
  /// the first point gets [thinWidth], every later point gets
  /// `NibModel.widthForSegment(previousPosition, position)`.
  static List<double> widths(List<Offset> positions) {
    if (positions.isEmpty) return const [];

    final nibAngleRadians = nibAngle * pi / 180.0;
    final smoothingClamped = smoothing.clamp(0.0, 0.95);

    final result = <double>[thinWidth];
    double? lastWidth; // NibModel._lastWidth (reset at each stroke start)

    for (var i = 1; i < positions.length; i++) {
      final double dx = positions[i].dx - positions[i - 1].dx;
      final double dy = positions[i].dy - positions[i - 1].dy;

      // No meaningful movement: hold the last width so nothing jumps.
      if (dx == 0 && dy == 0) {
        final held = lastWidth ?? _mediumWidth;
        lastWidth = held;
        result.add(held);
        continue;
      }

      final double movementAngle = atan2(dy, dx);
      final double effectiveAngle = movementAngle - nibAngleRadians;
      final double factor = (sin(effectiveAngle) + 1.0) / 2.0;
      final double rawWidth = thinWidth + (thickWidth - thinWidth) * factor;

      final double previousWidth = lastWidth ?? rawWidth;
      final double smoothedWidth =
          previousWidth + (rawWidth - previousWidth) * (1.0 - smoothingClamped);

      lastWidth = smoothedWidth;
      result.add(smoothedWidth);
    }
    return result;
  }

  /// The options pen_pal passed to `getStroke`.
  ///
  /// `size` is [thickWidth] on purpose: perfect_freehand's radius is
  /// `size * pressure` (with thinning 1), and `size` also feeds its minimum
  /// point distance, sharp-corner and end-noise thresholds.
  static StrokeOptions options({required bool isComplete}) => StrokeOptions(
    size: thickWidth,
    thinning: 1.0,
    smoothing: 0.5,
    streamline: 0.35,
    simulatePressure: false,
    start: StrokeEndOptions.start(cap: true, taperEnabled: false),
    end: StrokeEndOptions.end(cap: true, taperEnabled: false),
    isComplete: isComplete,
  );

  /// perfect_freehand input: each width re-expressed as pseudo-pressure.
  static List<PointVector> inputPoints(List<Offset> positions) {
    final w = widths(positions);
    return [
      for (var i = 0; i < positions.length; i++)
        PointVector(
          positions[i].dx,
          positions[i].dy,
          thickWidth > 0 ? (w[i] / thickWidth).clamp(0.05, 1.0) : 1.0,
        ),
    ];
  }

  /// The outline polygon pen_pal filled with `Path.addPolygon`.
  static List<Offset> polygon(
    List<Offset> positions, {
    required bool isComplete,
  }) {
    if (positions.isEmpty) return const [];
    return getStroke(
      inputPoints(positions),
      options: options(isComplete: isComplete),
    );
  }

  /// pen_pal draws a lone tap as `drawCircle(position, width / 2)`
  /// instead of running it through perfect_freehand.
  static double get dotRadius => thinWidth / 2;
}
