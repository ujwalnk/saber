import 'dart:math';
import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart';

/// User-adjustable nib parameters (pen_pal's "Nib Angle", "Smoothing",
/// "Thin Width" and "Thick Width" sliders).
///
/// The widths are the widths used when the toolbar size is
/// [FountainNib.referenceSize]; other sizes scale them proportionally.
class NibSettings {
  const NibSettings({
    this.angle = 25.0,
    this.smoothing = 0.6,
    this.minWidth = 0.9,
    this.maxWidth = 1.5,
  });

  /// Nib orientation in degrees (0-180).
  final double angle;

  /// 0 = none, 0.95 = heavy smoothing of width changes.
  final double smoothing;

  /// Thinnest width (pen_pal "Thin Width").
  final double minWidth;

  /// Thickest width (pen_pal "Thick Width").
  final double maxWidth;

  NibSettings copyWith({
    double? angle,
    double? smoothing,
    double? minWidth,
    double? maxWidth,
  }) => NibSettings(
    angle: angle ?? this.angle,
    smoothing: smoothing ?? this.smoothing,
    minWidth: minWidth ?? this.minWidth,
    maxWidth: maxWidth ?? this.maxWidth,
  );

  Map<String, dynamic> toJson() => {
    'a': angle,
    's': smoothing,
    'mn': minWidth,
    'mx': maxWidth,
  };

  /// Missing or invalid values fall back to the defaults.
  static NibSettings fromJson(Object json) {
    const d = NibSettings();
    if (json is! Map) return d;
    double read(String key, double fallback) {
      final v = json[key];
      return v is num && v.isFinite ? v.toDouble() : fallback;
    }

    return NibSettings(
      angle: read('a', d.angle),
      smoothing: read('s', d.smoothing),
      minWidth: read('mn', d.minWidth),
      maxWidth: read('mx', d.maxWidth),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NibSettings &&
      other.angle == angle &&
      other.smoothing == smoothing &&
      other.minWidth == minWidth &&
      other.maxWidth == maxWidth;

  @override
  int get hashCode => Object.hash(angle, smoothing, minWidth, maxWidth);
}

/// The fountain pen's nib, ported 1:1 from the pen_pal prototype
/// (`NibModel` + `StrokePainter`).
///
/// Every order of floating-point operations here is deliberately identical to
/// pen_pal so that the same pointer positions give the same outline polygon,
/// bit for bit. Do not "simplify" the arithmetic.
///
/// Width depends only on the movement direction relative to the nib angle and
/// on exponential smoothing. Stylus pressure is never used.
abstract final class FountainNib {
  /// The toolbar size at which the widths in [NibSettings] apply unscaled.
  static const double referenceSize = 5.0;

  /// pen_pal "Thin Width" for [nib] at toolbar [size].
  static double thinWidth(NibSettings nib, double size) =>
      nib.minWidth * (size / referenceSize);

  /// pen_pal "Thick Width" for [nib] at toolbar [size].
  static double thickWidth(NibSettings nib, double size) =>
      nib.maxWidth * (size / referenceSize);

  /// Per-point widths, exactly as pen_pal's `DrawingCanvas` produced them:
  /// the first point gets the thin width, every later point gets
  /// `NibModel.widthForSegment(previousPosition, position)`.
  static List<double> widths(
    List<Offset> positions, {
    required NibSettings nib,
    required double size,
  }) {
    if (positions.isEmpty) return const [];

    final thin = thinWidth(nib, size);
    final thick = thickWidth(nib, size);
    final mediumWidth = (thin + thick) / 2.0;
    final nibAngleRadians = nib.angle * pi / 180.0;
    final smoothingClamped = nib.smoothing.clamp(0.0, 0.95);

    final result = <double>[thin];
    double? lastWidth; // NibModel._lastWidth (reset at each stroke start)

    for (var i = 1; i < positions.length; i++) {
      final double dx = positions[i].dx - positions[i - 1].dx;
      final double dy = positions[i].dy - positions[i - 1].dy;

      // No meaningful movement: hold the last width so nothing jumps.
      if (dx == 0 && dy == 0) {
        final held = lastWidth ?? mediumWidth;
        lastWidth = held;
        result.add(held);
        continue;
      }

      final double movementAngle = atan2(dy, dx);
      final double effectiveAngle = movementAngle - nibAngleRadians;
      final double factor = (sin(effectiveAngle) + 1.0) / 2.0;
      final double rawWidth = thin + (thick - thin) * factor;

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
  /// `size` is the thick width on purpose: perfect_freehand's radius is
  /// `size * pressure` (with thinning 1), and `size` also feeds its minimum
  /// point distance, sharp-corner and end-noise thresholds.
  static StrokeOptions options({
    required NibSettings nib,
    required double size,
    required bool isComplete,
  }) => StrokeOptions(
    size: thickWidth(nib, size),
    thinning: 1.0,
    smoothing: 0.5,
    streamline: 0.35,
    simulatePressure: false,
    start: StrokeEndOptions.start(cap: true, taperEnabled: false),
    end: StrokeEndOptions.end(cap: true, taperEnabled: false),
    isComplete: isComplete,
  );

  /// perfect_freehand input: each width re-expressed as pseudo-pressure.
  static List<PointVector> inputPoints(
    List<Offset> positions, {
    required NibSettings nib,
    required double size,
  }) {
    final w = widths(positions, nib: nib, size: size);
    final maxWidth = thickWidth(nib, size);
    return [
      for (var i = 0; i < positions.length; i++)
        PointVector(
          positions[i].dx,
          positions[i].dy,
          maxWidth > 0 ? (w[i] / maxWidth).clamp(0.05, 1.0) : 1.0,
        ),
    ];
  }

  /// The outline polygon pen_pal filled with `Path.addPolygon`.
  static List<Offset> polygon(
    List<Offset> positions, {
    required NibSettings nib,
    required double size,
    required bool isComplete,
  }) {
    if (positions.isEmpty) return const [];
    return getStroke(
      inputPoints(positions, nib: nib, size: size),
      options: options(nib: nib, size: size, isComplete: isComplete),
    );
  }

  /// pen_pal draws a lone tap as `drawCircle(position, width / 2)`
  /// instead of running it through perfect_freehand.
  static double dotRadius(NibSettings nib, double size) =>
      thinWidth(nib, size) / 2;
}
