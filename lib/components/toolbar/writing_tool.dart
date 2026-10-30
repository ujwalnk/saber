import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/marker.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/i18n/strings.g.dart';

/// The tools offered by the unified writing-tool selector.
enum WritingTool {
  inkPen('assets/images/tool_inkpen.png', 1, Symbols.ink_pen),
  ballpointPen('assets/images/tool_ballpoint.png', 1, Symbols.draw),
  pencil('assets/images/tool_pencil.png', 1, Symbols.edit),
  marker('assets/images/tool_marker.png', 1, Symbols.ink_marker),
  highlighter('assets/images/tool_highlighter.png', 1.44, Symbols.ink_highlighter);

  const WritingTool(this.asset, this.widthFactor, this.icon);

  final String asset;

  /// Relative width of the artwork (the highlighter image is wider).
  final double widthFactor;

  /// Icon used for the collapsed toolbar button.
  final IconData icon;

  String get label => switch (this) {
    inkPen => t.editor.pens.fountainPen,
    ballpointPen => t.editor.pens.ballpointPen,
    pencil => t.editor.pens.pencil,
    marker => 'Marker',
    highlighter => t.editor.pens.highlighter,
  };

  /// The tool instance to activate when this entry is picked.
  /// Reuses the existing per-tool state.
  Pen get instance => switch (this) {
    inkPen => Pen.fountainPen(),
    ballpointPen => Pen.ballpointPen(),
    pencil => Pencil.currentPencil,
    marker => Marker.currentMarker,
    highlighter => Highlighter.currentHighlighter,
  };

  /// Which entry [pen] belongs to, or null (e.g. for the shape pen).
  static WritingTool? of(Pen pen) {
    if (pen is Marker) return marker;
    if (pen is Highlighter) return highlighter;
    if (pen is Pencil) return pencil;
    if (pen is ShapePen) return null;
    return pen.icon == Pen.ballpointPenIcon ? ballpointPen : inkPen;
  }
}
