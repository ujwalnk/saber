import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:saber/components/toolbar/nib_settings_panel.dart';
import 'package:saber/components/toolbar/samsung_panel.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/tool_id.dart';

/// Compact options popover for the pen, highlighter and pencil.
///
/// It is shown by the toolbar as a small overlay attached to the toolbar
/// (see `Toolbar`), and has a fixed [width] so it stays neat.
class PenModal extends StatefulWidget {
  const new({
    super.key,
    required this.getTool,
    required this.setTool,
    this.width = defaultWidth,
  });

  final Tool Function() getTool;
  final void Function(Pen) setTool;
  final double width;

  static const double defaultWidth = 336;

  @override
  State<PenModal> createState() => _PenModalState();
}

class _PenModalState extends State<PenModal> {
  /// Whether the fountain pen's nib sliders are expanded.
  bool _nibOpen = false;

  @override
  Widget build(BuildContext context) {
    final Tool currentTool = widget.getTool();
    final Pen currentPen;
    if (currentTool is Pen) {
      currentPen = currentTool;
    } else {
      return const SizedBox();
    }

    final colorScheme = ColorScheme.of(context);
    final isRegularPen = currentPen is! Highlighter && currentPen is! Pencil;
    final showNibSettings =
        isRegularPen && currentPen.toolId == ToolId.fountainPen;

    return SizedBox(
      width: widget.width,
      child: SamsungPanel(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        borderRadius: 16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isRegularPen)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _penTypeButton(
                    context: context,
                    isSelected: Pen.currentPen.icon == Pen.fountainPenIcon,
                    onPressed: () => setState(() {
                      widget.setTool(Pen.fountainPen());
                    }),
                    tooltip: t.editor.pens.fountainPen,
                    icon: SvgPicture.asset(
                      'assets/images/scribble_fountain.svg',
                      width: 26,
                      height: 26 / 508 * 374,
                      theme: SvgTheme(
                        currentColor: Pen.currentPen.icon == Pen.fountainPenIcon
                            ? colorScheme.secondary
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  _penTypeButton(
                    context: context,
                    isSelected: Pen.currentPen.icon == Pen.ballpointPenIcon,
                    onPressed: () => setState(() {
                      widget.setTool(Pen.ballpointPen());
                    }),
                    tooltip: t.editor.pens.ballpointPen,
                    icon: SvgPicture.asset(
                      'assets/images/scribble_ballpoint.svg',
                      width: 26,
                      height: 26 / 508 * 374,
                      theme: SvgTheme(
                        currentColor:
                            Pen.currentPen.icon == Pen.ballpointPenIcon
                            ? colorScheme.secondary
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  _penTypeButton(
                    context: context,
                    isSelected: Pen.currentPen.icon == ShapePen.shapePenIcon,
                    onPressed: () => setState(() {
                      widget.setTool(ShapePen());
                    }),
                    tooltip: t.editor.pens.shapePen,
                    icon: FaIcon(
                      ShapePen.shapePenIcon,
                      size: 18,
                      color: Pen.currentPen.icon == ShapePen.shapePenIcon
                          ? colorScheme.secondary
                          : colorScheme.onSurface,
                    ),
                  ),
                ],
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  currentPen.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            SizePicker(axis: Axis.horizontal, pen: currentPen),
            if (showNibSettings) ...[
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _nibOpen = !_nibOpen),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Nib settings',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      Icon(
                        _nibOpen ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              if (_nibOpen) const NibSettingsPanel(),
            ],
          ],
        ),
      ),
    );
  }

  /// Samsung Notes-style pen type button: 44x44, 10px radius,
  /// 2px orange ring when selected.
  Widget _penTypeButton({
    required BuildContext context,
    required bool isSelected,
    required VoidCallback onPressed,
    required String tooltip,
    required Widget icon,
  }) {
    const orange = Color(0xFFFF6B35);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 52,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: isSelected
                ? orange.withValues(alpha: 0.15)
                : Colors.transparent,
            border: Border.all(
              color: isSelected ? orange : Colors.transparent,
              width: 2,
            ),
          ),
          child: icon,
        ),
      ),
    );
  }
}
