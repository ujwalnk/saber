import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_fountain_nib.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/data/extensions/list_extensions.dart';
import 'package:saber/data/extensions/point_extensions.dart';
import 'package:sbn/has_size.dart';
import 'package:sbn/tool_id.dart';

class Stroke {
  static final log = Logger('Stroke');

  @visibleForTesting
  @protected
  final List<PointVector> points = [];

  bool get isEmpty => points.isEmpty;
  int get length => points.length;

  int pageIndex;
  HasSize page;
  final ToolId toolId;

  static const defaultColor = Colors.black;
  static const defaultPressureEnabled = true;

  Color color;
  bool pressureEnabled;
  final StrokeOptions options;

  /// The nib this stroke was drawn with (only used by the fountain pen).
  /// Stored per stroke so changing the pen settings never alters old ink.
  final NibSettings nib;

  List<Offset>? _lowQualityPolygon, _highQualityPolygon;
  List<Offset> get lowQualityPolygon =>
      _lowQualityPolygon ??= _polygonFor(.low);
  List<Offset> get highQualityPolygon =>
      _highQualityPolygon ??= _polygonFor(.high);

  /// The fountain pen's outline is identical at every quality, so reuse
  /// (a copy of) one that was already computed instead of running
  /// perfect_freehand a second time. It must be a copy because [shift]
  /// shifts both polygons in place.
  List<Offset> _polygonFor(StrokeQuality quality) {
    if (toolId == .fountainPen && runtimeType == Stroke) {
      final other = quality == .low ? _highQualityPolygon : _lowQualityPolygon;
      if (other != null) return List.of(other);
    }
    return getPolygon(quality: quality);
  }

  Path? _lowQualityPath, _highQualityPath;
  Path get lowQualityPath =>
      _lowQualityPath ??= getPath(lowQualityPolygon, smooth: false);
  // The fountain pen fills the raw outline polygon (like pen_pal's
  // `Path.addPolygon`), never the quadratic-smoothed version.
  Path get highQualityPath => _highQualityPath ??= getPath(
    highQualityPolygon,
    smooth: toolId != .fountainPen,
  );

  /// True when this stroke is a single tap of the fountain pen, which pen_pal
  /// draws as a plain circle (see [fountainPenDotRadius]).
  bool get isFountainPenDot =>
      toolId == .fountainPen && runtimeType == Stroke && points.length == 1;
  Offset get fountainPenDotCenter => Offset(points.first.dx, points.first.dy);
  double get fountainPenDotRadius => FountainNib.dotRadius(nib, options.size);

  void shift(Offset offset) {
    if (offset == .zero) return;

    points.shift(offset);
    _lowQualityPolygon?.shift(offset);
    _highQualityPolygon?.shift(offset);
    _lowQualityPath = _lowQualityPath?.shift(offset);
    _highQualityPath = _highQualityPath?.shift(offset);
  }

  /// Makes this stroke a transformed copy of [original]:
  /// every point is mapped by [transform], and the pen size is scaled with it.
  /// Always computed from [original] so repeated calls don't build up error.
  void applyTransform(Stroke original, StrokeTransform transform) {
    final count = min(points.length, original.points.length);
    for (var i = 0; i < count; i++) {
      final point = original.points[i];
      final mapped = transform.apply(Offset(point.dx, point.dy));
      points[i] = PointVector(mapped.dx, mapped.dy, point.pressure);
    }
    options.size = original.options.size * transform.sizeScale;
    markPolygonNeedsUpdating();
  }

  void markPolygonNeedsUpdating() {
    _lowQualityPolygon = null;
    _highQualityPolygon = null;
    _lowQualityPath = null;
    _highQualityPath = null;
  }

  new({
    required this.color,
    required this.pressureEnabled,
    required this.options,
    required this.pageIndex,
    required this.page,
    required this.toolId,
    this.nib = const NibSettings(),
  });

  factory fromJson(
    Map<String, dynamic> json, {
    required int fileVersion,
    required int pageIndex,
    required HasSize page,
  }) {
    assert(json['i'] == pageIndex || json['i'] == null);
    switch (json['shape'] as String?) {
      case null:
        break;
      case 'circle':
        return CircleStroke.fromJson(
          json,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      case 'rect':
        return RectangleStroke.fromJson(
          json,
          fileVersion: fileVersion,
          pageIndex: pageIndex,
          page: page,
        );
      default:
        log.severe('Unknown shape: ${json['shape']}');
    }

    final ToolId toolId = .parsePenType(json['ty'], fallback: .fountainPen);

    final options = StrokeOptions.fromJson(json);
    final pressureEnabled = json['pe'] ?? defaultPressureEnabled;
    if (toolId == .shapePen) {
      // Set smoothing and streamline to 0 for ShapePen
      // to mitigate https://github.com/saber-notes/saber/issues/1587
      options.smoothing = 0;
      options.streamline = 0;
    }

    final Color color;
    switch (json['c']) {
      case (final int value):
        color = Color(value);
      case (final Int64 value):
        color = Color(value.toInt());
      case null:
        color = defaultColor;
      default:
        throw Exception(
          'Invalid color value: (${json['c'].runtimeType}) ${json['c']}',
        );
    }

    final offset = Offset(json['ox'] ?? 0, json['oy'] ?? 0);
    final pointsJson = json['p'] as List<dynamic>;
    final Iterable<PointVector> points;
    if (fileVersion >= 13) {
      points = pointsJson.map(
        (point) => PointExtensions.fromBsonBinary(json: point, offset: offset),
      );
    } else {
      points = pointsJson.map(
        // ignore: deprecated_member_use_from_same_package
        (point) => PointExtensions.fromJson(
          json: Map<String, dynamic>.from(point),
          offset: offset,
        ),
      );
    }

    final nibJson = json['nib'];
    return Stroke(
      color: color,
      pressureEnabled: pressureEnabled,
      options: options,
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
      nib: nibJson == null
          ? const NibSettings()
          : NibSettings.fromJson(nibJson),
    )..points.addAll(points);
  }
  Map<String, dynamic> toJson() {
    // these json keys should not be the same as the ones in [StrokeOptions.toJson]
    return {
      'shape': null,
      'p': points
          .where((point) => point.isFinite)
          .map((PointVector point) => point.toBsonBinary())
          .toList(),
      'i': pageIndex,
      'ty': toolId.id,
      'pe': pressureEnabled,
      'c': color.toARGB32(),
      if (toolId == .fountainPen) 'nib': nib.toJson(),
    }..addAll(options.toJson());
  }

  void addPoint(Offset point, [double? pressure]) {
    if (!pressureEnabled) {
      pressure = null;
    } else if (pressure != null) {
      options.simulatePressure = false;
    }

    points.add(PointVector(point.dx, point.dy, pressure));
    markPolygonNeedsUpdating();
  }

  void addPoints(List<Offset> points) {
    for (final point in points) {
      addPoint(point);
    }
  }

  void popFirstPoint() {
    points.removeAt(0);
    markPolygonNeedsUpdating();
  }

  /// Points that are closer than this
  /// threshold multiplied by the stroke's size
  /// will be counted as duplicates.
  static const _optimisePointsThreshold = 0.1;

  /// Removes points that are too close together. See [_optimisePointsThreshold].
  ///
  /// This function is idempotent, so running it multiple times
  /// will not change the result.
  ///
  /// This function does not change [_polygonNeedsUpdating].
  void optimisePoints({double thresholdMultiplier = _optimisePointsThreshold}) {
    if (points.length <= 3) return;

    final minDistance = options.size * thresholdMultiplier;

    // Remove points with null pressure because they were duplicates
    points.removeWhere((point) => point.pressure == null);

    for (int i = 1; i < points.length - 1; i++) {
      final point = points[i];
      final prev = points[i - 1];
      final next = points[i + 1];

      if (prev.distanceSquaredTo(point) < minDistance * minDistance &&
          point.distanceSquaredTo(next) < minDistance * minDistance) {
        points.removeAt(i);
        i--;
      }
    }
  }

  @protected
  List<Offset> getPolygon({required StrokeQuality quality}) {
    if (!pressureEnabled) {
      options.simulatePressure = false;
    }

    // The fountain pen is a 1:1 port of pen_pal: every point is kept and the
    // same outline is used at every zoom level.
    if (toolId == .fountainPen) {
      return FountainNib.polygon(
        points,
        nib: nib,
        size: options.size,
        isComplete: options.isComplete,
      );
    }

    final rememberSimulatedPressure =
        quality == .high && options.simulatePressure && options.isComplete;

    final skipped = skipPoints(points, quality.N);
    final qualityOptions = quality == .low
        ? options.copyWith(simulatePressure: false, smoothing: 0, streamline: 0)
        : options;

    final polygon = getStroke(
      skipped,
      options: qualityOptions,
      rememberSimulatedPressure: rememberSimulatedPressure,
    );

    if (rememberSimulatedPressure) {
      // Ensure we don't simulate pressure again
      options.simulatePressure = false;
      // Remove points that are too close together
      optimisePoints();
    }

    return polygon;
  }

  /// Returns a [Path] that represents the stroke.
  ///
  /// If [smooth] is true, and the stroke is complete,
  /// the path will be a smooth curve between the points in [polygon].
  ///
  /// Otherwise, the path will use straight lines between each point
  /// in [polygon] for performance.
  @protected
  Path getPath(List<Offset> polygon, {bool smooth = true}) {
    if (smooth && options.isComplete) {
      return smoothPathFromPolygon(polygon);
    }

    return Path()..addPolygon(polygon, true);
  }

  /// Returns a list with every Nth point in [points].
  static List<PointVector> skipPoints(List<PointVector> points, int N) {
    // Nothing is being skipped, just return [points].
    if (N <= 1) return points;

    // If we have too few points, skip less points
    final divided = points.length / N;
    const minDivided = 8;
    if (divided < minDivided) {
      N = (N * divided / minDivided).floor();
      if (N <= 1) return points;
    }

    return [
      for (int i = 0; i < points.length - 1; i += N) points[i],
      points.last,
    ];
  }

  static Path smoothPathFromPolygon(List<Offset> polygon) {
    final path = Path();
    path.moveTo(polygon.first.dx, polygon.first.dy);
    for (int i = 1; i < polygon.length - 1; i++) {
      final p1 = polygon[i];
      final p2 = polygon[i + 1];
      final mid = (p1 + p2) / 2;
      path.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
    }
    return path..close();
  }

  String toSvgPath() {
    String toSvgPoint(Offset point) {
      return '${point.dx} '
          '${page.size.height - point.dy}';
    }

    // Remove NaN points, and convert to SVG coordinates
    final svgPoints = highQualityPolygon
        .where((offset) => offset.isFinite)
        .map(toSvgPoint);

    return svgPoints.isNotEmpty ? 'M${svgPoints.join('L')}' : '';
  }

  double get maxY {
    return points.isEmpty ? 0 : points.map((point) => point.y).reduce(max);
  }

  /// The bounding box of this stroke's points, in logical pixels.
  Rect get boundingBox {
    if (points.isEmpty) return Rect.zero;
    var minX = double.infinity, maxX = double.negativeInfinity;
    var minY = double.infinity, maxY = double.negativeInfinity;
    for (final point in points) {
      if (point.dx < minX) minX = point.dx;
      if (point.dx > maxX) maxX = point.dx;
      if (point.dy < minY) minY = point.dy;
      if (point.dy > maxY) maxY = point.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// The diagonal of this stroke's bounding box, in logical pixels.
  /// Useful for size-based filters (e.g. shape snapping).
  double get boundingBoxDiagonal {
    final box = boundingBox;
    return sqrt(box.width * box.width + box.height * box.height);
  }

  RecognizedUnistroke? detectShape() {
    if (points.length < 3) return null;
    return recognizeUnistroke(points);
  }

  /// Uses the one_dollar_unistroke_recognizer package
  /// only to recognize straight lines.
  ///
  /// In addition, the line must be sufficiently long
  /// relative to [options.size].
  bool isStraightLine([int minLength = 5]) {
    if (points.length < 3) return false;

    final recognized = recognizeUnistroke(
      points,
      overrideReferenceUnistrokes: default$1Unistrokes
          .where((unistroke) => unistroke.name == DefaultUnistrokeNames.line)
          .toList(),
    );
    if (recognized == null) return false;
    assert(recognized.name == DefaultUnistrokeNames.line);
    if (recognized.score < 0.7) return false;

    final sqrLength = points.first.distanceSquaredTo(points.last);
    final sqrMinLength = minLength * minLength * options.size * options.size;
    return sqrLength >= sqrMinLength;
  }

  /// Replaces the points in this stroke with a straight line.
  ///
  /// If the resulting line is close to horizontal or vertical,
  /// it will be snapped to be exactly horizontal or vertical.
  void convertToLine() {
    assert(points.length >= 2);

    // Use the average pressure
    final pressure = points.map((point) => point.pressure ?? 0.5).average;
    var firstPoint = PointVector.fromOffset(
      offset: points.first,
      pressure: pressure,
    );
    var lastPoint = PointVector.fromOffset(
      offset: points.last,
      pressure: pressure,
    );

    // Snap to the horizontal or vertical axis
    (firstPoint, lastPoint) = snapLine(firstPoint, lastPoint);

    points.clear();
    points.add(firstPoint);
    points.add(lastPoint);
    points.add(lastPoint);
    options.isComplete = true;
    options.start.taperEnabled = false;
    options.end.taperEnabled = false;
  }

  /// Snaps a line to either horizontal or vertical
  /// if the angle is close enough.
  static (PointVector firstPoint, PointVector lastPoint) snapLine(
    PointVector firstPoint,
    PointVector lastPoint,
  ) {
    final dx = (lastPoint.dx - firstPoint.dx).abs();
    final dy = (lastPoint.dy - firstPoint.dy).abs();
    final angle = atan2(dy, dx);

    const snapAngle = 5 * pi / 180; // 5 degrees
    if (angle < snapAngle) {
      // snap to horizontal
      return (
        firstPoint,
        PointVector(lastPoint.dx, firstPoint.dy, lastPoint.pressure),
      );
    } else if (angle > pi / 2 - snapAngle) {
      // snap to vertical
      return (
        firstPoint,
        PointVector(firstPoint.dx, lastPoint.dy, lastPoint.pressure),
      );
    } else {
      return (firstPoint, lastPoint);
    }
  }

  Stroke copy() => Stroke(
    color: color,
    pressureEnabled: pressureEnabled,
    options: options.copyWith(),
    pageIndex: pageIndex,
    page: page,
    toolId: toolId,
    nib: nib,
  )..points.addAll(points);
}

enum StrokeQuality(
  /// We use every Nth point for this quality level.
  final int N,
) {
  low(4),
  high(1)
}

/// A scale (about [anchor]) followed by a rotation (about [anchor]):
/// `anchor + R(angle) * S(scaleX, scaleY) * (p - anchor)`.
class StrokeTransform {
  const StrokeTransform({
    required this.anchor,
    this.scaleX = 1,
    this.scaleY = 1,
    this.angle = 0,
  });

  final Offset anchor;
  final double scaleX, scaleY;

  /// In radians.
  final double angle;

  Offset apply(Offset point) {
    final d = point - anchor;
    final x = d.dx * scaleX;
    final y = d.dy * scaleY;
    final c = cos(angle);
    final s = sin(angle);
    return anchor + Offset(x * c - y * s, x * s + y * c);
  }

  /// How much line widths (and circle radii) change.
  double get sizeScale => sqrt(scaleX.abs() * scaleY.abs());

  /// The same transform as a column-major 4x4 matrix for [Path.transform].
  Float64List get matrix4 {
    final c = cos(angle);
    final s = sin(angle);
    final a = c * scaleX;
    final b = s * scaleX;
    final cc = -s * scaleY;
    final d = c * scaleY;
    final tx = anchor.dx - (a * anchor.dx + cc * anchor.dy);
    final ty = anchor.dy - (b * anchor.dx + d * anchor.dy);
    return Float64List.fromList([
      a, b, 0, 0, //
      cc, d, 0, 0, //
      0, 0, 1, 0, //
      tx, ty, 0, 1, //
    ]);
  }
}
