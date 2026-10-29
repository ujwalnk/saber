import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:sbn/canvas_background_pattern.dart';

class CanvasBackgroundPainter extends CustomPainter {
  const new({
    required this.invert,
    required this.backgroundColor,
    this.backgroundPattern = .none,
    required this.lineHeight,
    required this.lineThickness,
    this.primaryColor = Colors.blue,
    this.secondaryColor = Colors.red,
    this.preview = false,
  });

  final bool invert;
  final Color backgroundColor;

  /// The pattern to use for the background. See [CanvasBackgroundPatterns].
  final CanvasBackgroundPattern backgroundPattern;

  /// The height between each line in the background pattern
  final int lineHeight;
  final int lineThickness;
  final Color primaryColor, secondaryColor;

  /// Whether to draw the background pattern in a preview mode (more opaque).
  final bool preview;

  @override
  void paint(Canvas canvas, Size size) {
    final canvasRect = Offset.zero & size;
    final paint = Paint();

    paint.color = backgroundColor.withInversion(invert);
    canvas.drawRect(canvasRect, paint);

    paint.strokeWidth = lineThickness.toDouble();

    if (backgroundPattern.requiresClipping) {
      canvas.save();
      canvas.clipRect(canvasRect);
    }

    for (final element in getPatternElements(
      pattern: backgroundPattern,
      size: size,
      lineHeight: lineHeight,
    )) {
      if (element.secondaryColor) {
        paint.color = secondaryColor.withValues(alpha: preview ? 0.5 : 0.2);
      } else {
        paint.color = primaryColor.withValues(alpha: preview ? 0.5 : 0.2);
      }

      if (element.isLine) {
        canvas.drawLine(element.start, element.end, paint);
      } else {
        canvas.drawCircle(element.start, paint.strokeWidth * 4 / 3, paint);
      }
    }

    if (backgroundPattern.requiresClipping) {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(CanvasBackgroundPainter oldDelegate) =>
      kDebugMode ||
      oldDelegate.invert != invert ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.backgroundPattern != backgroundPattern ||
      oldDelegate.lineHeight != lineHeight ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.secondaryColor != secondaryColor;

  static Iterable<PatternElement> getPatternElements({
    required CanvasBackgroundPattern pattern,
    required Size size,
    required int lineHeight,
  }) sync* {
    switch (pattern) {
      case .none:
        return;
      case .collegeLtr:
      case .collegeRtl:
      case .lined:
        // horizontal lines
        for (double y = lineHeight * 2; y < size.height; y += lineHeight) {
          yield PatternElement(
            Offset(0, y),
            Offset(size.width, y),
            isLine: true,
          );
        }

        // vertical line
        if (pattern == .collegeLtr) {
          yield PatternElement(
            Offset(lineHeight * 2, 0),
            Offset(lineHeight * 2, size.height),
            isLine: true,
            secondaryColor: true,
          );
        } else if (pattern == .collegeRtl) {
          yield PatternElement(
            Offset(size.width - lineHeight * 2, 0),
            Offset(size.width - lineHeight * 2, size.height),
            isLine: true,
            secondaryColor: true,
          );
        }
      case .grid:
        // Grids cover the whole page, including the top margin.
        for (double y = 0; y < size.height; y += lineHeight) {
          yield PatternElement(
            Offset(0, y),
            Offset(size.width, y),
            isLine: true,
          );
        }
        for (double x = 0; x < size.width; x += lineHeight) {
          yield PatternElement(
            Offset(x, 0),
            Offset(x, size.height),
            isLine: true,
          );
        }
      case .dots:
        for (double y = lineHeight * 2; y <= size.height; y += lineHeight) {
          for (double x = 0; x <= size.width; x += lineHeight) {
            yield PatternElement(Offset(x, y), Offset(x, y), isLine: false);
          }
        }
      case .staffs:
      case .tablature:
        final staffSpaces = pattern == .staffs ? 4 : 5;
        final staffHeight = lineHeight * staffSpaces;
        final staffSpacing = lineHeight * 3;

        for (
          double topOfStaff = staffSpacing.toDouble() - lineHeight;
          topOfStaff + staffHeight < size.height;
          topOfStaff += staffHeight + staffSpacing
        ) {
          // horizontal lines
          for (int line = 0; line < staffSpaces + 1; line++) {
            yield PatternElement(
              Offset(lineHeight.toDouble(), topOfStaff + lineHeight * line),
              Offset(size.width - lineHeight, topOfStaff + lineHeight * line),
              isLine: true,
            );
          }

          // vertical lines on either side
          yield PatternElement(
            Offset(lineHeight.toDouble(), topOfStaff),
            Offset(lineHeight.toDouble(), topOfStaff + staffHeight),
            isLine: true,
          );
          yield PatternElement(
            Offset(size.width - lineHeight, topOfStaff),
            Offset(size.width - lineHeight, topOfStaff + staffHeight),
            isLine: true,
          );
        }
      case .cornell:
        // half-width line for name field
        yield PatternElement(
          Offset(lineHeight.toDouble(), lineHeight * 2),
          Offset(size.width / 2 - lineHeight / 2, lineHeight * 2),
          isLine: true,
        );
        // half-width line for date field
        yield PatternElement(
          Offset(size.width / 2 + lineHeight / 2, lineHeight * 2),
          Offset(size.width - lineHeight, lineHeight * 2),
          isLine: true,
        );
        // full-width line for title field
        yield PatternElement(
          Offset(lineHeight.toDouble(), lineHeight * 3),
          Offset(size.width - lineHeight, lineHeight * 3),
          isLine: true,
        );

        // lines for main notes
        final left = size.width * 0.35; // 35% width reserved for cues column
        final bottom = size.height * 0.7; // 30% height reserved for summary
        for (double y = lineHeight * 5; y < bottom; y += lineHeight) {
          yield PatternElement(
            Offset(left, y),
            Offset(size.width - lineHeight, y),
            isLine: true,
          );
        }
      case .wideRuled:
        {
          final spacing = lineHeight * 1.5;
          for (double y = spacing * 2; y < size.height; y += spacing) {
            yield PatternElement(
              Offset(0, y),
              Offset(size.width, y),
              isLine: true,
            );
          }
        }
      case .narrowRuled:
        {
          final spacing = lineHeight * 2 / 3;
          for (double y = spacing * 2; y < size.height; y += spacing) {
            yield PatternElement(
              Offset(0, y),
              Offset(size.width, y),
              isLine: true,
            );
          }
        }
      case .largeGrid:
        {
          final spacing = lineHeight * 1.5;
          for (double y = 0; y < size.height; y += spacing) {
            yield PatternElement(
              Offset(0, y),
              Offset(size.width, y),
              isLine: true,
            );
          }
          for (double x = 0; x < size.width; x += spacing) {
            yield PatternElement(
              Offset(x, 0),
              Offset(x, size.height),
              isLine: true,
            );
          }
        }
      case .smallGrid:
        {
          final spacing = lineHeight / 2;
          for (double y = 0; y < size.height; y += spacing) {
            yield PatternElement(
              Offset(0, y),
              Offset(size.width, y),
              isLine: true,
            );
          }
          for (double x = 0; x < size.width; x += spacing) {
            yield PatternElement(
              Offset(x, 0),
              Offset(x, size.height),
              isLine: true,
            );
          }
        }
      case .largeDots:
        {
          final spacing = lineHeight * 1.5;
          for (double y = spacing * 2; y <= size.height; y += spacing) {
            for (double x = 0; x <= size.width; x += spacing) {
              yield PatternElement(Offset(x, y), Offset(x, y), isLine: false);
            }
          }
        }
      case .smallDots:
        {
          final spacing = lineHeight / 2;
          for (double y = spacing * 2; y <= size.height; y += spacing) {
            for (double x = 0; x <= size.width; x += spacing) {
              yield PatternElement(Offset(x, y), Offset(x, y), isLine: false);
            }
          }
        }
      case .isometricDots:
        {
          final spacing = lineHeight.toDouble();
          var row = 0;
          for (double y = spacing * 2; y <= size.height; y += spacing, row++) {
            final xOffset = row.isOdd ? spacing / 2 : 0.0;
            for (double x = xOffset; x <= size.width; x += spacing) {
              yield PatternElement(Offset(x, y), Offset(x, y), isLine: false);
            }
          }
        }
      case .seyesRuled:
        {
          // main grid squares
          for (double y = 0; y < size.height; y += lineHeight) {
            yield PatternElement(
              Offset(0, y),
              Offset(size.width, y),
              isLine: true,
            );
          }
          for (double x = 0; x < size.width; x += lineHeight) {
            yield PatternElement(
              Offset(x, 0),
              Offset(x, size.height),
              isLine: true,
            );
          }
          // interlines through each square (secondary color, like real Seyes paper)
          final half = lineHeight / 2;
          for (double y = half; y < size.height; y += lineHeight) {
            yield PatternElement(
              Offset(0, y),
              Offset(size.width, y),
              isLine: true,
              secondaryColor: true,
            );
          }
        }
      case .crossGrid:
        {
          final spacing = lineHeight.toDouble();
          final arm = spacing * 0.22;
          for (double y = 0; y <= size.height; y += spacing) {
            for (double x = 0; x <= size.width; x += spacing) {
              yield PatternElement(
                Offset(x - arm, y),
                Offset(x + arm, y),
                isLine: true,
              );
              yield PatternElement(
                Offset(x, y - arm),
                Offset(x, y + arm),
                isLine: true,
              );
            }
          }
        }
      case .dashedLines:
        {
          const dashLength = 12.0;
          const gapLength = 8.0;
          for (double y = lineHeight * 2; y < size.height; y += lineHeight) {
            for (double x = 0; x < size.width; x += dashLength + gapLength) {
              yield PatternElement(
                Offset(x, y),
                Offset((x + dashLength).clamp(0.0, size.width), y),
                isLine: true,
              );
            }
          }
        }
      case .checklist:
        {
          final boxSize = lineHeight * 0.55;
          final boxLeft = lineHeight * 0.75;
          final textLeft = boxLeft + boxSize + lineHeight * 0.5;
          for (double y = lineHeight * 2; y < size.height; y += lineHeight) {
            // writing line, starting after the checkbox
            yield PatternElement(
              Offset(textLeft, y),
              Offset(size.width, y),
              isLine: true,
            );
            // checkbox square outline, vertically centered on the line
            final top = y - boxSize / 2;
            final right = boxLeft + boxSize;
            final bottom = y + boxSize / 2;
            yield PatternElement(
              Offset(boxLeft, top),
              Offset(right, top),
              isLine: true,
            );
            yield PatternElement(
              Offset(right, top),
              Offset(right, bottom),
              isLine: true,
            );
            yield PatternElement(
              Offset(right, bottom),
              Offset(boxLeft, bottom),
              isLine: true,
            );
            yield PatternElement(
              Offset(boxLeft, bottom),
              Offset(boxLeft, top),
              isLine: true,
            );
          }
        }
    }
  }
}

class PatternElement {
  final Offset start, end;

  /// Whether this is a line or a dot
  final bool isLine;

  /// Whether this should use a secondary color
  final bool secondaryColor;

  const new(
    this.start,
    this.end, {
    this.isLine = true,
    this.secondaryColor = false,
  });
}
