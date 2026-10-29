import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/components/toolbar/color_option.dart';
import 'package:saber/components/toolbar/samsung_panel.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/i18n/strings.g.dart';

typedef NamedColor = ({String name, Color color});

class ColorBar extends StatefulWidget {
  const new({
    super.key,
    required this.width,
    required this.setColor,
    required this.currentColor,
    required this.invert,
  });

  /// Width of the popup panel.
  final double width;
  final ValueChanged<Color> setColor;
  final Color? currentColor;
  final bool invert;

  static List<NamedColor> get colorPresets =>
      stows.preferGreyscale.value ? greyScaleColorOptions : normalColorOptions;
  static final List<NamedColor> normalColorOptions = [
    (name: t.editor.colors.black, color: Colors.black),
    (name: t.editor.colors.red, color: Colors.red),
    (name: t.editor.colors.orange, color: Colors.orange),
    (name: t.editor.colors.yellow, color: Colors.yellow),
    (name: t.editor.colors.green, color: Colors.green),
    (name: t.editor.colors.cyan, color: Colors.cyan),
    (name: t.editor.colors.blue, color: Colors.blue),
    (name: t.editor.colors.purple, color: Colors.purple),
    (name: t.editor.colors.pink, color: Colors.pink),
    (name: t.editor.colors.white, color: Colors.white),
    ..._pastelColorOptions,
  ];
  static final List<NamedColor> _pastelColorOptions = [
    (
      name: t.editor.colors.pastelRed,
      color: const Color.fromRGBO(255, 173, 173, 1),
    ),
    (
      name: t.editor.colors.pastelOrange,
      color: const Color.fromRGBO(255, 214, 165, 1),
    ),
    (
      name: t.editor.colors.pastelYellow,
      color: const Color.fromRGBO(253, 255, 182, 1),
    ),
    (
      name: t.editor.colors.pastelGreen,
      color: const Color.fromRGBO(202, 255, 191, 1),
    ),
    (
      name: t.editor.colors.pastelCyan,
      color: const Color.fromRGBO(155, 246, 255, 1),
    ),
    (
      name: t.editor.colors.pastelBlue,
      color: const Color.fromRGBO(160, 196, 255, 1),
    ),
    (
      name: t.editor.colors.pastelPurple,
      color: const Color.fromRGBO(189, 178, 255, 1),
    ),
    (
      name: t.editor.colors.pastelPink,
      color: const Color.fromRGBO(255, 198, 255, 1),
    ),
  ];
  static final List<NamedColor> greyScaleColorOptions = [
    (name: t.editor.colors.black, color: Colors.black),
    (name: t.editor.colors.darkGrey, color: Colors.grey[800] ?? Colors.black54),
    (name: t.editor.colors.grey, color: Colors.grey),
    (
      name: t.editor.colors.lightGrey,
      color: Colors.grey[200] ?? Colors.black12,
    ),
    (name: t.editor.colors.white, color: Colors.white),
  ];
  static final List<NamedColor> _allColors = [
    ...normalColorOptions,
    ...greyScaleColorOptions,
  ];
  static String findColorName(Color searchColor) {
    for (final namedColor in _allColors) {
      if (namedColor.color == searchColor) {
        return namedColor.name;
      }
    }
    return describeColor(searchColor);
  }

  @visibleForTesting
  static String describeColor(Color color) {
    final hsl = HSLColor.fromColor(color);

    final String hueName;
    if (hsl.saturation < 0.1 || hsl.lightness < 0.05 || hsl.lightness > 0.95) {
      hueName = t.editor.colors.grey.toLowerCase();
    } else {
      hueName = switch (hsl.hue) {
        < 10 => t.editor.colors.red.toLowerCase(),
        < 35 => t.editor.colors.orange.toLowerCase(),
        < 70 => t.editor.colors.yellow.toLowerCase(),
        < 150 => t.editor.colors.green.toLowerCase(),
        < 200 => t.editor.colors.cyan.toLowerCase(),
        < 250 => t.editor.colors.blue.toLowerCase(),
        < 285 => t.editor.colors.purple.toLowerCase(),
        < 340 => t.editor.colors.pink.toLowerCase(),
        _ => t.editor.colors.red.toLowerCase(),
      };
    }

    final lightnessName = switch (hsl.lightness) {
      < 0.35 => t.editor.colors.dark,
      < 0.65 => null,
      _ => t.editor.colors.light,
    };

    if (lightnessName == null) {
      return t.editor.colors.customHue(h: hueName);
    } else {
      return t.editor.colors.customBrightnessHue(b: lightnessName, h: hueName);
    }
  }

  /// Returns whether the color is now pinned.
  static bool toggleColorPinned(String colorString) {
    if (stows.pinnedColors.value.contains(colorString)) {
      stows.pinnedColors.value.remove(colorString);
      stows.recentColorsChronological.value.remove(colorString);
      stows.recentColorsPositioned.value.remove(colorString);
      if (stows.recentColorsChronological.value.length >=
          stows.recentColorsLength.value) {
        // if full, replace oldest
        final oldestColor = stows.recentColorsChronological.value.removeAt(0);
        stows.recentColorsChronological.value.add(colorString);
        final int oldestColorPosition = stows.recentColorsPositioned.value
            .indexOf(oldestColor);
        stows.recentColorsPositioned.value[oldestColorPosition] = colorString;
      } else {
        // not full, add to end
        stows.recentColorsChronological.value.add(colorString);
        stows.recentColorsPositioned.value.insert(0, colorString);
      }
      return false;
    } else {
      // add to pinned and remove from recent colors
      stows.pinnedColors.value.add(colorString);
      stows.recentColorsChronological.value.remove(colorString);
      stows.recentColorsPositioned.value.remove(colorString);
      return true;
    }
  }

  @override
  State<ColorBar> createState() => _ColorBarState();
}

class _ColorBarState extends State<ColorBar> {
  static var pickedColor = const Color.fromRGBO(255, 0, 0, 1);

  bool _isSelected(Color color) =>
      widget.currentColor?.withAlpha(255).toARGB32() == color.toARGB32();

  /// One round color swatch. A null [color] is an empty placeholder slot.
  Widget _swatch(
    ColorScheme colorScheme, {
    required Color? color,
    required String? tooltip,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return ColorOption(
      isSelected: color != null && _isSelected(color),
      enabled: widget.currentColor != null,
      onTap: onTap,
      onLongPress: onLongPress,
      tooltip: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color?.withInversion(widget.invert) ?? Colors.transparent,
          shape: .circle,
          border: Border.all(
            color: colorScheme.onSurface.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
    );
  }

  /// A row of swatches that wraps onto more lines, led by a small icon.
  Widget _section(IconData icon, List<Widget> children) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: ColorOption.diameter,
          child: Center(child: ColorOptionSeparatorIcon(icon: icon)),
        ),
        Expanded(child: Wrap(runSpacing: 4, children: children)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    Widget savedColor(String colorString) {
      final color = Color(int.parse(colorString));
      return _swatch(
        colorScheme,
        color: color,
        tooltip: ColorBar.findColorName(color),
        onTap: () => widget.setColor(color),
        onLongPress: () =>
            setState(() => ColorBar.toggleColorPinned(colorString)),
      );
    }

    final sections = <Widget>[
      // pinned colors
      if (stows.pinnedColors.value.isNotEmpty)
        _section(Icons.pin_drop, [
          for (final colorString in stows.pinnedColors.value)
            savedColor(colorString),
        ]),

      // recent colors, with placeholders up to `recentColorsLength`
      _section(Icons.history, [
        for (final colorString in stows.recentColorsPositioned.value.reversed)
          savedColor(colorString),
        for (
          int i = 0;
          i <
              stows.recentColorsLength.value -
                  stows.recentColorsPositioned.value.length;
          ++i
        )
          _swatch(colorScheme, color: null, tooltip: null),
      ]),

      // custom color picker, then the presets
      _section(Icons.palette, [
        ColorOption(
          isSelected: _isSelected(pickedColor),
          enabled: true,
          onTap: () => openColorPicker(context),
          tooltip: t.editor.colors.colorPicker,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.transparent,
              shape: .circle,
            ),
            child: Center(child: FaIcon(FontAwesomeIcons.droplet, size: 16)),
          ),
        ),
        for (final namedColor in ColorBar.colorPresets)
          _swatch(
            colorScheme,
            color: namedColor.color,
            tooltip: namedColor.name,
            onTap: () => widget.setColor(namedColor.color),
          ),
      ]),
    ];

    return SizedBox(
      width: widget.width,
      child: SamsungPanel(
        padding: const .all(10),
        borderRadius: 16,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.5,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  sections[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void openColorPicker(BuildContext context) async {
    // This popup closes as soon as the dialog is tapped, so don't read from
    // `widget` after the await.
    final setColor = widget.setColor;
    final invert = widget.invert;

    final bool? confirmChange = await showDialog(
      context: context,
      builder: (BuildContext context) => _colorPickerDialog(context),
    );
    if (confirmChange ?? false) {
      setColor(pickedColor.withInversion(invert));
    }
  }

  Widget _colorPickerDialog(BuildContext context) => AdaptiveAlertDialog(
    title: Text(t.settings.accentColorPicker.pickAColor),
    content: SingleChildScrollView(
      child: ColorPicker(
        color: pickedColor,
        pickersEnabled: const {ColorPickerType.wheel: true},
        onColorChanged: (Color color) {
          pickedColor = color;
        },
      ),
    ),
    actions: [
      CupertinoDialogAction(
        child: Text(MaterialLocalizations.of(context).saveButtonLabel),
        onPressed: () {
          Navigator.of(context).pop(true);
        },
      ),
    ],
  );
}
