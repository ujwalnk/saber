import 'package:flutter/material.dart';
import 'package:saber/components/toolbar/samsung_panel.dart';
import 'package:saber/i18n/strings.g.dart';

/// Samsung Notes-style selection bar: floating pill with text buttons.
class SelectionBar extends StatelessWidget {
  final VoidCallback duplicateSelection;
  final VoidCallback deleteSelection;

  const new({
    super.key,
    required this.duplicateSelection,
    required this.deleteSelection,
  });

  @override
  Widget build(BuildContext context) {
    return SamsungPanel(
      borderRadius: 14,
      padding: const .all(6),
      child: Row(
        mainAxisSize: .min,
        children: [
          _textButton(
            context,
            label: t.editor.selectionBar.duplicate,
            onPressed: duplicateSelection,
          ),
          _textButton(
            context,
            label: t.editor.selectionBar.delete,
            onPressed: deleteSelection,
          ),
        ],
      ),
    );
  }

  Widget _textButton(
    BuildContext context, {
    required String label,
    required VoidCallback onPressed,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: ColorScheme.of(context).onSurface,
        padding: const .symmetric(horizontal: 12, vertical: 9),
        shape: const RoundedRectangleBorder(
          borderRadius: .all(.circular(10)),
        ),
        textStyle: const TextStyle(fontSize: 13),
      ),
      child: Text(label),
    );
  }
}
