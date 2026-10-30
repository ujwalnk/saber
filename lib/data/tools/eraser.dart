import 'dart:math';
import 'dart:ui';

import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:sbn/tool_id.dart';

double square(double x) => x * x;
double sqrDistanceBetween(Offset p1, Offset p2) =>
    square(p1.dx - p2.dx) + square(p1.dy - p2.dy);

/// What an eraser drag changed.
typedef EraseResult = ({List<Stroke> erased, List<Stroke> added});

class Eraser extends Tool {
  /// Limits of the size slider (the eraser's radius, in page units).
  static const double sizeMin = 2;
  static const double sizeMax = 60;
  static const double sizeStep = 1;

  /// A fixed size, or null to follow [Stows.eraserSize] live.
  final double? _size;

  /// The eraser's radius in page units.
  double get size => _size ?? stows.eraserSize.value;
  double get sqrSize => square(size);

  /// Strokes that were on the page before this drag and have been removed
  /// (completely, or replaced by the pieces left over).
  final List<Stroke> _erased = [];

  /// Pieces created during this drag that are still on the page.
  final Set<Stroke> _added = {};

  new({double? size}) : _size = size;

  @override
  ToolId get toolId => .eraser;

  /// Erases whatever is under the eraser as it moves from [from] to [to].
  ///
  /// By default only the touched part of each stroke is removed: the stroke
  /// is cut and the untouched pieces stay. With
  /// [Stows.eraseWholeStrokes] the whole stroke goes instead.
  void erase(Offset from, Offset to, EditorPage page) {
    final wholeStrokes = stows.eraseWholeStrokes.value;

    // iterate over a copy: we modify page.strokes as we go
    for (final stroke in List<Stroke>.of(page.strokes)) {
      final List<Stroke>? pieces;
      if (wholeStrokes || stroke.runtimeType != Stroke) {
        // shapes (circles, rectangles) can't be cut
        pieces = _shouldStrokeBeErased(to, stroke, sqrSize) ? const [] : null;
      } else {
        pieces = _cut(stroke, from, to, size);
      }
      if (pieces == null) continue; // untouched

      page.strokes.remove(stroke);
      if (!_added.remove(stroke)) _erased.add(stroke);
      for (final piece in pieces) {
        page.insertStroke(piece);
        _added.add(piece);
      }
    }
  }

  /// Returns what this drag erased (original strokes) and what replaced it
  /// (the pieces left over), then resets.
  EraseResult onDragEnd() {
    final result = (erased: List.of(_erased), added: List.of(_added));
    _erased.clear();
    _added.clear();
    return result;
  }

  /// Cuts [stroke] where the eraser (a circle of [radius] swept from [from]
  /// to [to]) touches it. Returns the pieces that remain, or null if the
  /// eraser doesn't touch the stroke at all.
  static List<Stroke>? _cut(
    Stroke stroke,
    Offset from,
    Offset to,
    double radius,
  ) {
    if (stroke.points.isEmpty) return null;

    // The ink extends half the stroke size beyond its centre line, so cut
    // that much further out: what's left must not poke into the eraser.
    final reach = radius + stroke.options.size / 2;

    // quick reject using the stroke's bounds
    final bounds = stroke.lowQualityPath.getBounds().inflate(reach);
    if (!bounds.contains(from) && !bounds.contains(to)) {
      final sweep = Rect.fromPoints(from, to);
      if (!bounds.overlaps(sweep.inflate(0.5))) return null;
    }

    final points = _resample(stroke.points, max(1.0, reach / 2));

    final sqrReach = square(reach);
    final erased = [
      for (final p in points) _sqrDistanceToSegment(p, from, to) <= sqrReach,
    ];
    if (!erased.contains(true)) return null;

    // keep the runs of points that weren't erased
    final pieces = <Stroke>[];
    var run = <PointVector>[];
    void endRun() {
      // a single leftover point would just be a speck
      if (run.length >= 2) {
        pieces.add(
          stroke.copy()
            ..points.clear()
            ..points.addAll(run)
            ..markPolygonNeedsUpdating(),
        );
      }
      run = <PointVector>[];
    }

    for (var i = 0; i < points.length; i++) {
      if (erased[i]) {
        endRun();
      } else {
        run.add(points[i]);
      }
    }
    endRun();
    return pieces;
  }

  /// Adds points along any segment longer than [maxGap], so that cutting at
  /// a point cuts close to where the eraser actually is.
  static List<PointVector> _resample(List<PointVector> points, double maxGap) {
    final result = <PointVector>[points.first];
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final distance = (Offset(b.dx, b.dy) - Offset(a.dx, a.dy)).distance;
      final steps = (distance / maxGap).ceil();
      for (var s = 1; s < steps; s++) {
        final t = s / steps;
        result.add(
          PointVector(
            a.dx + (b.dx - a.dx) * t,
            a.dy + (b.dy - a.dy) * t,
            a.pressure == null || b.pressure == null
                ? a.pressure
                : a.pressure! + (b.pressure! - a.pressure!) * t,
          ),
        );
      }
      result.add(b);
    }
    return result;
  }

  static double _sqrDistanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared == 0) return sqrDistanceBetween(p, a);
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSquared).clamp(
      0.0,
      1.0,
    );
    return sqrDistanceBetween(p, a + ab * t);
  }

  static bool _shouldStrokeBeErased(
    Offset eraserPos,
    Stroke stroke,
    double sqrSize,
  ) {
    if (stroke.length <= 3) {
      if (stroke.lowQualityPath.contains(eraserPos)) return true;
    }

    /// skip checking every few vertices for performance
    final int verticesToSkip = switch (stroke.lowQualityPolygon.length) {
      < 100 => 0,
      < 1000 => 1,
      _ => 2,
    };

    for (
      int i = 0;
      i < stroke.lowQualityPolygon.length;
      i += verticesToSkip + 1
    ) {
      final Offset strokeVertex = stroke.lowQualityPolygon[i];
      if (sqrDistanceBetween(strokeVertex, eraserPos) <= sqrSize) return true;
    }
    return false;
  }
}
