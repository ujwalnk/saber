import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_fountain_nib.dart';
import 'package:saber/components/toolbar/writing_tool.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/marker.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:sbn/tool_id.dart';

/// A named, saved pen: which tool it is plus its colour, size/stroke
/// options and (for the ink pen) nib settings. These are the pens listed
/// under "Favourites" in the pen popup.
class PenPreset {
  const new({
    required this.id,
    required this.name,
    required this.tool,
    required this.color,
    required this.options,
    this.nib,
  });

  final String id;
  final String name;

  /// A [WritingTool] name, or [shapePenKey].
  final String tool;
  static const shapePenKey = 'shapePen';

  /// ARGB colour (includes the opacity).
  final int color;

  /// [StrokeOptions] as JSON (includes the size).
  final Map<String, dynamic> options;

  /// [NibSettings] as JSON; only for the fountain pen.
  final Map<String, dynamic>? nib;

  PenPreset copyWith({String? name}) => PenPreset(
    id: id,
    name: name ?? this.name,
    tool: tool,
    color: color,
    options: options,
    nib: nib,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tool': tool,
    'color': color,
    'options': options,
    if (nib != null) 'nib': nib,
  };

  static PenPreset? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final tool = json['tool'];
    final color = json['color'];
    final options = json['options'];
    if (id is! String ||
        name is! String ||
        tool is! String ||
        color is! int ||
        options is! Map) {
      return null;
    }
    return PenPreset(
      id: id,
      name: name,
      tool: tool,
      color: color,
      options: Map<String, dynamic>.from(options),
      nib: json['nib'] is Map
          ? Map<String, dynamic>.from(json['nib'] as Map)
          : null,
    );
  }

  // --- Storage ------------------------------------------------------------

  static List<PenPreset> loadAll() => [
    for (final raw in stows.penPresets.value)
      ?_tryParse(raw),
  ];

  static PenPreset? _tryParse(String raw) {
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static void saveAll(List<PenPreset> presets) {
    stows.penPresets.value = [
      for (final preset in presets) jsonEncode(preset.toJson()),
    ];
  }

  // --- Capturing and applying ---------------------------------------------

  static String _toolKeyOf(Pen pen) =>
      pen is ShapePen ? shapePenKey : (WritingTool.of(pen) ?? WritingTool.inkPen).name;

  static bool _hasNib(Pen pen) =>
      pen is! ShapePen &&
      WritingTool.of(pen) == WritingTool.inkPen &&
      pen.toolId == ToolId.fountainPen;

  /// A preset holding [pen]'s current settings.
  static PenPreset capture(Pen pen, String name) => PenPreset(
    id: DateTime.now().microsecondsSinceEpoch.toString(),
    name: name,
    tool: _toolKeyOf(pen),
    color: pen.color.toARGB32(),
    options: pen.options.toJson(),
    nib: _hasNib(pen) ? stows.fountainNibSettings.value.toJson() : null,
  );

  /// Whether [pen] currently has exactly this preset's settings.
  bool matches(Pen pen) =>
      _toolKeyOf(pen) == tool &&
      pen.color.toARGB32() == color &&
      jsonEncode(pen.options.toJson()) == jsonEncode(options) &&
      (!_hasNib(pen) ||
          nib == null ||
          jsonEncode(stows.fountainNibSettings.value.toJson()) ==
              jsonEncode(nib));

  /// A readable name of the tool, e.g. "Marker".
  String get toolLabel => tool == shapePenKey
      ? 'Shape pen'
      : WritingTool.values.firstWhere((t) => t.name == tool).label;

  double get size =>
      StrokeOptions.fromJson(Map<String, dynamic>.from(options)).size;

  /// Makes this preset the active settings of its tool and returns a pen
  /// to switch to. The settings are saved like any other pen change.
  Pen toPen() {
    final opts = StrokeOptions.fromJson(Map<String, dynamic>.from(options));
    final pen = switch (tool) {
      shapePenKey => () {
        stows.lastShapePenOptions.value = opts;
        stows.lastShapePenColor.value = color;
        return ShapePen();
      }(),
      'ballpointPen' => () {
        stows.lastBallpointPenOptions.value = opts;
        stows.lastBallpointPenColor.value = color;
        return Pen.ballpointPen();
      }(),
      'pencil' => () {
        stows.lastPencilOptions.value = opts;
        stows.lastPencilColor.value = color;
        return Pencil();
      }(),
      'highlighter' => () {
        stows.lastHighlighterOptions.value = opts;
        stows.lastHighlighterColor.value = color;
        return Highlighter();
      }(),
      'marker' => Marker()..options = opts,
      _ => () {
        stows.lastFountainPenOptions.value = opts;
        stows.lastFountainPenColor.value = color;
        if (nib != null) {
          stows.fountainNibSettings.value = NibSettings.fromJson(nib!);
        }
        return Pen.fountainPen();
      }(),
    };
    pen.color = Color(color);
    return pen;
  }
}
