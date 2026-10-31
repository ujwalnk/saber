import 'dart:io';

import 'package:android_file_picker/android_file_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saber/data/prefs.dart';

/// Finds the stickers in the folder chosen in Settings.
abstract final class StickerLibrary {
  static const extensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp'};

  /// Lets the user choose the sticker folder and remembers it.
  /// Returns whether a folder was chosen.
  static Future<bool> pickDirectory() async {
    final directory = await FilePicker.getDirectoryPath(
      dialogTitle: 'Sticker folder',
      initialDirectory: stows.stickerDirectory.value,
      androidOptions: defaultTargetPlatform == .android
          ? const FilePickerAndroidOptions(
              safOptions: .new(
                grant: .lifetime,
                accessMode: .readOnly,
                persistGrant: true,
              ),
            )
          : const .new(),
    );
    if (directory == null) return false;
    stows.stickerDirectory.value = directory;
    return true;
  }

  /// The sticker files in the folder, sorted by name.
  /// Throws if the folder can't be read.
  static Future<List<File>> list() async {
    final path = stows.stickerDirectory.value;
    if (path == null || path.isEmpty) return const [];

    final directory = Directory(path);
    if (!directory.existsSync()) {
      throw FileSystemException('The sticker folder does not exist', path);
    }

    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.toLowerCase();
      final dot = name.lastIndexOf('.');
      if (dot < 0 || !extensions.contains(name.substring(dot))) continue;
      files.add(entity);
    }
    files.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    return files;
  }
}

/// A full-screen page to pick a sticker from the sticker folder.
/// Pops with the chosen [File], or null if the user backed out.
class StickerPicker extends StatefulWidget {
  const StickerPicker({super.key});

  static Future<File?> show(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<File>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => const StickerPicker(),
      ),
    );
  }

  @override
  State<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<StickerPicker> {
  late Future<List<File>> _stickers = StickerLibrary.list();

  Future<void> _chooseFolder() async {
    if (!await StickerLibrary.pickDirectory()) return;
    if (!mounted) return;
    setState(() => _stickers = StickerLibrary.list());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stickers'),
        actions: [
          IconButton(
            tooltip: 'Choose sticker folder',
            icon: const Icon(Icons.folder_open),
            onPressed: _chooseFolder,
          ),
        ],
      ),
      body: FutureBuilder<List<File>>(
        future: _stickers,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _Message(
              icon: Icons.error_outline,
              text:
                  "Couldn't read the sticker folder.\n"
                  'Choose it again to give the app access to it.',
              onChooseFolder: _chooseFolder,
            );
          }
          final stickers = snapshot.data!;
          if (stickers.isEmpty) {
            return _Message(
              icon: Icons.emoji_emotions_outlined,
              text: stows.stickerDirectory.value == null
                  ? 'No sticker folder chosen yet.\n'
                        'Pick a folder with PNG, JPEG or GIF images.'
                  : 'There are no PNG, JPEG or GIF images in the sticker '
                        'folder.',
              onChooseFolder: _chooseFolder,
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 150,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: stickers.length,
            itemBuilder: (context, index) {
              final file = stickers[index];
              return Material(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => Navigator.of(context).pop(file),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _CheckerboardPainter(
                          colorScheme.surfaceContainerHigh,
                          colorScheme.surfaceContainerLow,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Image.file(
                          file,
                          fit: BoxFit.contain,
                          cacheWidth: 320,
                          gaplessPlayback: true,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.onChooseFolder,
  });

  final IconData icon;
  final String text;
  final VoidCallback onChooseFolder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onChooseFolder,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose folder'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows that a sticker's transparent areas are transparent.
class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter(this.a, this.b);

  final Color a, b;

  static const _cell = 12.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paintA = Paint()..color = a;
    final paintB = Paint()..color = b;
    for (var y = 0; y * _cell < size.height; y++) {
      for (var x = 0; x * _cell < size.width; x++) {
        canvas.drawRect(
          Rect.fromLTWH(x * _cell, y * _cell, _cell, _cell),
          (x + y).isEven ? paintA : paintB,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter oldDelegate) =>
      oldDelegate.a != a || oldDelegate.b != b;
}
