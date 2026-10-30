import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:saber/components/toolbar/nib_settings_panel.dart';
import 'package:saber/components/toolbar/samsung_panel.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/components/toolbar/writing_tool.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/tool_id.dart';

/// Compact options popover for all writing tools (ink pen, ballpoint,
/// pencil, marker, highlighter).
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

  /// Height of the tool strip above the divider.
  static const double _stripHeight = 72;

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
    final selected = WritingTool.of(currentPen);
    final isShapePen = currentPen is ShapePen;
    final showNibSettings =
        selected == WritingTool.inkPen && currentPen.toolId == ToolId.fountainPen;

    return SizedBox(
      width: widget.width,
      child: SamsungPanel(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        borderRadius: 16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: PenModal._stripHeight,
              child: Row(
                children: [
                  for (final tool in WritingTool.values)
                    Expanded(
                      child: _ToolSlot(
                        tool: tool,
                        selected: tool == selected,
                        onPressed: () => setState(() {
                          if (tool != selected) widget.setTool(tool.instance);
                        }),
                      ),
                    ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outlineVariant,
            ),
            const SizedBox(height: 4),
            _shapePenToggle(colorScheme, isShapePen),
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

  /// The shape pen isn't one of the five tools above, so it stays
  /// reachable as a toggle in the settings area.
  Widget _shapePenToggle(ColorScheme colorScheme, bool isShapePen) {
    const orange = Color(0xFFFF6B35);
    return Align(
      alignment: Alignment.centerRight,
      child: Tooltip(
        message: t.editor.pens.shapePen,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() {
            widget.setTool(isShapePen ? WritingTool.inkPen.instance : ShapePen());
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: isShapePen
                  ? orange.withValues(alpha: 0.15)
                  : Colors.transparent,
              border: Border.all(
                color: isShapePen ? orange : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FaIcon(
                  ShapePen.shapePenIcon,
                  size: 14,
                  color: isShapePen
                      ? colorScheme.secondary
                      : colorScheme.onSurface,
                ),
                const SizedBox(width: 6),
                Text(
                  t.editor.pens.shapePen,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One tool in the strip. The artwork is much taller than the strip and is
/// anchored to its top, so the strip's bottom edge (the divider) clips it.
/// Selecting a tool slides it up, so more of it shows above the others.
class _ToolSlot extends StatelessWidget {
  const _ToolSlot({
    required this.tool,
    required this.selected,
    required this.onPressed,
  });

  final WritingTool tool;
  final bool selected;
  final VoidCallback onPressed;

  static const double _baseWidth = 30;
  static const double _restingTop = 24;
  static const double _liftedTop = 4;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tool.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ClipRect(
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                top: selected ? _liftedTop : _restingTop,
                left: 0,
                right: 0,
                height: 400,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Image.asset(
                    tool.asset,
                    width: _baseWidth * tool.widthFactor,
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topCenter,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
