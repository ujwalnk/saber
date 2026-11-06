import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:one_dollar_unistroke_recognizer/one_dollar_unistroke_recognizer.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/marker.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/tool_id.dart';

class Pen extends Tool {
  @protected
  @visibleForTesting
  new({
    required this.name,
    required this.sizeMin,
    required this.sizeMax,
    required this.sizeStep,
    required this.icon,
    required this.options,
    required this.pressureEnabled,
    required this.color,
    required this.toolId,
  });

  new fountainPen()
    : name = t.editor.pens.fountainPen,
      sizeMin = 1,
      sizeMax = 25,
      sizeStep = 1,
      icon = fountainPenIcon,
      options = stows.lastFountainPenOptions.value,
      pressureEnabled = true,
      color = Color(stows.lastFountainPenColor.value),
      toolId = .fountainPen;

  new ballpointPen()
    : name = t.editor.pens.ballpointPen,
      sizeMin = 1,
      sizeMax = 25,
      sizeStep = 1,
      icon = ballpointPenIcon,
      options = stows.lastBallpointPenOptions.value,
      pressureEnabled = false,
      color = Color(stows.lastBallpointPenColor.value),
      toolId = .ballpointPen;

  final String name;
  final double sizeMin, sizeMax, sizeStep;
  late final int sizeStepsBetweenMinAndMax = ((sizeMax - sizeMin) / sizeStep)
      .round();
  final Object icon;

  @override
  final ToolId toolId;

  static const fountainPenIcon = FontAwesomeIcons.penFancy;
  static const ballpointPenIcon = FontAwesomeIcons.pen;

  static Stroke? currentStroke;
  Color color;
  bool pressureEnabled;
  StrokeOptions options;

  /// The most recently active writing tool of any kind (ink pen, ballpoint,
  /// pencil, marker, highlighter or shape pen). The toolbar's pen button
  /// returns to this after another tool (e.g. the eraser) was used.
  static Pen? lastUsedPen;

  /// The tool the toolbar's pen button activates.
  static Pen get activePen => lastUsedPen ?? _currentPen;

  static var _currentPen = Pen.fountainPen();
  static Pen get currentPen => _currentPen;
  static set currentPen(Pen currentPen) {
    assert(
      currentPen is! Highlighter,
      'Use Highlighter.currentHighlighter instead',
    );
    assert(currentPen is! Pencil, 'Use Pencil.currentPencil instead');
    assert(currentPen is! Marker, 'Use Marker.currentMarker instead');
    _currentPen = currentPen;
  }

  void onDragStart(
    Offset position,
    EditorPage page,
    int pageIndex,
    double? pressure,
  ) {
    _resetHold();
    _holdPage = page;
    currentStroke = Stroke(
      color: color,
      pressureEnabled: pressureEnabled,
      options: options.copyWith(isComplete: false),
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
      nib: stows.fountainNibSettings.value,
    );
    onDragUpdate(position, pressure);
  }

  void onDragUpdate(Offset position, double? pressure) {
    currentStroke?.addPoint(position, pressure);
    _trackHold(position);
  }

  Stroke? onDragEnd() {
    final stroke = currentStroke;
    currentStroke = null;
    final heldShape = holdDetectedShape;
    _resetHold();
    if (stroke == null) return null;

    stroke
      ..options.isComplete = true
      ..markPolygonNeedsUpdating();

    // Strokes are left exactly as drawn, unless the pen was held still at
    // the end of the stroke (see [_trackHold]) and a shape was recognised.
    if (heldShape != null) {
      final snapped = _snapToShape(stroke, heldShape);
      if (snapped != null) return snapped;
    }

    return stroke;
  }

  // --- Hold to snap -------------------------------------------------------

  /// Whether holding the pen still at the end of a stroke snaps the stroke
  /// to a shape. The shape pen has its own always-on recognition.
  @protected
  bool get snapOnHold => true;

  /// Minimum bounding-box diagonal (logical pixels) for a stroke to be
  /// considered for shape snapping. Filters out dots and tiny marks.
  static const _minShapeSnapDiagonal = 24.0;

  /// Minimum $1 recognizer score (0.0-1.0) to snap.
  static const _minShapeSnapScore = 0.7;

  /// How far (logical pixels) the pen may drift and still count as "held
  /// still". Absorbs stylus / hand jitter.
  static const _holdMoveTolerance = 5.0;

  /// The shape the current stroke will snap to when the pen is lifted, or
  /// null if the stroke will be kept as drawn. Drawn as a preview.
  static RecognizedUnistroke? holdDetectedShape;

  static Timer? _holdTimer;
  static Offset? _holdAnchor;
  static EditorPage? _holdPage;

  /// The configured hold time, or null if hold-to-snap is turned off.
  static Duration? get holdDelay {
    if (!stows.holdToSnapDelay.loaded) return null;
    final ms = stows.holdToSnapDelay.value;
    return ms < 0 ? null : Duration(milliseconds: ms);
  }

  /// Called for every point. While the pen stays within
  /// [_holdMoveTolerance] of [_holdAnchor] the timer keeps running; moving
  /// further drops any pending snap and restarts the wait.
  void _trackHold(Offset position) {
    if (!snapOnHold) return;
    final delay = holdDelay;
    if (delay == null) return;

    final anchor = _holdAnchor;
    if (anchor != null && (position - anchor).distance <= _holdMoveTolerance) {
      return; // still holding
    }

    _holdAnchor = position;
    _holdTimer?.cancel();
    if (holdDetectedShape != null) {
      holdDetectedShape = null;
      _holdPage?.redrawStrokes();
    }
    _holdTimer = Timer(delay, _onHold);
  }

  static void _onHold() {
    final stroke = currentStroke;
    if (stroke == null) return;
    if (stroke.boundingBoxDiagonal < _minShapeSnapDiagonal) return;

    final detected = stroke.detectShape();
    if (detected == null ||
        detected.name == null ||
        detected.score < _minShapeSnapScore) {
      return;
    }

    holdDetectedShape = detected;
    HapticFeedback.selectionClick();
    _holdPage?.redrawStrokes();
  }

  static void _resetHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdAnchor = null;
    holdDetectedShape = null;
  }

  /// Drops any pending hold-to-snap (e.g. when a stroke is abandoned).
  static void cancelHold() {
    final hadShape = holdDetectedShape != null;
    _resetHold();
    if (hadShape) _holdPage?.redrawStrokes();
  }

  /// Replaces [stroke] with the clean version of [detected]. The result
  /// matches the preview drawn while holding.
  Stroke? _snapToShape(Stroke stroke, RecognizedUnistroke detected) {
    switch (detected.name) {
      case DefaultUnistrokeNames.line:
        if (stroke.points.length < 2) return null;
        return stroke..convertToLine();
      case DefaultUnistrokeNames.rectangle:
        return RectangleStroke(
          color: color,
          pressureEnabled: pressureEnabled,
          options: stroke.options,
          pageIndex: stroke.pageIndex,
          page: stroke.page,
          toolId: toolId,
          rect: detected.convertToRect(),
        );
      case DefaultUnistrokeNames.circle:
        final (center, radius) = detected.convertToCircle();
        return CircleStroke(
          color: color,
          pressureEnabled: pressureEnabled,
          options: stroke.options,
          pageIndex: stroke.pageIndex,
          page: stroke.page,
          toolId: toolId,
          radius: radius,
          center: center,
        );
      case DefaultUnistrokeNames.triangle:
      case DefaultUnistrokeNames.star:
        return Stroke(
          color: color,
          pressureEnabled: pressureEnabled,
          options: stroke.options,
          pageIndex: stroke.pageIndex,
          page: stroke.page,
          toolId: toolId,
          nib: stroke.nib,
        )..addPoints(detected.convertToCanonicalPolygon());
      default:
        return null;
    }
  }

  /// The default stroke options.
  ///
  /// Note that these are different to the default options in [StrokeOptions]
  /// e.g. [StrokeOptions.defaultSize] for historical reasons
  /// (i.e. [StrokeOptions.toJson] does not include default values.)
  static final defaultOptions = StrokeOptions(size: 5);

  // Matches the pen_pal prototype: smoothing 0.5, streamline 0.35.
  static StrokeOptions get fountainPenOptions =>
      defaultOptions.copyWith(smoothing: 0.5, streamline: 0.35);
  static StrokeOptions get ballpointPenOptions => defaultOptions.copyWith();
  static StrokeOptions get shapePenOptions =>
      defaultOptions.copyWith(smoothing: 0, streamline: 0);
  static StrokeOptions get highlighterOptions =>
      defaultOptions.copyWith(size: 50);
  static StrokeOptions get pencilOptions => defaultOptions.copyWith(
    streamline: 0.1,
    start: StrokeEndOptions.start(taperEnabled: true, customTaper: 1),
    end: StrokeEndOptions.end(taperEnabled: true, customTaper: 1),
  );
}
