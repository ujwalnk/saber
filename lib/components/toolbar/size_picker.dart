import 'package:flutter/material.dart';
import 'package:saber/components/toolbar/step_slider.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';

class SizePicker extends StatefulWidget {
  const new({super.key, required this.axis, required this.pen});

  final Axis axis;
  final Pen pen;

  @override
  State<SizePicker> createState() => _SizePickerState();

  static const double smallLength = 25;
  static const double largeLength = 150;
}

/// Returns a string representation of [num] that:
/// - Has no decimal point if [num] is an integer
/// - Has one decimal point if [num] has a non-zero fractional part
String _prettyNum(double num) {
  final rounded = num.round();
  if (num == rounded) return rounded.toString();
  return num.toStringAsFixed(1);
}

class _SizePickerState extends State<SizePicker> {
  static const _orange = Color(0xFFFF6B35);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final pen = widget.pen;

    final slider = StepSlider(
      axis: widget.axis,
      length: SizePicker.largeLength,
      value: pen.options.size,
      min: pen.sizeMin,
      max: pen.sizeMax,
      step: pen.sizeStep,
      activeColor: _orange,
      onChanged: (size) => setState(() => pen.options.size = size),
    );

    final horizontal = widget.axis == Axis.horizontal;
    return Flex(
      direction: widget.axis,
      mainAxisSize: horizontal ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Column(
          children: [
            Text(
              t.editor.penOptions.size,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.8),
                fontSize: 10,
                height: 1,
              ),
            ),
            Text(_prettyNum(pen.options.size)),
          ],
        ),
        const SizedBox(width: 8),
        if (horizontal)
          Expanded(child: slider)
        else
          Padding(padding: const .symmetric(vertical: 8), child: slider),
      ],
    );
  }
}
