import 'dart:async';

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/list_extensions.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:sbn/tool_id.dart';

class LaserPointer extends Tool {
  new _();

  static final _currentLaserPointer = LaserPointer._();
  static LaserPointer get currentLaserPointer => _currentLaserPointer;

  @override
  ToolId get toolId => .laserPointer;

  static const outerColor = Colors.red;
  final pressureEnabled = false;
  final options = StrokeOptions(smoothing: 0.7, streamline: 0.7);

  /// List of timings that correspond to the delay between each point
  /// in the stroke. The first point has a delay of 0.
  ///
  /// This is used to fade out each point in the stroke one by one.
  List<Duration> strokePointDelays = [];

  /// Stopwatch used to find the time elapsed since the last point.
  final _stopwatch = Stopwatch();

  /// Everything drawn with the laser since it last faded away completely.
  ///
  /// The laser is handled as one session: the strokes fade out together, and
  /// as soon as a new stroke starts, every stroke of the session is brought
  /// back in full, so it is never left partly erased.
  static final List<_LaserSessionEntry> _session = [];

  /// Bumped whenever the session is restored or its fade-out restarts, which
  /// cancels the fade-out that was running.
  static int _generation = 0;

  /// The page the current stroke is being drawn on.
  EditorPage? _page;

  /// Whether the user is currently drawing with the laser.
  /// This is used to prevent strokes fading out until the user
  /// has finished drawing.
  static var isDrawing = false;

  void onDragStart(Offset position, EditorPage page, int pageIndex) {
    isDrawing = true;
    _page = page;
    _restoreSession();
    Pen.currentStroke = LaserStroke(
      color: outerColor,
      pressureEnabled: pressureEnabled,
      options: options.copyWith(),
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
    );

    strokePointDelays = [];
    _stopwatch.reset();
    onDragUpdate(position);
    _stopwatch.start();
  }

  void onDragUpdate(Offset position, {@visibleForTesting Duration? elapsed}) {
    isDrawing = true;
    Pen.currentStroke?.addPoint(position);
    strokePointDelays.add(elapsed ?? _stopwatch.elapsed);
    _stopwatch.reset();
  }

  LaserStroke? onDragEnd(
    VoidCallback redrawPage,
    void Function(Stroke) deleteStroke,
  ) {
    isDrawing = false;

    final stroke = Pen.currentStroke;
    Pen.currentStroke = null;
    if (stroke is! LaserStroke) return null;

    stroke
      ..options.isComplete = true
      ..markPolygonNeedsUpdating();

    final page = _page;
    if (page == null) {
      // not drawn through onDragStart: fade this stroke out by itself
      unawaited(
        fadeOutStroke(
          stroke: stroke,
          strokePointDelays: strokePointDelays,
          redrawPage: redrawPage,
          deleteStroke: deleteStroke,
        ),
      );
      return stroke;
    }

    _session.add(
      _LaserSessionEntry(
        stroke: stroke,
        page: page,
        originalPoints: List.of(stroke.points),
        strokePointDelays: List.of(strokePointDelays),
        redrawPage: redrawPage,
        deleteStroke: deleteStroke,
      ),
    );
    unawaited(_fadeOutSession());

    return stroke;
  }

  /// Puts every stroke of the session back exactly as it was drawn, and
  /// stops the fade-out that was in progress.
  static void _restoreSession() {
    _generation++;
    for (final entry in _session) {
      entry.stroke.points
        ..clear()
        ..addAll(entry.originalPoints);
      entry.stroke.markPolygonNeedsUpdating();
      // strokes that already finished fading were removed from the page
      if (!entry.page.laserStrokes.contains(entry.stroke)) {
        entry.page.laserStrokes.add(entry.stroke);
      }
      entry.redrawPage();
    }
  }

  /// Fades out the whole session. A new stroke cancels this (and restores
  /// the session) before it can finish.
  static Future<void> _fadeOutSession() async {
    final generation = ++_generation;
    bool cancelled() => generation != _generation;

    final entries = List.of(_session);
    await Future.wait([
      for (final entry in entries)
        fadeOutStroke(
          stroke: entry.stroke,
          strokePointDelays: entry.strokePointDelays,
          redrawPage: entry.redrawPage,
          deleteStroke: entry.deleteStroke,
          isCancelled: cancelled,
        ),
    ]);

    if (!cancelled()) _session.clear();
  }

  @visibleForTesting
  static const fadeOutDelay = Duration(seconds: 2);
  @visibleForTesting
  static Future<void> fadeOutStroke({
    required LaserStroke stroke,
    required List<Duration> strokePointDelays,
    required VoidCallback redrawPage,
    required void Function(LaserStroke) deleteStroke,
    @visibleForTesting Future<void> Function(Duration) wait = Future.delayed,

    /// When this returns true the fade-out stops where it is, without
    /// touching the stroke again.
    bool Function()? isCancelled,
  }) async {
    bool cancelled() => isCancelled?.call() ?? false;

    await wait(fadeOutDelay);
    if (cancelled()) return;

    for (final delay in strokePointDelays) {
      await wait(delay);
      if (cancelled()) return;

      if (stroke.length <= 1) break;

      stroke.popFirstPoint();
      redrawPage();

      if (isDrawing) {
        // if the user starts drawing again, wait until they stop
        const waitTime = Duration(milliseconds: 100);
        while (isDrawing && !cancelled()) await wait(waitTime);
        if (cancelled()) return;
        // now wait the normal delay before continuing
        await wait(fadeOutDelay - waitTime);
        if (cancelled()) return;
      }
    }

    deleteStroke(stroke);
    redrawPage();
  }
}

/// One laser stroke of the current session, with what's needed to fade it out
/// and to restore it.
class _LaserSessionEntry {
  _LaserSessionEntry({
    required this.stroke,
    required this.page,
    required this.originalPoints,
    required this.strokePointDelays,
    required this.redrawPage,
    required this.deleteStroke,
  });

  final LaserStroke stroke;
  final EditorPage page;

  /// The stroke's points as drawn, before any of them faded out.
  final List<PointVector> originalPoints;
  final List<Duration> strokePointDelays;
  final VoidCallback redrawPage;
  final void Function(LaserStroke) deleteStroke;
}

class LaserStroke extends Stroke {
  new({
    required super.color,
    required super.pressureEnabled,
    required super.options,
    required super.pageIndex,
    required EditorPage super.page,
    required super.toolId,
  });
  @visibleForTesting
  new convertStroke(Stroke stroke)
    : super(
        color: stroke.color,
        pressureEnabled: stroke.pressureEnabled,
        options: stroke.options
          ..streamline = 0.7
          ..smoothing = 0.7,
        pageIndex: stroke.pageIndex,
        page: stroke.page,
        toolId: stroke.toolId,
      ) {
    points.addAll(stroke.points);
  }

  @protected
  List<Offset> get innerPolygon => _innerPolygon ??= getStroke(
    points,
    options: options.copyWith(size: options.size * 0.4),
  );
  List<Offset>? _innerPolygon;

  /// The inner part of the stroke which is thinner and white
  /// to create a glowing effect.
  Path get innerPath =>
      _innerPath ??= Stroke.smoothPathFromPolygon(innerPolygon);
  Path? _innerPath;

  /// The outer thicker part of the stroke which is colored with [color].
  @override
  List<Offset> get highQualityPolygon => super.highQualityPolygon;

  /// The outer thicker part of the stroke which is colored with [color].
  ///
  /// Note that LODs are disabled so that the outer path matches the inner path.
  @override
  List<Offset> get lowQualityPolygon => super.highQualityPolygon;

  @override
  void shift(Offset offset) {
    _innerPolygon?.shift(offset);
    _innerPath?.shift(offset);
    super.shift(offset);
  }

  @override
  void markPolygonNeedsUpdating() {
    _innerPolygon = null;
    _innerPath = null;
    super.markPolygonNeedsUpdating();
  }
}
