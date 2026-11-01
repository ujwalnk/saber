import 'dart:io';

import 'package:android_file_picker/android_file_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // The Android app already ships the permission_handler plugin, but the
  // Linux build doesn't have that package, so its channel is used directly
  // instead of importing it.
  static const _permissionsChannel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );

  /// permission_handler's numbering: 9 is "photos" (READ_MEDIA_IMAGES) and
  /// 15 is "storage" (READ_EXTERNAL_STORAGE, for Android 12 and older).
  static Future<void> _requestReadAccess() async {
    if (!Platform.isAndroid) return;
    try {
      final sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      await _permissionsChannel.invokeMethod('requestPermissions', [
        sdkInt >= 33 ? 9 : 15,
      ]);
    } catch (_) {
      // best effort: the user can still allow it in the system settings
    }
  }

  /// Opens this app's page in the system settings (Android only).
  static Future<void> openAppSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _permissionsChannel.invokeMethod('openAppSettings');
    } catch (_) {}
  }

  /// On Android the folder picker returns a `content://` "tree" address
  /// (e.g. `content://com.android.externalstorage.documents/tree/ABCD-1234%3AStickers`),
  /// which `dart:io` can't open. For folders on internal storage or an SD card
  /// this works out the ordinary path (`/storage/ABCD-1234/Stickers`).
  /// Returns null for locations that have no ordinary path.
  static String? _resolvePath(String stored) {
    if (!stored.startsWith('content://')) return stored;

    final uri = Uri.tryParse(stored);
    if (uri == null ||
        uri.authority != 'com.android.externalstorage.documents') {
      return null;
    }
    final segments = uri.pathSegments;
    final treeIndex = segments.indexOf('tree');
    if (treeIndex < 0 || treeIndex + 1 >= segments.length) return null;

    // e.g. "primary:Pictures/Stickers" or "ABCD-1234:Stickers"
    final documentId = segments[treeIndex + 1];
    final colon = documentId.indexOf(':');
    final volume = colon < 0 ? documentId : documentId.substring(0, colon);
    final relative = colon < 0 ? '' : documentId.substring(colon + 1);

    final root = volume == 'primary'
        ? '/storage/emulated/0'
        : '/storage/$volume';
    return relative.isEmpty ? root : '$root/$relative';
  }

  /// The sticker files in the folder, sorted by name.
  /// Throws if the folder can't be read.
  static Future<List<File>> list() async {
    final stored = stows.stickerDirectory.value;
    if (stored == null || stored.isEmpty) return const [];

    await _requestReadAccess();

    final path = _resolvePath(stored);
    if (path == null) {
      throw FileSystemException(
        "This kind of location can't be read. Choose a folder on the "
        'phone or on an SD card',
        stored,
      );
    }

    final directory = Directory(path);
    if (!directory.existsSync()) {
      throw FileSystemException(
        'The folder could not be opened. If it exists, allow the app to '
        'access photos / media in the system settings (App info > '
        'Permissions)',
        path,
      );
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
    setState(() {
      _stickers = StickerLibrary.list();
    });
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
              text: "Couldn't read the sticker folder.",
              details: '${stows.stickerDirectory.value}\n${snapshot.error}',
              onChooseFolder: _chooseFolder,
              onOpenSettings: Platform.isAndroid
                  ? StickerLibrary.openAppSettings
                  : null,
            );
          }
          final stickers = snapshot.data!;
          if (stickers.isEmpty) {
            return _Message(
              icon: Icons.emoji_emotions_outlined,
              text: stows.stickerDirectory.value == null
                  ? 'No sticker folder chosen yet.\n'
                        'Pick a folder with PNG, JPEG or GIF images.'
                  : 'No PNG, JPEG or GIF images were found in the sticker '
                        'folder.\nIf the folder does have images, allow '
                        '"Photos and videos" for this app (choose "Allow '
                        'all"), then come back.',
              onChooseFolder: _chooseFolder,
              onOpenSettings: Platform.isAndroid
                  ? StickerLibrary.openAppSettings
                  : null,
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
    this.onOpenSettings,
    this.details,
  });

  final IconData icon;
  final String text;

  /// Technical details, shown small, to help work out what went wrong.
  final String? details;
  final VoidCallback onChooseFolder;

  /// Opens the app's system settings, to allow access to photos.
  final VoidCallback? onOpenSettings;

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
            if (details != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                details!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onChooseFolder,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose folder'),
            ),
            if (onOpenSettings != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('App permissions'),
              ),
            ],
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
