import 'package:flutter/material.dart';
import 'package:saber/components/canvas/_fountain_nib.dart';
import 'package:saber/data/prefs.dart';

/// Sliders for the fountain pen's nib: angle, smoothness, min & max width.
///
/// Changes are saved immediately and apply to strokes drawn afterwards;
/// existing strokes keep the nib they were drawn with.
///
/// The widths apply at toolbar size [FountainNib.referenceSize]; the size
/// slider scales them proportionally.
class NibSettingsPanel extends StatefulWidget {
  const NibSettingsPanel({super.key});

  @override
  State<NibSettingsPanel> createState() => _NibSettingsPanelState();
}

class _NibSettingsPanelState extends State<NibSettingsPanel> {
  static const _orange = Color(0xFFFF6B35);

  NibSettings get _nib => stows.fountainNibSettings.value;

  void _set(NibSettings nib) {
    setState(() => stows.fountainNibSettings.value = nib);
  }

  /// Rounds to [decimals] places the way a literal would be written,
  /// so 9 / 10 gives exactly 0.9.
  static double _round(double v, int decimals) {
    final f = decimals == 0 ? 1 : (decimals == 1 ? 10 : 100);
    return (v * f).round() / f;
  }

  @override
  Widget build(BuildContext context) {
    final nib = _nib;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Wrap(
        spacing: 16,
        runSpacing: 0,
        children: [
          _row(
            context,
            label: 'Angle',
            value: nib.angle,
            min: 0,
            max: 180,
            divisions: 180,
            text: '${nib.angle.round()}°',
            onChanged: (v) => _set(nib.copyWith(angle: _round(v, 0))),
          ),
          _row(
            context,
            label: 'Smoothness',
            value: nib.smoothing,
            min: 0,
            max: 0.95,
            divisions: 19,
            text: nib.smoothing.toStringAsFixed(2),
            onChanged: (v) => _set(nib.copyWith(smoothing: _round(v, 2))),
          ),
          _row(
            context,
            label: 'Min width',
            value: nib.minWidth,
            min: 0.1,
            max: 10,
            divisions: 99,
            text: nib.minWidth.toStringAsFixed(1),
            onChanged: (v) {
              final w = _round(v, 1);
              _set(
                nib.copyWith(
                  minWidth: w,
                  // keep min <= max
                  maxWidth: w > nib.maxWidth ? w : nib.maxWidth,
                ),
              );
            },
          ),
          _row(
            context,
            label: 'Max width',
            value: nib.maxWidth,
            min: 0.1,
            max: 10,
            divisions: 99,
            text: nib.maxWidth.toStringAsFixed(1),
            onChanged: (v) {
              final w = _round(v, 1);
              _set(
                nib.copyWith(
                  maxWidth: w,
                  minWidth: w < nib.minWidth ? w : nib.minWidth,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String text,
    required ValueChanged<double> onChanged,
  }) {
    final colorScheme = ColorScheme.of(context);
    return SizedBox(
      width: 200,
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.8),
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: _orange,
                thumbColor: _orange,
                inactiveTrackColor: colorScheme.onSurface.withValues(
                  alpha: 0.2,
                ),
                trackHeight: 3,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              text,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
