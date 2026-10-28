import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:go_router/go_router.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

class NewNoteButton extends StatefulWidget {
  const new({super.key, required this.cupertino, this.path});

  final bool cupertino;
  final String? path;

  @override
  State<NewNoteButton> createState() => _NewNoteButtonState();
}

class _NewNoteButtonState extends State<NewNoteButton> {
  final ValueNotifier<bool> isDialOpen = ValueNotifier(false);

  @override
  Widget build(BuildContext context) {
    const materialBorderRadius = BorderRadius.all(.circular(16));
    return SpeedDial(
      spacing: 3,
      mini: true,
      openCloseDial: isDialOpen,
      childPadding: const .all(5),
      spaceBetweenChildren: 4,
      switchLabelPosition: Directionality.of(context) == .rtl,
      shape: widget.cupertino
          ? const CircleBorder()
          : const RoundedRectangleBorder(borderRadius: materialBorderRadius),
      dialRoot: (context, open, toggleChildren) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Tooltip(
          message: t.home.tooltips.newNote,
          child: SizedBox(
            height: 62,
            width: 62,
            child: Material(
              shape: const CircleBorder(),
              color: isDark ? const Color(0xFF333336) : Colors.white,
              elevation: 6,
              shadowColor: Colors.black54,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: toggleChildren,
                child: const Center(
                  child: Icon(
                    Icons.add,
                    color: Color(0xFFFF6B35),
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      children: [
        SpeedDialChild(
          child: const Icon(Icons.create),
          label: t.home.create.newNote,
          onTap: () async {
            if (widget.path == null) {
              context.push(RoutePaths.edit);
            } else {
              final newFilePath = await FileManager.newFilePath(
                '${widget.path}/',
              );
              if (!context.mounted) return;
              context.push(RoutePaths.editFilePath(newFilePath));
            }
          },
        ),
        SpeedDialChild(
          child: const Icon(Icons.note_add),
          label: t.home.create.importNote,
          onTap: () async {
            final file = await FilePicker.pickFile(type: FileType.any);
            if (file == null) return;

            final filePath = file.path;
            final fileName = file.name;
            if (filePath == null) return;

            if (filePath.toLowerCase().endsWith('.sbn') ||
                filePath.toLowerCase().endsWith('.sbn2') ||
                filePath.toLowerCase().endsWith('.sba')) {
              final path = await FileManager.importFile(
                filePath,
                '${widget.path ?? ''}/',
              );
              if (path == null) return;
              if (!context.mounted) return;

              context.push(RoutePaths.editFilePath(path));
            } else if (filePath.toLowerCase().endsWith('.pdf')) {
              if (!Editor.canRasterPdf) return;
              if (!mounted) return;

              final fileNameWithoutExtension = fileName.substring(
                0,
                fileName.length - '.pdf'.length,
              );
              final sbnFilePath =
                  await FileManager.suffixFilePathToMakeItUnique(
                    '${widget.path ?? ''}/$fileNameWithoutExtension',
                  );
              if (!context.mounted) return;

              context.push(RoutePaths.editImportPdf(sbnFilePath, filePath));
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(t.home.invalidFormat)));
              }
              throw 'Invalid file type';
            }
          },
        ),
      ],
    );
  }
}
