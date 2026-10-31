import 'package:flutter/material.dart';
import 'package:saber/components/toolbar/samsung_panel.dart';
import 'package:saber/i18n/strings.g.dart';

/// A floating menu for the current lasso selection. It sits just above (or,
/// if there's no room, below) the selection instead of in the toolbar.
///
/// Place this in a [Stack] that fills the canvas area and pass the selection's
/// bounds in that stack's coordinate space as [selectionRect].
class SelectionPopup extends StatelessWidget {
  const SelectionPopup({
    super.key,
    required this.selectionRect,
    required this.duplicateSelection,
    required this.copySelection,
    required this.deleteSelection,
    this.moveForward,
    this.moveBackward,
  });

  /// The selection's bounds, relative to the enclosing stack.
  final Rect selectionRect;

  final VoidCallback duplicateSelection;
  final VoidCallback copySelection;
  final VoidCallback deleteSelection;

  /// Move the selected images one layer up / down. Only shown when given
  /// (i.e. when the selection contains images).
  final VoidCallback? moveForward;
  final VoidCallback? moveBackward;

  static const double gap = 12;

  /// Space for the selection's rotate handle when the popup is above it.
  static const double gapAbove = 66;
  static const double edgeMargin = 8;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    return CustomSingleChildLayout(
      delegate: _SelectionPopupLayoutDelegate(selectionRect),
      child: SamsungPanel(
        borderRadius: 14,
        padding: const .all(6),
        child: Row(
          mainAxisSize: .min,
          children: [
            if (moveBackward != null)
              _textButton(context, label: 'Backward', onPressed: moveBackward!),
            if (moveForward != null)
              _textButton(context, label: 'Forward', onPressed: moveForward!),
            _textButton(
              context,
              label: t.editor.selectionBar.duplicate,
              onPressed: duplicateSelection,
            ),
            _textButton(
              context,
              label: t.editor.selectionBar.copy,
              onPressed: copySelection,
            ),
            _textButton(
              context,
              label: t.editor.selectionBar.delete,
              onPressed: deleteSelection,
              color: colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }

  Widget _textButton(
    BuildContext context, {
    required String label,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color ?? ColorScheme.of(context).onSurface,
        padding: const .symmetric(horizontal: 12, vertical: 9),
        minimumSize: .zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(borderRadius: .all(.circular(10))),
        textStyle: const TextStyle(fontSize: 13),
      ),
      child: Text(label),
    );
  }
}

class _SelectionPopupLayoutDelegate extends SingleChildLayoutDelegate {
  const _SelectionPopupLayoutDelegate(this.selectionRect);

  final Rect selectionRect;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return constraints.loosen();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    const gap = SelectionPopup.gap;
    const margin = SelectionPopup.edgeMargin;

    // Centered on the selection, but never off the sides.
    final maxX = size.width - childSize.width - margin;
    final x = (selectionRect.center.dx - childSize.width / 2)
        .clamp(margin, maxX < margin ? margin : maxX)
        .toDouble();

    final above =
        selectionRect.top - SelectionPopup.gapAbove - childSize.height;
    final below = selectionRect.bottom + gap;

    double y;
    if (above >= margin) {
      y = above;
    } else if (below + childSize.height <= size.height - margin) {
      y = below;
    } else {
      // The selection fills the screen: float inside it, near the top.
      y = margin + gap;
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_SelectionPopupLayoutDelegate oldDelegate) {
    return oldDelegate.selectionRect != selectionRect;
  }
}
