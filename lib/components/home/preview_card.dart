import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/canvas/invert_widget.dart';
import 'package:saber/components/home/note_cover_colors.dart';
import 'package:saber/components/home/sync_indicator.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/is_this_a_test.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/editor/editor.dart';

class PreviewCard extends StatefulWidget {
  new({
    required this.filePath,
    required this.toggleSelection,
    required this.selected,
    required this.isAnythingSelected,
  }) : super(key: ValueKey('PreviewCard$filePath'));

  final String filePath;
  final bool selected;
  final bool isAnythingSelected;
  final void Function(String, bool) toggleSelection;

  @override
  State<PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends State<PreviewCard> {
  final expanded = ValueNotifier(false);
  final thumbnail = _ThumbnailState();
  var _dateStr = '';

  void _updateDateStr() {
    _dateStr = DateFormat(
      'MMM d, yyyy',
    ).format(FileManager.lastModified('${widget.filePath}${Editor.extension}'));
  }

  @override
  void initState() {
    fileWriteSubscription = FileManager.fileWriteStream.stream.listen(
      fileWriteListener,
    );

    expanded.value = widget.selected;
    super.initState();
  }

  @override
  void didUpdateWidget(PreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The selection can be cleared from outside (e.g. after moving, renaming
    // or recoloring notes), so keep the card's selected overlay in sync.
    // Otherwise it stays faded out and looks like an empty slot.
    if (expanded.value != widget.selected) expanded.value = widget.selected;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _updateDateStr();

    final imageFile = FileManager.getFile(
      '${widget.filePath}${Editor.extension}.p',
    );
    if (isThisATest) {
      // Avoid FileImages in tests
      thumbnail.image = imageFile.existsSync()
          ? MemoryImage(imageFile.readAsBytesSync())
          : null;
    } else {
      thumbnail.image = FileImage(imageFile);
    }
  }

  StreamSubscription? fileWriteSubscription;
  void fileWriteListener(FileOperation event) {
    if (event.filePath != widget.filePath) return;
    if (event.type == .delete) {
      thumbnail.image = null;
    } else if (event.type == .write) {
      thumbnail.image?.evict();
      thumbnail.markAsChanged();
      if (mounted) setState(_updateDateStr);
    } else {
      throw Exception('Unknown file operation type: ${event.type}');
    }
  }

  void _toggleCardSelection() {
    expanded.value = !expanded.value;
    widget.toggleSelection(widget.filePath, expanded.value);
  }

  Timer? _refreshThumbnailTimer;
  void _refreshThumbnailAfterDelay() {
    _refreshThumbnailTimer?.cancel();
    _refreshThumbnailTimer = Timer(const Duration(milliseconds: 500), () {
      thumbnail.image?.evict();
      thumbnail.markAsChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: stows.noteColors,
      builder: (context, _) {
        return _buildCard(context);
      },
    );
  }

  Widget _buildCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final transitionDuration = Duration(
      milliseconds: disableAnimations ? 0 : 300,
    );
    final invert = theme.brightness == .dark && stows.editorAutoInvert.value;

    // The note's cover color, if the user set one. Muted in dark mode
    // so pastel covers don't glare.
    Color? noteColor = NoteCoverColors.of(widget.filePath);
    if (noteColor != null && theme.brightness == .dark) {
      noteColor = Color.lerp(noteColor, colorScheme.surface, 0.45)!;
    }

    final Widget card = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.isAnythingSelected ? _toggleCardSelection : null,
        onSecondaryTap: _toggleCardSelection,
        onLongPress: _toggleCardSelection,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: noteColor,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisSize: stows.homeLayout.value.fillVertical ? .max : .min,
            children: [
              Flexible(
                fit: stows.homeLayout.value.fillVertical ? .tight : .loose,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: noteColor == null
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ColoredBox(
                            color: InnerCanvas.defaultBackgroundColor
                                .withInversion(invert),
                          ),
                        ),
                        ListenableBuilder(
                          listenable: thumbnail,
                          builder: (context, _) => AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: ConstrainedBox(
                              key: ValueKey(thumbnail.updateCount),
                              constraints: const BoxConstraints(
                                minWidth: double.infinity,
                                minHeight: 100,
                              ),
                              child: InvertWidget(
                                invert: invert,
                                child: thumbnail.doesImageExist
                                    ? Image(
                                        image: thumbnail.image!,
                                        alignment: .topCenter,
                                        fit: .cover,
                                      )
                                    : const _FallbackThumbnail(),
                              ),
                            ),
                          ),
                        ),
                        Positioned.fill(
                          left: -1,
                          top: -1,
                          right: -1,
                          bottom: -1,
                          child: ValueListenableBuilder(
                            valueListenable: expanded,
                            builder: (context, expanded, child) =>
                                AnimatedOpacity(
                                  opacity: expanded ? 1 : 0,
                                  duration: const Duration(milliseconds: 200),
                                  child: IgnorePointer(
                                    ignoring: !expanded,
                                    child: child!,
                                  ),
                                ),
                            child: GestureDetector(
                              onTap: _toggleCardSelection,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: .topCenter,
                                    end: .bottomCenter,
                                    colors: [
                                      colorScheme.surface.withValues(
                                        alpha: 0.2,
                                      ),
                                      colorScheme.surface.withValues(
                                        alpha: 0.8,
                                      ),
                                      colorScheme.surface.withValues(alpha: 1),
                                    ],
                                  ),
                                ),
                                child: ColoredBox(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.05,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SyncIndicator(filePath: widget.filePath),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
                child: Text(
                  widget.filePath.substring(
                    widget.filePath.lastIndexOf('/') + 1,
                  ),
                  maxLines: 1,
                  overflow: .ellipsis,
                  textAlign: .center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                child: Text(
                  _dateStr,
                  maxLines: 1,
                  overflow: .ellipsis,
                  textAlign: .center,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return ValueListenableBuilder(
      valueListenable: expanded,
      builder: (context, expanded, _) {
        return OpenContainer(
          clipBehavior: Clip.none,
          closedColor: noteColor ?? colorScheme.surface,
          closedShape: RoundedRectangleBorder(
            side: BorderSide(
              color: expanded
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.12),
              width: 2,
            ),
            borderRadius: const .all(.circular(18)),
          ),
          closedElevation: 0,
          closedBuilder: (context, action) => card,
          openColor: colorScheme.surface,
          openBuilder: (context, action) => Editor(path: widget.filePath),
          transitionDuration: transitionDuration,
          routeSettings: RouteSettings(
            name: RoutePaths.editFilePath(widget.filePath),
          ),
          onClosed: (_) => _refreshThumbnailAfterDelay(),
        );
      },
    );
  }

  @override
  void dispose() {
    _refreshThumbnailTimer?.cancel();
    fileWriteSubscription?.cancel();
    super.dispose();
  }
}

class const _FallbackThumbnail() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: InnerCanvas.defaultBackgroundColor,
      child: Center(
        child: Text(
          t.home.noPreviewAvailable,
          style: TextTheme.of(context).bodyMedium?.copyWith(
            color: Stroke.defaultColor.withValues(alpha: 0.7),
            fontStyle: FontStyle.italic,
          ),
          textAlign: .center,
        ),
      ),
    );
  }
}

class _ThumbnailState extends ChangeNotifier {
  var updateCount = 0;
  ImageProvider? _image;

  void markAsChanged() {
    ++updateCount;
    notifyListeners();
  }

  ImageProvider? get image => _image;
  set image(ImageProvider? image) {
    _image = image;
    markAsChanged();
  }

  bool get doesImageExist => switch (image) {
    (final FileImage fileImage) => fileImage.file.existsSync(),
    null => false,
    _ => true,
  };
}
