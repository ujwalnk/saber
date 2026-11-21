import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/quill_styles.dart';

/// A movable text box on a page.
///
/// While [editing], the box shows a border and a handle bar: drag the
/// handle to move the box, drag the arrows to change its width, tap the
/// cross to delete it. Otherwise it's just text (and ignores touches).
///
/// Must be placed directly inside a [Stack] (it returns a [Positioned]).
class CanvasTextBox extends StatefulWidget {
  const new({
    super.key,
    required this.box,
    required this.pageSize,
    required this.editing,
    required this.invert,
    required this.lineHeight,
    required this.secondaryColor,
    required this.currentScale,
  });

  final TextBoxData box;
  final Size pageSize;

  /// Whether the box can currently be edited and moved.
  final bool editing;
  final bool invert;
  final int lineHeight;
  final Color secondaryColor;

  /// The zoom of the canvas, so the handle bar stays a usable size.
  final double currentScale;

  @override
  State<CanvasTextBox> createState() => _CanvasTextBoxState();
}

class _CanvasTextBoxState extends State<CanvasTextBox> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.box.quill.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(CanvasTextBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.box != widget.box) {
      oldWidget.box.quill.focusNode.removeListener(_onFocusChange);
      widget.box.quill.focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.box.quill.focusNode.removeListener(_onFocusChange);
    _scrollController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  /// Keeps at least part of the box on the page.
  Offset _clamp(Offset position, double width) {
    final maxX = max(0.0, widget.pageSize.width - width);
    final maxY = max(0.0, widget.pageSize.height - 60);
    return Offset(position.dx.clamp(0.0, maxX), position.dy.clamp(0.0, maxY));
  }

  void _drag(DragUpdateDetails details) {
    final box = widget.box;
    box.moveTo(_clamp(box.position + details.delta, box.width));
  }

  void _resize(DragUpdateDetails details) {
    final box = widget.box;
    final maxWidth = widget.pageSize.width - box.position.dx;
    box.resizeTo(
      (box.width + details.delta.dx).clamp(
        TextBoxData.minWidth,
        max(TextBoxData.minWidth, maxWidth),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.box,
      builder: (context, _) {
        final box = widget.box;
        final primary = Theme.of(context).colorScheme.primary;
        final focused = box.quill.focusNode.hasFocus;

        // keep the controls a comfortable size when the page is zoomed out
        final handleHeight = (40 / widget.currentScale).clamp(28.0, 140.0);
        final iconSize = handleHeight * 0.6;
        final borderScale = widget.currentScale.clamp(0.25, 4.0);

        final editor = QuillEditor(
          controller: box.quill.controller,
          focusNode: box.quill.focusNode,
          scrollController: _scrollController,
          config: QuillEditorConfig(
            customStyles: SaberQuillStyles.get(
              invert: widget.invert,
              secondary: widget.secondaryColor,
              lineHeight: widget.lineHeight,
            ),
            scrollable: false,
            autoFocus: false,
            expands: false,
            placeholder: widget.editing ? t.editor.quill.typeSomething : null,
            showCursor: true,
            keyboardAppearance: widget.invert ? .dark : .light,
            padding: .all(widget.lineHeight * 0.4),
            showCodeBlockLineNumbers: false,
          ),
        );

        return Positioned(
          left: box.position.dx,
          top: box.position.dy,
          width: box.width,
          child: IgnorePointer(
            ignoring: !widget.editing,
            child: DecoratedBox(
              decoration: widget.editing
                  ? BoxDecoration(
                      border: Border.all(
                        color: primary.withValues(alpha: focused ? 1 : 0.5),
                        width: (focused ? 2.0 : 1.0) / borderScale,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : const BoxDecoration(),
              child: Column(
                mainAxisSize: .min,
                crossAxisAlignment: .stretch,
                children: [
                  if (widget.editing)
                    SizedBox(
                      height: handleHeight,
                      child: ColoredBox(
                        color: primary.withValues(alpha: 0.12),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                behavior: .opaque,
                                onPanUpdate: _drag,
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.move,
                                  child: Center(
                                    child: Icon(
                                      Icons.drag_indicator,
                                      size: iconSize,
                                      color: primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            GestureDetector(
                              behavior: .opaque,
                              onPanUpdate: _resize,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeLeftRight,
                                child: SizedBox(
                                  width: handleHeight,
                                  height: handleHeight,
                                  child: Icon(
                                    Icons.swap_horiz,
                                    size: iconSize,
                                    color: primary,
                                  ),
                                ),
                              ),
                            ),
                            GestureDetector(
                              behavior: .opaque,
                              onTap: () => box.onDelete?.call(box),
                              child: SizedBox(
                                width: handleHeight,
                                height: handleHeight,
                                child: Icon(
                                  Icons.close,
                                  size: iconSize,
                                  color: primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: widget.lineHeight * 2.0,
                    ),
                    child: editor,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
