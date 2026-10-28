import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/home/note_cover_colors.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';

class NoteColorButton extends StatelessWidget {
  const new({super.key, required this.selectedFiles});

  final List<String> selectedFiles;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      tooltip: 'Note color',
      onPressed: () {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return _NoteColorDialog(selectedFiles: selectedFiles);
          },
        );
      },
      icon: const Icon(Icons.palette_outlined),
    );
  }
}

class _NoteColorDialog extends StatelessWidget {
  const new({required this.selectedFiles});

  final List<String> selectedFiles;

  @override
  Widget build(BuildContext context) {
    // The color currently applied to all selected notes, if they agree.
    final currentHexes = {
      for (final path in selectedFiles) NoteCoverColors.of(path)?.toARGB32(),
    };
    final currentArgb = currentHexes.length == 1 ? currentHexes.single : null;

    return AdaptiveAlertDialog(
      title: const Text('Note color'),
      content: SizedBox(
        width: 280,
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            for (final entry in NoteCoverColors.palette)
              _ColorSwatch(
                color: entry.color,
                label: entry.label,
                selected:
                    entry.color?.toARGB32() == currentArgb ||
                    (entry.color == null && currentArgb == null),
                onTap: () {
                  NoteCoverColors.setAll(selectedFiles, entry.color);
                  Navigator.of(context).pop();
                  // Keep the selection: clearing it would collapse the
                  // footer buttons and make the note grid visibly jump.
                  // The user can tap away to deselect, or pick another color.
                },
              ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const new({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color? color;
  final String label;
  final bool selected;
  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.25),
              width: selected ? 3 : 1.5,
            ),
          ),
          child: color == null
              ? Icon(
                  Icons.format_color_reset,
                  color: colorScheme.onSurfaceVariant,
                  size: 22,
                )
              : selected
              ? const Icon(Icons.check, color: Colors.black54, size: 22)
              : null,
        ),
      ),
    );
  }
}
