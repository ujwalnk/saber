import 'package:flutter/material.dart';
import 'package:saber/components/toolbar/toolbar_items.dart';

/// Lets the user reorder the editor toolbar's items and remove the ones
/// they don't need. Changes are saved immediately.
class ToolbarCustomizeDialog extends StatefulWidget {
  const ToolbarCustomizeDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const ToolbarCustomizeDialog(),
    );
  }

  @override
  State<ToolbarCustomizeDialog> createState() => _ToolbarCustomizeDialogState();
}

class _ToolbarCustomizeDialogState extends State<ToolbarCustomizeDialog> {
  late List<ToolbarItem> _order = ToolbarItem.ordered;
  late Set<ToolbarItem> _hidden = {
    for (final item in ToolbarItem.values)
      if (!ToolbarItem.visible.contains(item)) item,
  };

  void _save() => ToolbarItem.save(_order, _hidden);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    return AlertDialog(
      title: const Text('Customize toolbar'),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Drag to reorder. Switch off the tools you don\'t need.',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ReorderableListView(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = _order.removeAt(oldIndex);
                    _order.insert(newIndex, item);
                  });
                  _save();
                },
                children: [
                  for (var i = 0; i < _order.length; i++)
                    _row(context, i, _order[i]),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            ToolbarItem.reset();
            setState(() {
              _order = ToolbarItem.ordered;
              _hidden = {};
            });
          },
          child: const Text('Reset'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, int index, ToolbarItem item) {
    final visible = !_hidden.contains(item);
    final colorScheme = ColorScheme.of(context);
    return ListTile(
      key: ValueKey(item),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: ReorderableDragStartListener(
        index: index,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.drag_indicator),
        ),
      ),
      title: Row(
        children: [
          Icon(
            item.icon,
            size: 22,
            color: visible
                ? colorScheme.onSurface
                : colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.label,
              style: TextStyle(
                color: visible
                    ? colorScheme.onSurface
                    : colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
      trailing: Switch(
        value: visible,
        onChanged: (value) {
          setState(() {
            if (value) {
              _hidden.remove(item);
            } else {
              _hidden.add(item);
            }
          });
          _save();
        },
      ),
    );
  }
}
