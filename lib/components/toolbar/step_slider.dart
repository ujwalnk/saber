import 'package:flutter/material.dart';

/// A regular [Slider] with a minus button on one side and a plus button on
/// the other, so values can be nudged by exactly one [step].
///
/// Horizontal: `[-] ---o--- [+]`. Vertical: minus on top, plus at the bottom,
/// and the value increases downwards (same direction as the old size picker).
class StepSlider extends StatelessWidget {
  const StepSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.axis = Axis.horizontal,
    this.length = 150,
    this.activeColor,
  });

  final double value;
  final double min, max, step;
  final ValueChanged<double> onChanged;
  final Axis axis;

  /// Slider length for [Axis.vertical]. Horizontal sliders fill the width
  /// they are given, so wrap them in a [SizedBox] or [Expanded].
  final double length;

  /// Accent colour for the track and thumb. Null uses the theme's colour.
  final Color? activeColor;

  /// Snaps [v] to the nearest multiple of [step] above [min], inside
  /// [min]..[max], and removes floating point noise (0.1 + 8 * 0.1 -> 0.9).
  double _snap(double v) {
    final steps = ((v - min) / step).round();
    final snapped = (min + steps * step).clamp(min, max);
    return double.parse(snapped.toStringAsFixed(4));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final current = value.clamp(min, max);
    final divisions = ((max - min) / step).round();

    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: activeColor,
        thumbColor: activeColor,
        inactiveTrackColor: activeColor == null
            ? null
            : colorScheme.onSurface.withValues(alpha: 0.2),
        trackHeight: 3,
        overlayShape: SliderComponentShape.noOverlay,
      ),
      child: Slider(
        value: current,
        min: min,
        max: max,
        divisions: divisions < 1 ? null : divisions,
        onChanged: (v) {
          final snapped = _snap(v);
          if (snapped != current) onChanged(snapped);
        },
      ),
    );

    final minus = _StepButton(
      icon: Icons.remove,
      tooltip: '-',
      onPressed: current > min ? () => onChanged(_snap(current - step)) : null,
    );
    final plus = _StepButton(
      icon: Icons.add,
      tooltip: '+',
      onPressed: current < max ? () => onChanged(_snap(current + step)) : null,
    );

    if (axis == Axis.horizontal) {
      return Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          minus,
          Expanded(child: slider),
          plus,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        minus,
        SizedBox(
          height: length,
          child: RotatedBox(quarterTurns: 1, child: slider),
        ),
        plus,
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      splashRadius: 16,
    );
  }
}
