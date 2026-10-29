import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:saber/data/prefs.dart';

/// Everything that can appear in the editor toolbar.
///
/// Undo, redo, fullscreen and export live in the editor's top bar, so they
/// are not part of this list.
///
/// The order and visibility are user-configurable (Settings > Customize
/// toolbar) and stored in [Stows.toolbarItemOrder] / [Stows.toolbarItemsHidden].
enum ToolbarItem {
  pen('Pen', Symbols.ink_pen),
  pencil('Pencil', Symbols.edit),
  highlighter('Highlighter', Symbols.ink_highlighter),
  quickColors('Preset colors', Symbols.palette),
  quickWidths('Preset stroke widths', Symbols.line_weight),
  colorPalette('All colors', Symbols.colorize),
  select('Select', Symbols.lasso_select),
  laserPointer('Laser pointer', Symbols.stylus_laser_pointer),
  eraser('Eraser', Symbols.ink_eraser),
  photo('Photo', Symbols.image),
  text('Text', Symbols.text_fields),
  fingerDrawing('Finger drawing', Symbols.touch_app);

  const ToolbarItem(this.label, this.icon);

  final String label;
  final IconData icon;

  /// The default order: the declaration order above.
  static List<ToolbarItem> get defaultOrder => values;

  /// All items in the user's chosen order. Items missing from the stored
  /// order (e.g. added in an update) are appended at the end.
  static List<ToolbarItem> get ordered {
    final byName = {for (final item in values) item.name: item};
    final result = <ToolbarItem>[];
    for (final name in stows.toolbarItemOrder.value) {
      final item = byName.remove(name);
      if (item != null) result.add(item);
    }
    // anything the stored order didn't mention keeps its default position
    // relative to the other new items
    result.addAll(byName.values);
    return result;
  }

  /// The items that are shown in the toolbar, in order.
  static List<ToolbarItem> get visible {
    final hidden = stows.toolbarItemsHidden.value.toSet();
    return [
      for (final item in ordered)
        if (!hidden.contains(item.name)) item,
    ];
  }

  /// Saves [order] and [hidden] as the user's toolbar layout.
  static void save(List<ToolbarItem> order, Set<ToolbarItem> hidden) {
    stows.toolbarItemOrder.value = [for (final item in order) item.name];
    stows.toolbarItemsHidden.value = [
      for (final item in order)
        if (hidden.contains(item)) item.name,
    ];
  }

  /// Restores the default layout.
  static void reset() {
    stows.toolbarItemOrder.value = <String>[];
    stows.toolbarItemsHidden.value = <String>[];
  }
}
