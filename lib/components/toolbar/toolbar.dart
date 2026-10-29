import 'dart:io';
import 'dart:math';

import 'package:collapsible/collapsible.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:keybinder/keybinder.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/components/toolbar/eraser_modal.dart';
import 'package:saber/components/toolbar/export_bar.dart';
import 'package:saber/components/toolbar/pen_modal.dart';
import 'package:saber/components/toolbar/selection_bar.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/components/toolbar/toolbar_button.dart';
import 'package:saber/components/toolbar/toolbar_items.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/i18n/strings.g.dart';

class Toolbar extends StatefulWidget {
  const new({
    super.key,
    required this.readOnly,
    required this.setTool,
    required this.currentTool,
    required this.setColor,
    required this.quillFocus,
    required this.textEditing,
    required this.toggleTextEditing,
    required this.toggleFingerDrawing,
    required this.pickPhoto,
    required this.paste,
    required this.duplicateSelection,
    required this.deleteSelection,
    required this.showExportOptions,
    required this.exportAsSba,
    required this.exportAsPdf,
    required this.exportAsPng,
  });

  final bool readOnly;

  final ValueChanged<Tool> setTool;
  final Tool currentTool;
  final ValueChanged<Color> setColor;

  final ValueNotifier<QuillStruct?> quillFocus;
  final bool textEditing;
  final VoidCallback toggleTextEditing;

  final VoidCallback toggleFingerDrawing;

  final VoidCallback pickPhoto;

  final VoidCallback paste;

  final VoidCallback duplicateSelection;
  final VoidCallback deleteSelection;

  /// Whether the export bar is open. Opened from the editor's 3-dot menu.
  final ValueNotifier<bool> showExportOptions;

  final Future Function(BuildContext)? exportAsSba;
  final Future Function(BuildContext)? exportAsPdf;
  final Future Function(BuildContext)? exportAsPng;

  @override
  State<Toolbar> createState() => _ToolbarState();

  static const _buttonPaddingHorizontal = EdgeInsets.symmetric(horizontal: 4);
  static const _buttonPaddingVertical = EdgeInsets.symmetric(vertical: 4);
}

class _ToolbarState extends State<Toolbar> {
  ValueNotifier<bool> get showExportOptions => widget.showExportOptions;
  ValueNotifier<bool> showColorOptions = ValueNotifier(false);
  ValueNotifier<ToolOptions> toolOptionsType = ValueNotifier(ToolOptions.hide);

  /// The pen / highlighter / pencil / eraser options and the color picker
  /// are small popover overlays, attached to the toolbar bar through
  /// [_optionsLink]. Only one of them is open at a time.
  final LayerLink _optionsLink = LayerLink();
  final OverlayPortalController _optionsPortal = OverlayPortalController();
  final Object _optionsTapGroup = Object();

  static bool _isToolPopover(ToolOptions type) => switch (type) {
    ToolOptions.pen ||
    ToolOptions.highlighter ||
    ToolOptions.pencil ||
    ToolOptions.eraser => true,
    _ => false,
  };

  void _syncPopover() {
    // Wait for the frame: this can be triggered while building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final wantShown =
          showColorOptions.value || _isToolPopover(toolOptionsType.value);
      if (wantShown && !_optionsPortal.isShowing) {
        _optionsPortal.show();
      } else if (!wantShown && _optionsPortal.isShowing) {
        _optionsPortal.hide();
      }
    });
  }

  void _onToolOptionsTypeChanged() {
    if (_isToolPopover(toolOptionsType.value) && showColorOptions.value) {
      showColorOptions.value = false;
    }
    _syncPopover();
  }

  void _onShowColorOptionsChanged() {
    if (showColorOptions.value && _isToolPopover(toolOptionsType.value)) {
      toolOptionsType.value = ToolOptions.hide;
    }
    _syncPopover();
  }

  void _closePopovers() {
    // The selection bar isn't a popover, so leave it alone.
    if (_isToolPopover(toolOptionsType.value)) {
      toolOptionsType.value = ToolOptions.hide;
    }
    showColorOptions.value = false;
  }

  @override
  void initState() {
    _assignKeybindings();
    toolOptionsType.addListener(_onToolOptionsTypeChanged);
    showColorOptions.addListener(_onShowColorOptionsChanged);

    DynamicMaterialApp.addFullscreenListener(_setState);

    super.initState();
  }

  void _setState() => setState(() {});

  Keybinding? _ctrlF;
  Keybinding? _ctrlE;
  Keybinding? _ctrlC;
  Keybinding? _ctrlShiftS;
  Keybinding? _f11;
  Keybinding? _ctrlV;
  void _assignKeybindings() {
    _ctrlF = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyF),
    ], inclusive: true);
    _ctrlE = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyE),
    ], inclusive: true);
    _ctrlC = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyC),
    ], inclusive: true);
    _ctrlShiftS = Keybinding([
      KeyCode.ctrl,
      KeyCode.shift,
      KeyCode.from(LogicalKeyboardKey.keyS),
    ], inclusive: true);
    _f11 = Keybinding([KeyCode.from(LogicalKeyboardKey.f11)], inclusive: true);
    _ctrlV = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyV),
    ], inclusive: true);

    Keybinder.bind(_ctrlF!, widget.toggleFingerDrawing);
    Keybinder.bind(_ctrlE!, toggleEraser);
    Keybinder.bind(_ctrlC!, toggleColorOptions);
    Keybinder.bind(_ctrlShiftS!, toggleExportBar);
    Keybinder.bind(_f11!, toggleFullscreen);
    Keybinder.bind(_ctrlV!, widget.paste);
  }

  void _removeKeybindings() {
    if (_ctrlF != null) Keybinder.remove(_ctrlF!);
    if (_ctrlE != null) Keybinder.remove(_ctrlE!);
    if (_ctrlC != null) Keybinder.remove(_ctrlC!);
    if (_ctrlShiftS != null) Keybinder.remove(_ctrlShiftS!);
    if (_f11 != null) Keybinder.remove(_f11!);
    if (_ctrlV != null) Keybinder.remove(_ctrlV!);
  }

  void toggleEraser() {
    toolOptionsType.value = .hide;
    widget.setTool(Eraser()); // this toggles eraser
  }

  void toggleColorOptions() {
    showColorOptions.value = !showColorOptions.value;
  }

  void toggleExportBar() {
    showExportOptions.value = !showExportOptions.value;
  }

  void toggleFullscreen() async {
    DynamicMaterialApp.setFullscreen(
      !DynamicMaterialApp.isFullscreen,
      updateSystem: true,
    );
  }

  /// Nearest screen edge to [pos], used for toolbar edge-snapping.
  AxisDirection _nearestEdge(Offset pos) {
    final size = MediaQuery.sizeOf(context);
    var best = AxisDirection.down;
    var bestDistance = double.infinity;
    void consider(AxisDirection edge, double distance) {
      if (distance < bestDistance) {
        bestDistance = distance;
        best = edge;
      }
    }

    consider(AxisDirection.up, pos.dy);
    consider(AxisDirection.down, size.height - pos.dy);
    consider(AxisDirection.left, pos.dx);
    consider(AxisDirection.right, size.width - pos.dx);
    return best;
  }

  /// Material Symbols glyph used for the current pen in the toolbar.
  static IconData _penSymbol(Pen pen) {
    final icon = pen.icon;
    if (icon == Pen.ballpointPenIcon) return Symbols.draw;
    if (icon == ShapePen.shapePenIcon) return Symbols.shapes;
    return Symbols.ink_pen;
  }

  /// A toolbar glyph: outlined normally, filled while its tool is selected.
  Widget _toolIcon(IconData icon, {bool selected = false}) {
    return Icon(icon, fill: selected ? 1 : 0);
  }

  /// Subtle Samsung-style grip handle. Only this starts a drag —
  /// every tool button keeps its normal tap behavior. Uses Flutter's
  /// built-in Draggable so the floating preview is handled robustly.
  Widget _buildDragHandle(bool isToolbarVertical, ColorScheme colorScheme) {
    // Fixed ghost size, floating above the fingertip so it's visible.
    const ghostWidth = 300.0;
    const ghostHeight = 68.0;
    const liftAboveFinger = 90.0;

    Widget ghostBar() {
      return Container(
        width: ghostWidth,
        height: ghostHeight,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: .circular(24),
          border: Border.all(color: colorScheme.primary, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: .center,
          children: [
            for (int i = 0; i < 5; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: .circle,
                    color: colorScheme.primary.withValues(alpha: 0.25),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    Widget handlePill() {
      return Container(
        padding: const EdgeInsets.all(10),
        color: Colors.transparent,
        child: Container(
          width: isToolbarVertical ? 28 : 5,
          height: isToolbarVertical ? 5 : 28,
          decoration: BoxDecoration(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
            borderRadius: .circular(3),
          ),
        ),
      );
    }

    return Draggable<Object>(
      data: null,
      // Float the preview above the fingertip so it's visible, not hidden
      // under the finger. The returned offset is the grab point within the
      // feedback: feedback top-left = pointer - offset.
      dragAnchorStrategy: (draggable, context, position) =>
          const Offset(ghostWidth / 2, liftAboveFinger + ghostHeight / 2),
      feedback: Material(color: Colors.transparent, child: ghostBar()),
      childWhenDragging: Opacity(opacity: 0.4, child: handlePill()),
      onDragEnd: (details) {
        // details.offset is the feedback's top-left; recover the finger
        // position and snap to the nearest screen edge.
        final fingerPos =
            details.offset +
            const Offset(ghostWidth / 2, liftAboveFinger + ghostHeight / 2);
        stows.editorToolbarAlignment.value = _nearestEdge(fingerPos);
      },
      child: handlePill(),
    );
  }

  /// One of the three colors that can be picked straight from the toolbar.
  /// Tap to use it, long-press to replace it with the current color.
  Widget _quickColorButton(
    int index,
    Color? currentColor,
    bool invert,
    ColorScheme colorScheme,
    EdgeInsets padding,
  ) {
    final quickColors = stows.toolbarQuickColors.value;
    if (index >= quickColors.length) return const SizedBox.shrink();

    final color = Color(int.parse(quickColors[index]));
    final enabled = !widget.readOnly && currentColor != null;
    final isSelected =
        currentColor?.withAlpha(255).toARGB32() == color.toARGB32();
    const diameter = 30.0;

    // Same 48x48 footprint as [ToolbarIconButton] so the presets sit on the
    // same line, with the same spacing, as the other tools.
    return Padding(
      padding: padding,
      child: Tooltip(
        message: ColorBar.findColorName(color),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? () => widget.setColor(color) : null,
          onLongPress: enabled
              ? () {
                  final replaced = List<String>.of(quickColors);
                  replaced[index] = currentColor!
                      .withAlpha(255)
                      .toARGB32()
                      .toString();
                  stows.toolbarQuickColors.value = replaced;
                  setState(() {});
                }
              : null,
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: Container(
                width: diameter,
                height: diameter,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: AnimatedOpacity(
                  opacity: enabled ? 1 : 0.4,
                  duration: const Duration(milliseconds: 200),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color.withInversion(invert),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.onSurface.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color? _currentColorOf(Tool tool) => switch (tool) {
    final Pen pen => pen.color,
    final Select select => select.getDominantStrokeColor(),
    _ => null,
  };

  /// The popover that is currently open, or null.
  Widget? _buildPopover(BuildContext context, double width) {
    if (showColorOptions.value) {
      final brightness = Theme.brightnessOf(context);
      return ColorBar(
        width: width,
        setColor: widget.setColor,
        currentColor: _currentColorOf(widget.currentTool),
        invert: stows.editorAutoInvert.value && brightness == .dark,
      );
    }
    return switch (toolOptionsType.value) {
      ToolOptions.pen => PenModal(
        getTool: () => Pen.currentPen,
        setTool: widget.setTool,
        width: width,
      ),
      ToolOptions.highlighter => PenModal(
        getTool: () => Highlighter.currentHighlighter,
        setTool: widget.setTool,
        width: width,
      ),
      ToolOptions.pencil => PenModal(
        getTool: () => Pencil.currentPencil,
        setTool: widget.setTool,
        width: width,
      ),
      ToolOptions.eraser => EraserModal(width: width),
      _ => null,
    };
  }

  /// The tool options / color picker: a small popover attached to the
  /// toolbar bar, on the side facing the page.
  Widget _buildOptionsOverlay(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([toolOptionsType, showColorOptions]),
      builder: (context, _) {
        final width = min(
          PenModal.defaultWidth,
          MediaQuery.sizeOf(context).width - 16,
        );
        final popover = _buildPopover(context, width);
        if (popover == null) return const SizedBox.shrink();

        final (
          targetAnchor,
          followerAnchor,
          offset,
        ) = switch (stows.editorToolbarAlignment.value) {
          AxisDirection.down => (
            Alignment.topLeft,
            Alignment.bottomLeft,
            const Offset(8, -6),
          ),
          AxisDirection.up => (
            Alignment.bottomLeft,
            Alignment.topLeft,
            const Offset(8, 6),
          ),
          AxisDirection.left => (
            Alignment.topRight,
            Alignment.topLeft,
            const Offset(6, 8),
          ),
          AxisDirection.right => (
            Alignment.topLeft,
            Alignment.topRight,
            const Offset(-6, 8),
          ),
        };

        return Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _optionsLink,
            showWhenUnlinked: false,
            targetAnchor: targetAnchor,
            followerAnchor: followerAnchor,
            offset: offset,
            child: TapRegion(
              groupId: _optionsTapGroup,
              // Tapping the page closes the popover but still draws.
              onTapOutside: (_) => _closePopovers(),
              child: Material(
                type: MaterialType.transparency,
                child: popover,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    final brightness = Theme.brightnessOf(context);
    final invert = stows.editorAutoInvert.value && brightness == .dark;

    final alignment = stows.editorToolbarAlignment.value;
    final isToolbarVertical =
        alignment == AxisDirection.left || alignment == AxisDirection.right;
    final dividerSide = BorderSide(
      color: colorScheme.outlineVariant,
    );

    final buttonPadding = isToolbarVertical
        ? Toolbar._buttonPaddingVertical
        : Toolbar._buttonPaddingHorizontal;

    final currentColor = _currentColorOf(widget.currentTool);

    if (widget.currentTool == Select.currentSelect) {
      // Enable selection bar only when selection is done
      toolOptionsType.value = Select.currentSelect.doneSelecting
          ? .select
          : .hide;
    }

    // Every item that can appear in the toolbar. They are laid out below in
    // the order chosen in Settings > Customize toolbar ([ToolbarItem.visible]).
    // Undo, redo and fullscreen live in the editor's top bar; export is in
    // its 3-dot menu.
    final items = <ToolbarItem, List<Widget>>{
      ToolbarItem.pen: [
        ToolbarIconButton(
          tooltip: Pen.currentPen.name,
          selected: widget.currentTool == Pen.currentPen,
          enabled: !widget.readOnly,
          onPressed: () {
            if (widget.currentTool == Pen.currentPen) {
              if (toolOptionsType.value == .pen) {
                toolOptionsType.value = .hide;
              } else {
                toolOptionsType.value = .pen;
              }
            } else {
              toolOptionsType.value = .hide;
              widget.setTool(Pen.currentPen);
            }
          },
          padding: buttonPadding,
          child: _toolIcon(
            _penSymbol(Pen.currentPen),
            selected: widget.currentTool == Pen.currentPen,
          ),
        ),
      ],
      ToolbarItem.pencil: [
        ToolbarIconButton(
          tooltip: t.editor.pens.pencil,
          selected: widget.currentTool == Pencil.currentPencil,
          enabled: !widget.readOnly,
          onPressed: () {
            if (widget.currentTool == Pencil.currentPencil) {
              if (toolOptionsType.value == .pencil) {
                toolOptionsType.value = .hide;
              } else {
                toolOptionsType.value = .pencil;
              }
            } else {
              toolOptionsType.value = .hide;
              widget.setTool(Pencil.currentPencil);
            }
          },
          padding: buttonPadding,
          child: _toolIcon(
            Symbols.edit,
            selected: widget.currentTool == Pencil.currentPencil,
          ),
        ),
      ],
      ToolbarItem.highlighter: [
        ToolbarIconButton(
          tooltip: t.editor.pens.highlighter,
          selected: widget.currentTool == Highlighter.currentHighlighter,
          enabled: !widget.readOnly,
          onPressed: () {
            if (widget.currentTool == Highlighter.currentHighlighter) {
              if (toolOptionsType.value == .highlighter) {
                toolOptionsType.value = .hide;
              } else {
                toolOptionsType.value = .highlighter;
              }
            } else {
              toolOptionsType.value = .hide;
              widget.setTool(Highlighter.currentHighlighter);
            }
          },
          padding: buttonPadding,
          child: _toolIcon(
            Symbols.ink_highlighter,
            selected: widget.currentTool == Highlighter.currentHighlighter,
          ),
        ),
      ],
      ToolbarItem.quickColors: [
        for (var i = 0; i < 3; i++)
          _quickColorButton(
            i,
            currentColor,
            invert,
            colorScheme,
            buttonPadding,
          ),
      ],
      ToolbarItem.colorPalette: [
        ValueListenableBuilder(
          valueListenable: showColorOptions,
          builder: (context, showColorOptions, child) {
            return ToolbarIconButton(
              tooltip: t.editor.toolbar.toggleColors,
              selected: showColorOptions,
              enabled: !widget.readOnly,
              onPressed: toggleColorOptions,
              padding: buttonPadding,
              child: child!,
            );
          },
          child: currentColor == null
              ? const Icon(Symbols.palette)
              : Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: currentColor
                        .withInversion(invert)
                        .withValues(alpha: 1),
                    shape: .circle,
                    border: Border.all(color: colorScheme.primary, width: 2),
                  ),
                ),
        ),
      ],
      ToolbarItem.select: [
        ToolbarIconButton(
          tooltip: t.editor.toolbar.select,
          selected: widget.currentTool is Select,
          enabled: !widget.readOnly,
          onPressed: () {
            toolOptionsType.value = .hide;
            widget.setTool(Select.currentSelect);
          },
          padding: buttonPadding,
          child: _toolIcon(
            Symbols.lasso_select,
            selected: widget.currentTool is Select,
          ),
        ),
      ],
      ToolbarItem.laserPointer: [
        ToolbarIconButton(
          tooltip: t.editor.pens.laserPointer,
          selected: widget.currentTool == LaserPointer.currentLaserPointer,
          enabled: true, // even in read-only mode
          onPressed: () {
            toolOptionsType.value = .hide;
            widget.setTool(LaserPointer.currentLaserPointer);
          },
          padding: buttonPadding,
          child: _toolIcon(
            Symbols.stylus_laser_pointer,
            selected: widget.currentTool == LaserPointer.currentLaserPointer,
          ),
        ),
      ],
      ToolbarItem.eraser: [
        ToolbarIconButton(
          tooltip: t.editor.toolbar.toggleEraser,
          selected: widget.currentTool is Eraser,
          enabled: !widget.readOnly,
          onPressed: () {
            if (widget.currentTool is Eraser) {
              // already using the eraser: open / close its options
              toolOptionsType.value = toolOptionsType.value == .eraser
                  ? .hide
                  : .eraser;
            } else {
              toolOptionsType.value = .hide;
              widget.setTool(Eraser());
            }
          },
          padding: buttonPadding,
          child: _toolIcon(
            Symbols.ink_eraser,
            selected: widget.currentTool is Eraser,
          ),
        ),
      ],
      ToolbarItem.photo: [
        ToolbarIconButton(
          tooltip: t.editor.toolbar.photo,
          enabled: !widget.readOnly,
          onPressed: widget.pickPhoto,
          padding: buttonPadding,
          child: _toolIcon(Symbols.image),
        ),
      ],
      ToolbarItem.text: [
        ToolbarIconButton(
          tooltip: t.editor.toolbar.text,
          selected: widget.textEditing,
          enabled: !widget.readOnly,
          onPressed: widget.toggleTextEditing,
          padding: buttonPadding,
          child: _toolIcon(Symbols.text_fields, selected: widget.textEditing),
        ),
      ],
      ToolbarItem.fingerDrawing: [
        if (!stows.hideFingerDrawingToggle.value)
          ValueListenableBuilder(
            valueListenable: stows.editorFingerDrawing,
            builder: (context, value, child) {
              return ToolbarIconButton(
                tooltip: t.editor.toolbar.toggleFingerDrawing,
                selected: value,
                enabled: !widget.readOnly,
                onPressed: widget.toggleFingerDrawing,
                padding: buttonPadding,
                child: _toolIcon(Symbols.touch_app, selected: value),
              );
            },
          ),
      ],
      // There is no preset-stroke-width button in the toolbar (yet).
      ToolbarItem.quickWidths: const [],
    };

    final bars = <Widget>[
      ValueListenableBuilder(
        valueListenable: showExportOptions,
        builder: (context, showExportOptions, child) {
          return Collapsible(
            axis: isToolbarVertical
                ? CollapsibleAxis.horizontal
                : CollapsibleAxis.vertical,
            maintainState: true,
            collapsed: !showExportOptions,
            child: child!,
          );
        },
        child: ExportBar(
          axis: isToolbarVertical ? Axis.vertical : Axis.horizontal,
          toggleExportBar: toggleExportBar,
          exportAsSba: widget.exportAsSba,
          exportAsPdf: widget.exportAsPdf,
          exportAsPng: widget.exportAsPng,
        ),
      ),
      ValueListenableBuilder(
        valueListenable: toolOptionsType,
        builder: (context, toolOptionsType, _) {
          return Collapsible(
            axis: isToolbarVertical
                ? CollapsibleAxis.horizontal
                : CollapsibleAxis.vertical,
            maintainState: true,
            collapsed: toolOptionsType != ToolOptions.select,
            child: switch (toolOptionsType) {
              .select => SelectionBar(
                duplicateSelection: widget.duplicateSelection,
                deleteSelection: widget.deleteSelection,
              ),
              // pen, highlighter, pencil and eraser options are in the overlay
              _ => const SizedBox.square(dimension: SizePicker.smallLength),
            },
          );
        },
      ),
      ValueListenableBuilder(
        valueListenable: widget.quillFocus,
        builder: (context, quill, _) {
          final baseButtonStyle =
              IconButtonTheme.of(context).style ?? const ButtonStyle();

          final iconTheme = QuillIconTheme(
            iconButtonUnselectedData: IconButtonData(
              style: baseButtonStyle.copyWith(
                backgroundColor: WidgetStateProperty.all(Colors.transparent),
                foregroundColor: WidgetStateProperty.all(colorScheme.primary),
              ),
            ),
            iconButtonSelectedData: IconButtonData(
              style: baseButtonStyle.copyWith(
                backgroundColor: WidgetStateProperty.all(colorScheme.primary),
                foregroundColor: WidgetStateProperty.all(colorScheme.onPrimary),
              ),
            ),
          );
          return Collapsible(
            axis: isToolbarVertical
                ? CollapsibleAxis.horizontal
                : CollapsibleAxis.vertical,
            maintainState: false,
            collapsed: !widget.textEditing || quill == null,
            child: quill != null
                ? QuillSimpleToolbar(
                    controller: quill.controller,
                    config: QuillSimpleToolbarConfig(
                      axis: isToolbarVertical ? Axis.vertical : Axis.horizontal,
                      buttonOptions: QuillSimpleToolbarButtonOptions(
                        base: QuillToolbarBaseButtonOptions(
                          iconTheme: iconTheme,
                        ),
                      ),
                      // scrollable on Android and iOS
                      multiRowsDisplay: !Platform.isAndroid && !Platform.isIOS,
                      showUndo: false,
                      showRedo: false,
                      showFontSize: false,
                      showFontFamily: false,
                      showClearFormat: false,
                    ),
                  )
                : const SizedBox.shrink(),
          );
        },
      ),
      OverlayPortal(
        controller: _optionsPortal,
        overlayChildBuilder: _buildOptionsOverlay,
        child: CompositedTransformTarget(
          link: _optionsLink,
          child: TapRegion(
            groupId: _optionsTapGroup,
            child: Container(
              // Edge-to-edge bar: spans the whole side of the screen.
              width: isToolbarVertical ? null : double.infinity,
              height: isToolbarVertical ? double.infinity : null,
              padding: const .symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                border: switch (alignment) {
                  AxisDirection.up => Border(bottom: dividerSide),
                  AxisDirection.down => Border(top: dividerSide),
                  AxisDirection.left => Border(right: dividerSide),
                  AxisDirection.right => Border(left: dividerSide),
                },
              ),
              child: Wrap(
                direction: isToolbarVertical ? Axis.vertical : Axis.horizontal,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                children: [
                  _buildDragHandle(isToolbarVertical, colorScheme),
                  for (final item in ToolbarItem.visible) ...?items[item],
                ],
              ),
            ),
          ),
        ),
      ),
    ];

    return Flex(
      direction: isToolbarVertical ? Axis.horizontal : Axis.vertical,
      textDirection: switch (stows.editorToolbarAlignment.value) {
        AxisDirection.left => .rtl,
        AxisDirection.right => .ltr,
        _ => null,
      },
      verticalDirection: switch (stows.editorToolbarAlignment.value) {
        AxisDirection.down => VerticalDirection.down,
        AxisDirection.up => VerticalDirection.up,
        _ => VerticalDirection.down,
      },
      children: bars,
    );
  }

  @override
  void dispose() {
    toolOptionsType.removeListener(_onToolOptionsTypeChanged);
    showColorOptions.removeListener(_onShowColorOptionsChanged);
    DynamicMaterialApp.removeFullscreenListener(_setState);
    DynamicMaterialApp.setFullscreen(false, updateSystem: true);

    _removeKeybindings();
    super.dispose();
  }
}

enum ToolOptions { hide, pen, highlighter, pencil, eraser, select }
