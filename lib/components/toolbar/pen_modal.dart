import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:saber/components/toolbar/nib_settings_panel.dart';
import 'package:saber/components/toolbar/samsung_panel.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/data/extensions/axis_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/tool_id.dart';

class PenModal extends StatefulWidget {
  const new({super.key, required this.getTool, required this.setTool});

  final Tool Function() getTool;
  final void Function(Pen) setTool;

  @override
  State<PenModal> createState() => _PenModalState();
}

class _PenModalState extends State<PenModal> {
  @override
  Widget build(BuildContext context) {
    final axis = stows.editorToolbarAlignment.value.axis.opposite;
    final Tool currentTool = widget.getTool();
    final Pen currentPen;
    if (currentTool is Pen) {
      currentPen = currentTool;
    } else {
      return const SizedBox();
    }

    final showNibSettings =
        currentPen is! Highlighter &&
        currentPen is! Pencil &&
        currentPen.toolId == ToolId.fountainPen;

    return SamsungPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flex(
            direction: axis,
            mainAxisAlignment: .center,
            children: [
              SizePicker(axis: axis, pen: currentPen),
              if (currentPen is! Highlighter && currentPen is! Pencil) ...[
                const SizedBox.square(dimension: 8),
                _penTypeButton(
                  context: context,
                  isSelected: Pen.currentPen.icon == Pen.fountainPenIcon,
                  onPressed: () => setState(() {
                    widget.setTool(Pen.fountainPen());
                  }),
                  tooltip: t.editor.pens.fountainPen,
                  icon: SvgPicture.asset(
                    'assets/images/scribble_fountain.svg',
                    width: 28,
                    height: 28 / 508 * 374,
                    theme: SvgTheme(
                      currentColor: Pen.currentPen.icon == Pen.fountainPenIcon
                          ? ColorScheme.of(context).secondary
                          : ColorScheme.of(context).onSurface,
                    ),
                  ),
                ),
                const SizedBox.square(dimension: 8),
                _penTypeButton(
                  context: context,
                  isSelected: Pen.currentPen.icon == Pen.ballpointPenIcon,
                  onPressed: () => setState(() {
                    widget.setTool(Pen.ballpointPen());
                  }),
                  tooltip: t.editor.pens.ballpointPen,
                  icon: SvgPicture.asset(
                    'assets/images/scribble_ballpoint.svg',
                    width: 28,
                    height: 28 / 508 * 374,
                    theme: SvgTheme(
                      currentColor: Pen.currentPen.icon == Pen.ballpointPenIcon
                          ? ColorScheme.of(context).secondary
                          : ColorScheme.of(context).onSurface,
                    ),
                  ),
                ),
                const SizedBox.square(dimension: 8),
                _penTypeButton(
                  context: context,
                  isSelected: Pen.currentPen.icon == ShapePen.shapePenIcon,
                  onPressed: () => setState(() {
                    widget.setTool(ShapePen());
                  }),
                  tooltip: t.editor.pens.shapePen,
                  icon: FaIcon(
                    ShapePen.shapePenIcon,
                    color: Pen.currentPen.icon == ShapePen.shapePenIcon
                        ? ColorScheme.of(context).secondary
                        : ColorScheme.of(context).onSurface,
                  ),
                ),
              ],
            ],
          ),
          if (showNibSettings) ...[
            const SizedBox(height: 8),
            const NibSettingsPanel(),
          ],
        ],
      ),
    );
  }

  /// Samsung Notes-style pen type button: 40x56, 10px radius,
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
          width: 40,
          height: 56,
          alignment: .center,
          decoration: BoxDecoration(
            borderRadius: .circular(10),
            color: isSelected
                ? orange.withValues(alpha: 0.15)
                : Colors.transparent,
            border: .all(
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
