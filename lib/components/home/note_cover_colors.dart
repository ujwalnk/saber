import 'package:flutter/material.dart';
import 'package:saber/data/prefs.dart';

/// Samsung Notes-style cover colors for notes in the library.
///
/// Colors are stored in [stows.noteColors] as ARGB hex strings,
/// keyed by note file path (without extension).
class NoteCoverColors {
  /// The palette shown in the color picker.
  /// A null color represents the default (no color) option.
  static const List<({Color? color, String label})> palette = [
    (color: null, label: 'Default'),
    (color: Color(0xFFFFF9C4), label: 'Yellow'),
    (color: Color(0xFFC8E6C9), label: 'Green'),
    (color: Color(0xFFB2DFDB), label: 'Mint'),
    (color: Color(0xFFB3E5FC), label: 'Sky'),
    (color: Color(0xFFBBDEFB), label: 'Blue'),
    (color: Color(0xFFD1C4E9), label: 'Purple'),
    (color: Color(0xFFF8BBD0), label: 'Pink'),
    (color: Color(0xFFFFE0B2), label: 'Orange'),
  ];

  /// Serializes [color] to an ARGB hex string like '#FFFFF9C4'.
  static String toHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }

  /// Parses an ARGB hex string back to a [Color].
  /// Returns null if [hex] is null or malformed.
  static Color? fromHex(String? hex) {
    if (hex == null) return null;
    try {
      var cleaned = hex.trim();
      if (cleaned.startsWith('#')) cleaned = cleaned.substring(1);
      if (cleaned.length == 6) cleaned = 'FF$cleaned';
      if (cleaned.length != 8) return null;
      return Color(int.parse(cleaned, radix: 16));
    } catch (_) {
      return null;
    }
  }

  /// The stored cover color for [notePath] (without extension),
  /// or null if the note uses the default color.
  /// Stale or malformed entries are ignored.
  static Color? of(String notePath) {
    return fromHex(stows.noteColors.value[notePath]);
  }

  /// Sets the cover color for [notePath] (without extension).
  /// A null [color] clears the note's color.
  static void set(String notePath, Color? color) {
    final colors = Map<String, String>.from(stows.noteColors.value);
    if (color == null) {
      colors.remove(notePath);
    } else {
      colors[notePath] = toHex(color);
    }
    stows.noteColors.value = colors;
  }

  /// Sets the same cover color for multiple notes at once.
  static void setAll(Iterable<String> notePaths, Color? color) {
    final colors = Map<String, String>.from(stows.noteColors.value);
    for (final notePath in notePaths) {
      if (color == null) {
        colors.remove(notePath);
      } else {
        colors[notePath] = toHex(color);
      }
    }
    stows.noteColors.value = colors;
  }
}
