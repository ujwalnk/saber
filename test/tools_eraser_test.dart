import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:sbn/has_size.dart';
import 'package:sbn/tool_id.dart';

final _options = StrokeOptions(
  size: 1, // small size so we have more precision in test
);
const _eraserPos = Offset(50, 50);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    stows.eraseWholeStrokes.value = true;
    stows.eraseHighlighterOnly.value = false;
  });

  test('Test that the eraser tool erases the correct strokes', () {
    final eraser = Eraser(size: 10);

    final List<Stroke> strokesToErase = [
      // center
      _strokeWithPoint(_eraserPos),

      // 1 size downwards from center
      _strokeWithPoint(_eraserPos + const Offset(0, 1) * eraser.size),

      // 1 size right from center
      _strokeWithPoint(_eraserPos + const Offset(1, 0) * eraser.size),

      // 1 size diagonally from center
      _strokeWithPoint(_eraserPos + const Offset(1, 1) * sqrt(eraser.size)),

      // 0.5 sizes right from center
      _strokeWithPoint(_eraserPos + const Offset(0.5, 0) * eraser.size),

      // straight line that passes through center
      _strokeWithPoint(_eraserPos + const Offset(-20, -20) * eraser.size)
        ..addPoint(_eraserPos + const Offset(20, 20) * eraser.size)
        ..addPoint(_eraserPos + const Offset(20, 20) * eraser.size),
    ];

    final List<Stroke> strokesToKeep = [
      // > 1 size downwards from center
      _strokeWithPoint(_eraserPos + const Offset(0, 1.1) * eraser.size),

      // > 1 size right from center
      _strokeWithPoint(_eraserPos + const Offset(1.1, 0) * eraser.size),

      // > 1 size diagonally from center
      _strokeWithPoint(_eraserPos + const Offset(1, 1) * eraser.size),

      // 2 sizes right from center
      _strokeWithPoint(_eraserPos + const Offset(2, 0) * eraser.size),
    ];

    final page = EditorPage(
      size: const Size(100, 100),
      strokes: [...strokesToErase, ...strokesToKeep],
    );
    eraser.erase(_eraserPos, _eraserPos, page);
    final result = eraser.onDragEnd();

    expect(
      result.added,
      isEmpty,
      reason: 'Erasing whole strokes should not leave any pieces behind',
    );
    expect(
      result.erased.length,
      strokesToErase.length,
      reason: 'The correct number of strokes should have been erased',
    );

    for (final stroke in strokesToErase) {
      expect(
        result.erased,
        contains(stroke),
        reason: 'Stroke should be erased: $stroke',
      );
      expect(page.strokes, isNot(contains(stroke)));
    }

    for (final stroke in strokesToKeep) {
      expect(
        result.erased,
        isNot(contains(stroke)),
        reason: 'Stroke should not be erased: $stroke',
      );
      expect(page.strokes, contains(stroke));
    }
  });

  test('Test that "only erase highlighter" leaves other strokes alone', () {
    stows.eraseHighlighterOnly.value = true;
    final eraser = Eraser(size: 10);

    final pen = _strokeWithPoint(_eraserPos);
    final highlighter = _strokeWithPoint(_eraserPos, toolId: .highlighter);
    final page = EditorPage(
      size: const Size(100, 100),
      strokes: [pen, highlighter],
    );

    eraser.erase(_eraserPos, _eraserPos, page);
    final result = eraser.onDragEnd();

    expect(result.erased, [highlighter]);
    expect(page.strokes, [pen]);
  });
}

Stroke _strokeWithPoint(Offset point, {ToolId toolId = .fountainPen}) => Stroke(
  color: Stroke.defaultColor,
  pressureEnabled: Stroke.defaultPressureEnabled,
  options: _options,
  pageIndex: 0,
  page: const HasSize(Size(100, 100)),
  toolId: toolId,
)..addPoint(point);
