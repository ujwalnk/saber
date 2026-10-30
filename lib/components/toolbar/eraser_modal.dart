import 'package:flutter/material.dart';
import 'package:saber/components/toolbar/pen_modal.dart';
import 'package:saber/components/toolbar/samsung_panel.dart';
import 'package:saber/components/toolbar/step_slider.dart';
import 'package:saber/data/prefs.dart';

/// Compact options popover for the eraser: its size, and whether it should
/// only erase highlighter strokes.
///
/// Shown by the toolbar as a small overlay, like [PenModal]. Both settings
/// are stored in [stows] and apply to the eraser immediately.
class EraserModal extends StatefulWidget {
  const new({super.key, this.width = PenModal.defaultWidth});

  final double width;

  static const double sizeMin = 5;
  static const double sizeMax = 60;
  static const double sizeStep = 5;

  @override
  State<EraserModal> createState() => _EraserModalState();
}

class _EraserModalState extends State<EraserModal> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final size = stows.eraserSize.value;

    return SizedBox(
      width: widget.width,
      child: SamsungPanel(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        borderRadius: 16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Eraser',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Row(
              children: [
                Column(
                  children: [
                    Text(
                      'Size',
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.8),
                        fontSize: 10,
                        height: 1,
                      ),
                    ),
                    Text(size.round().toString()),
                  ],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: StepSlider(
                    value: size,
                    min: EraserModal.sizeMin,
                    max: EraserModal.sizeMax,
                    step: EraserModal.sizeStep,
                    onChanged: (value) =>
                        setState(() => stows.eraserSize.value = value),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Only erase highlighter',
                style: TextStyle(fontSize: 13),
              ),
              value: stows.eraseHighlighterOnly.value,
              onChanged: (value) =>
                  setState(() => stows.eraseHighlighterOnly.value = value),
            ),
          ],
        ),
      ),
    );
  }
}
