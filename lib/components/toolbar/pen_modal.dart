import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:saber/components/toolbar/nib_settings_panel.dart';
import 'package:saber/components/toolbar/samsung_panel.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/components/toolbar/step_slider.dart';
import 'package:saber/components/toolbar/writing_tool.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pen_preset.dart';
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
    this.tapGroupId,
  });

  final Tool Function() getTool;
  final void Function(Pen) setTool;
  final double width;

  /// The toolbar's `TapRegion` group, so that dialogs opened from here
  /// (naming a favourite) don't count as taps outside and close the popup.
  final Object? tapGroupId;

  static const double defaultWidth = 336;

  /// Height of the tool strip above the divider.
  static const double _stripHeight = 72;

  @override
  State<PenModal> createState() => _PenModalState();
}

class _PenModalState extends State<PenModal> {
  /// Whether the fountain pen's nib sliders are expanded.
  bool _nibOpen = false;

  late List<PenPreset> _presets = PenPreset.loadAll();

  /// Whether the favourites tab is showing. Always starts on favourites
  /// when there are any.
  late bool _showFavourites = _presets.isNotEmpty;

  /// The favourite that was last picked from the list.
  String? _appliedId;

  static const double _favouritesMaxHeight = 260;

  void _setPresets(List<PenPreset> presets) {
    PenPreset.saveAll(presets);
    setState(() {
      _presets = presets;
      // no favourites left: there's no tab to show any more
      if (presets.isEmpty) _showFavourites = false;
    });
  }

  Future<String?> _askName(String title, String initial) => showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(
      title: title,
      initial: initial,
      tapGroupId: widget.tapGroupId,
    ),
  );

  Future<void> _saveCurrentAsFavourite(Pen pen) async {
    final name = await _askName(
      'Save as favourite',
      '${WritingTool.of(pen)?.label ?? t.editor.pens.shapePen} '
          '${_prettySize(pen.options.size)}',
    );
    if (name == null) return;
    // the popup may have been closed meanwhile: read what's stored now
    final presets = PenPreset.loadAll()..add(PenPreset.capture(pen, name));
    if (mounted) {
      _setPresets(presets);
    } else {
      PenPreset.saveAll(presets);
    }
  }

  Future<void> _rename(PenPreset preset) async {
    final name = await _askName('Rename pen', preset.name);
    if (name == null) return;
    final presets = [
      for (final p in PenPreset.loadAll())
        if (p.id == preset.id) p.copyWith(name: name) else p,
    ];
    if (mounted) {
      _setPresets(presets);
    } else {
      PenPreset.saveAll(presets);
    }
  }

  void _remove(PenPreset preset) => _setPresets([
    for (final p in _presets)
      if (p.id != preset.id) p,
  ]);

  void _apply(PenPreset preset) {
    widget.setTool(preset.toPen());
    setState(() => _appliedId = preset.id);
  }

  static String _prettySize(double size) =>
      size == size.roundToDouble()
          ? size.round().toString()
          : size.toStringAsFixed(1);

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
        selected == WritingTool.inkPen &&
        currentPen.toolId == ToolId.fountainPen;

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
            Divider(height: 1, thickness: 1, color: colorScheme.outlineVariant),
            const SizedBox(height: 4),
            if (_presets.isNotEmpty) _tabs(colorScheme),
            if (_presets.isNotEmpty && _showFavourites)
              _favouritesList(colorScheme, currentPen)
            else ...[
            _topRow(colorScheme, currentPen, isShapePen),
            SizePicker(axis: Axis.horizontal, pen: currentPen),
            // The highlighter has its own fixed transparency.
            if (currentPen is! Highlighter)
              _OpacityPicker(
                // rebuild when switching tools
                key: ValueKey(currentPen),
                pen: currentPen,
              ),
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
          ],
        ),
      ),
    );
  }

  /// "Favourites" / "New pen" tabs. Only shown once there is a favourite.
  Widget _tabs(ColorScheme colorScheme) {
    Widget tab(String label, bool favourites) {
      final selected = _showFavourites == favourites;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _showFavourites = favourites),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  width: 2,
                  color: selected ? colorScheme.primary : Colors.transparent,
                ),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [tab('Favourites', true), tab('New pen', false)],
      ),
    );
  }

  /// The saved pens: pick one, rename it or remove it. No other options.
  Widget _favouritesList(ColorScheme colorScheme, Pen currentPen) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _favouritesMaxHeight),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final preset in _presets)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _apply(preset),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(preset.color).withValues(alpha: 1),
                        border: Border.all(
                          color: preset.id == _appliedId ||
                                  preset.matches(currentPen)
                              ? colorScheme.primary
                              : colorScheme.outlineVariant,
                          width: preset.id == _appliedId ||
                                  preset.matches(currentPen)
                              ? 3
                              : 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preset.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                          Text(
                            '${preset.toolLabel} · ${_prettySize(preset.size)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Rename',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _rename(preset),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _remove(preset),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The star (save the current settings as a favourite) and the shape pen
  /// toggle.
  Widget _topRow(ColorScheme colorScheme, Pen pen, bool isShapePen) {
    final saved = _presets.any((preset) => preset.matches(pen));
    return Row(
      children: [
        IconButton(
          tooltip: saved ? 'Already a favourite' : 'Save as favourite',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            saved ? Icons.star : Icons.star_border,
            color: saved ? Colors.amber : null,
          ),
          onPressed: saved ? null : () => _saveCurrentAsFavourite(pen),
        ),
        const Spacer(),
        _shapePenToggle(colorScheme, isShapePen),
      ],
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
            widget.setTool(
              isShapePen ? WritingTool.inkPen.instance : ShapePen(),
            );
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

/// Opacity slider (10-100 %) for a writing tool. The opacity is the alpha of
/// the pen's colour, so it applies to every stroke drawn afterwards and is
/// kept when the colour is changed.
class _OpacityPicker extends StatefulWidget {
  const _OpacityPicker({super.key, required this.pen});

  final Pen pen;

  @override
  State<_OpacityPicker> createState() => _OpacityPickerState();
}

class _OpacityPickerState extends State<_OpacityPicker> {
  static const double _min = 0.1, _max = 1, _step = 0.05;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final opacity = widget.pen.color.a.clamp(_min, _max);
    final percent = (opacity * 100).round();

    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Column(
            children: [
              Text(
                'Opacity',
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.8),
                  fontSize: 10,
                  height: 1,
                ),
              ),
              Text('$percent%'),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: StepSlider(
            value: opacity,
            min: _min,
            max: _max,
            step: _step,
            onChanged: (v) => setState(() {
              widget.pen.color = widget.pen.color.withValues(alpha: v);
            }),
          ),
        ),
      ],
    );
  }
}

/// Asks for a (non-empty) name. Returns it, or null if cancelled.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.initial,
    required this.tapGroupId,
  });

  final String title;
  final String initial;
  final Object? tapGroupId;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    Widget dialog = AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
    // taps in the dialog shouldn't close the pen popup behind it
    if (widget.tapGroupId != null) {
      dialog = TapRegion(groupId: widget.tapGroupId, child: dialog);
    }
    return dialog;
  }
}
