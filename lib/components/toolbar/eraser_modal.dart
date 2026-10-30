import 'package:flutter/material.dart';
import 'package:saber/components/toolbar/samsung_panel.dart';
import 'package:saber/components/toolbar/step_slider.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/i18n/strings.g.dart';

/// Compact options popover for the eraser: just its size.
///
/// Shown by the toolbar the same way as [PenModal].
class EraserModal extends StatefulWidget {
  const new({super.key, this.width = defaultWidth});

  final double width;

  static const double defaultWidth = 336;

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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        borderRadius: 16,
        child: Row(
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
                Text(size.round().toString()),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StepSlider(
                value: size,
                min: Eraser.sizeMin,
                max: Eraser.sizeMax,
                step: Eraser.sizeStep,
                onChanged: (value) =>
                    setState(() => stows.eraserSize.value = value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
