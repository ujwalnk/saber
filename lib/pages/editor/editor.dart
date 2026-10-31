import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show cos, max, min, sin;

import 'package:collapsible/collapsible.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as flutter_quill;
import 'package:keybinder/keybinder.dart';
import 'package:logging/logging.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/canvas.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/eraser_cursor_painter.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/save_indicator.dart';
import 'package:saber/components/editor/read_only_banner.dart';
import 'package:saber/components/theming/adaptive_alert_dialog.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/dynamic_material_app.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/components/toolbar/samsung_panel.dart';
import 'package:saber/components/toolbar/sticker_picker.dart';
import 'package:saber/components/toolbar/selection_popup.dart';
import 'package:saber/components/toolbar/color_bar.dart';
import 'package:saber/components/toolbar/editor_bottom_sheet.dart';
import 'package:saber/components/toolbar/editor_page_manager.dart';
import 'package:saber/components/toolbar/toolbar.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/editor_exporter.dart';
import 'package:saber/data/editor/editor_history.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/change_notifier_extensions.dart';
import 'package:saber/data/extensions/matrix4_extensions.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/nextcloud/saber_syncer.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/eraser.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/marker.dart';
import 'package:saber/data/tools/laser_pointer.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/select.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/home/whiteboard.dart';
import 'package:sbn/change.dart';
import 'package:super_clipboard/super_clipboard.dart';

typedef _PhotoInfo = ({Uint8List bytes, String extension});

/// The handles around a lasso selection: eight to resize it, one to rotate.
enum _SelectionHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
  rotate,
}

/// Where a paste should go: the page, and the position on that page
/// (in page coordinates).
typedef _PasteTarget = ({int pageIndex, Offset position});

class Editor extends StatefulWidget {
  new({super.key, String? path, this.customTitle, this.pdfPath})
    : initialPath = path != null
          ? Future.value(path)
          : FileManager.newFilePath('/'),
      needsNaming = path == null;

  final Future<String> initialPath;
  final bool needsNaming;

  final String? customTitle;
  final String? pdfPath;

  /// The file extension used by the app.
  /// Files with this extension are
  /// encoded in BSON format.
  static const extension = '.sbn2';

  /// The old file extension used by the app.
  /// Files with this extension are
  /// encoded in JSON format.
  static const extensionOldJson = '.sbn';

  static const double gapBetweenPages = 16;

  /// Returns true if [path] belongs to a hidden file
  /// used by other functions of the app
  static bool isReservedPath(String path) {
    return _reservedFilePaths.any((regex) => regex.hasMatch(path));
  }

  static final _reservedFilePaths = <RegExp>[
    RegExp(RegExp.escape(Whiteboard.filePath)),
  ];

  /// Whether the platform can rasterize a pdf
  static var canRasterPdf = true;

  @override
  State<Editor> createState() => EditorState();
}

class EditorState extends State<Editor> {
  final log = Logger('EditorState');

  late var coreInfo = EditorCoreInfo.placeholder;

  final _canvasGestureDetectorKey = GlobalKey<CanvasGestureDetectorState>();
  final _transformationController = TransformationController();
  double get scrollY {
    final transformation = _transformationController.value;
    final scale = transformation.approxScale;
    final translation = transformation.getTranslation();
    final gestureDetector = _canvasGestureDetectorKey.currentState;

    if (gestureDetector == null) {
      log.warning('scrollY: Could not find CanvasGestureDetectorState');
      return translation.y / scale;
    } else {
      final middle = gestureDetector.containerBounds.maxHeight / 2;
      return (translation.y - middle) / scale + middle;
    }
  }

  var history = EditorHistory();

  late bool needsNaming = widget.needsNaming && stows.editorPromptRename.value;

  late Tool _currentTool = () {
    switch (stows.lastTool.value) {
      case .fountainPen:
        if (Pen.currentPen.toolId != stows.lastTool.value) {
          Pen.currentPen = Pen.fountainPen();
        }
        return Pen.currentPen;
      case .ballpointPen:
        if (Pen.currentPen.toolId != stows.lastTool.value) {
          Pen.currentPen = Pen.ballpointPen();
        }
        return Pen.currentPen;
      case .shapePen:
        if (Pen.currentPen.toolId != stows.lastTool.value) {
          Pen.currentPen = ShapePen();
        }
        return Pen.currentPen;
      case .highlighter:
        return Highlighter.currentHighlighter;
      case .pencil:
        return Pencil.currentPencil;
      case .eraser:
        return Eraser();
      case .select:
        return Select.currentSelect;
      case .textEditing:
        return Tool.textEditing;
      case .laserPointer:
        return LaserPointer.currentLaserPointer;
    }
  }();
  Tool get currentTool => _currentTool;
  set currentTool(Tool tool) {
    _currentTool = tool;
    _selectionPopupRect.value = null;
    if (tool is! Eraser) _lastNonEraserTool = tool;
    _eraserCircle.value = null;
    stows.lastTool.value = tool.toolId;
  }

  ValueNotifier<SavingState> savingState = ValueNotifier(SavingState.saved);
  Timer? _delayedSaveTimer;
  Timer? _watchServerTimer;

  // used to prevent accidentally drawing when pinch zooming
  var lastSeenPointerCount = 0;
  Timer? _lastSeenPointerCountTimer;

  ValueNotifier<QuillStruct?> quillFocus = ValueNotifier(null);

  /// Whether the export panel is open. Toggled by the share button in the top
  /// bar and shown next to the toolbar.
  final ValueNotifier<bool> showExportOptions = ValueNotifier(false);

  /// The last non-Eraser [currentTool] value.
  late Tool _lastNonEraserTool = Pen.currentPen;

  /// Where the eraser circle is drawn, in the canvas area's coordinates,
  /// and its radius on screen. Null when the circle is hidden.
  final ValueNotifier<({Offset center, double radius})?> _eraserCircle =
      ValueNotifier(null);

  /// The canvas-area Stack used to position the selection popup.
  final GlobalKey _canvasAreaKey = GlobalKey();

  /// Selection bounds in canvas-area coordinates; null when no selection
  /// should display the popup.
  final ValueNotifier<Rect?> _selectionPopupRect = ValueNotifier(null);

  /// Where the long-press "Paste" button is shown, in canvas-area
  /// coordinates, or null when it is hidden.
  final ValueNotifier<Offset?> _pasteMenuPosition = ValueNotifier(null);

  /// The page and position under the long press that opened the paste menu.
  _PasteTarget? _pasteTarget;
  Timer? _longPressTimer;
  Offset? _longPressStart;
  int _pointersDown = 0;

  static const _longPressDuration = Duration(milliseconds: 500);
  static const _longPressSlop = 18.0;

  /// A finger can long press (unless it is currently drawing or erasing);
  /// a stylus (or mouse) only can while the lasso tool is selected.
  bool _canLongPressToPaste(PointerDeviceKind kind) {
    final tool = currentTool;
    if (tool == Tool.textEditing) return false;
    if (kind == PointerDeviceKind.touch) {
      final fingerIsDrawing = stows.editorFingerDrawing.value;
      return !(fingerIsDrawing && (tool is Pen || tool is Eraser));
    }
    return tool is Select;
  }

  void _onCanvasPointerDown(PointerDownEvent event) {
    _pasteMenuPosition.value = null;
    _pointersDown++;
    _longPressTimer?.cancel();
    if (_pointersDown != 1 ||
        coreInfo.readOnly ||
        !_canLongPressToPaste(event.kind)) {
      return;
    }

    _longPressStart = event.position;
    _longPressTimer = Timer(_longPressDuration, () {
      final start = _longPressStart;
      final canvasBox = _canvasAreaKey.currentContext?.findRenderObject();
      if (!mounted ||
          start == null ||
          canvasBox is! RenderBox ||
          !canvasBox.attached) {
        return;
      }
      _pasteTarget = _pasteTargetAt(start);
      _pasteMenuPosition.value = canvasBox.globalToLocal(start);
    });
  }

  _PasteTarget? _pasteTargetAt(Offset globalPosition) {
    final pageIndex = onWhichPageIsFocalPoint(globalPosition);
    if (pageIndex == null) return null;
    final box = coreInfo.pages[pageIndex].renderBox;
    if (box == null || !box.attached) return null;
    return (pageIndex: pageIndex, position: box.globalToLocal(globalPosition));
  }

  void _onCanvasPointerMove(PointerMoveEvent event) {
    final start = _longPressStart;
    if (start == null) return;
    if ((event.position - start).distance > _longPressSlop) {
      _longPressTimer?.cancel();
    }
  }

  void _onCanvasPointerEnd(PointerEvent event) {
    if (_pointersDown > 0) _pointersDown--;
    _longPressTimer?.cancel();
  }

  /// A private in-app clipboard for copied lasso selections.
  /// The normal system clipboard continues to be used for copied images.
  dynamic _copiedSelection;

  // --- resizing / rotating the lasso selection with its handles ---

  static const _minHandleScale = 0.05;
  static const _rotateHandleDistance = 38.0;

  int? _handlePointer;
  _SelectionHandle? _activeHandle;
  bool _handleMoved = false;

  /// Everything below is in page coordinates, captured when a drag starts.
  Offset _handleStart = .zero;
  Offset _handleAnchor = .zero;
  List<Stroke> _originalStrokes = const [];
  List<EditorImage> _originalImages = const [];
  Path _originalPath = Path();

  Offset _handlePositionOn(Rect bounds, _SelectionHandle handle) {
    return switch (handle) {
      .topLeft => bounds.topLeft,
      .top => bounds.topCenter,
      .topRight => bounds.topRight,
      .right => bounds.centerRight,
      .bottomRight => bounds.bottomRight,
      .bottom => bounds.bottomCenter,
      .bottomLeft => bounds.bottomLeft,
      .left => bounds.centerLeft,
      .rotate => bounds.topCenter,
    };
  }

  _SelectionHandle _oppositeHandle(_SelectionHandle handle) {
    return switch (handle) {
      .topLeft => .bottomRight,
      .top => .bottom,
      .topRight => .bottomLeft,
      .right => .left,
      .bottomRight => .topLeft,
      .bottom => .top,
      .bottomLeft => .topRight,
      .left => .right,
      .rotate => .rotate,
    };
  }

  RenderBox? get _selectionPageBox {
    final select = currentTool;
    if (select is! Select || !select.doneSelecting) return null;
    final index = select.selectResult.pageIndex;
    if (index < 0 || index >= coreInfo.pages.length) return null;
    final box = coreInfo.pages[index].renderBox;
    return box != null && box.attached ? box : null;
  }

  void _startHandleDrag(_SelectionHandle handle, PointerDownEvent event) {
    if (_handlePointer != null || coreInfo.readOnly) return;
    final box = _selectionPageBox;
    if (box == null) return;
    final select = currentTool as Select;
    final result = select.selectResult;
    if (result.isEmpty) return;

    final bounds = result.path.getBounds();
    if (bounds.isEmpty) return;

    _handlePointer = event.pointer;
    _activeHandle = handle;
    _handleMoved = false;
    _originalStrokes = [for (final stroke in result.strokes) stroke.copy()];
    _originalImages = [for (final image in result.images) image.copy()];
    _originalPath = Path.from(result.path);

    final pointerOnPage = box.globalToLocal(event.position);
    if (handle == _SelectionHandle.rotate) {
      _handleAnchor = bounds.center;
      _handleStart = pointerOnPage;
    } else {
      _handleAnchor = _handlePositionOn(bounds, _oppositeHandle(handle));
      _handleStart = _handlePositionOn(bounds, handle);
    }
  }

  void _updateHandleDrag(PointerMoveEvent event) {
    if (event.pointer != _handlePointer) return;
    final handle = _activeHandle;
    final box = _selectionPageBox;
    if (handle == null || box == null) return;
    final select = currentTool as Select;
    final result = select.selectResult;

    final pointer = box.globalToLocal(event.position);
    final anchor = _handleAnchor;
    final start = _handleStart;

    double ratio(double now, double then) {
      if (then.abs() < 1e-6) return 1;
      return max(_minHandleScale, now / then);
    }

    final StrokeTransform transform;
    switch (handle) {
      case .rotate:
        final before = (start - anchor).direction;
        final now = (pointer - anchor).direction;
        transform = StrokeTransform(anchor: anchor, angle: now - before);
      case .topLeft || .topRight || .bottomLeft || .bottomRight:
        final from = start - anchor;
        final to = pointer - anchor;
        final denominator = from.distanceSquared;
        final scale = denominator < 1e-6
            ? 1.0
            : max(
                _minHandleScale,
                (to.dx * from.dx + to.dy * from.dy) / denominator,
              );
        transform = StrokeTransform(
          anchor: anchor,
          scaleX: scale,
          scaleY: scale,
        );
      case .left || .right:
        transform = StrokeTransform(
          anchor: anchor,
          scaleX: ratio(pointer.dx - anchor.dx, start.dx - anchor.dx),
        );
      case .top || .bottom:
        transform = StrokeTransform(
          anchor: anchor,
          scaleY: ratio(pointer.dy - anchor.dy, start.dy - anchor.dy),
        );
    }

    for (var i = 0; i < result.strokes.length; i++) {
      result.strokes[i].applyTransform(_originalStrokes[i], transform);
    }
    for (var i = 0; i < result.images.length; i++) {
      final original = _originalImages[i];
      final rect = original.dstRect;
      result.images[i]
        ..rotation = original.rotation + transform.angle
        ..dstRect = Rect.fromCenter(
          center: transform.apply(rect.center),
          width: rect.width * transform.scaleX.abs(),
          height: rect.height * transform.scaleY.abs(),
        );
    }
    result.path = _originalPath.transform(transform.matrix4);
    _handleMoved = true;

    coreInfo.pages[result.pageIndex].redrawStrokes();
    _updateSelectionPopupRect();
    setState(() {});
  }

  void _endHandleDrag(PointerEvent event) {
    if (event.pointer != _handlePointer) return;
    _handlePointer = null;
    _activeHandle = null;

    final select = currentTool;
    if (select is! Select || !select.doneSelecting) return;
    final result = select.selectResult;
    final originalStrokes = _originalStrokes;
    final originalImages = _originalImages;
    _originalStrokes = const [];
    _originalImages = const [];

    // just a tap on a handle: nothing changed
    if (!_handleMoved) return;
    _handleMoved = false;

    // undo puts back the original, redo puts back the transformed selection
    history.recordChange(
      EditorHistoryItem(
        type: .erase,
        pageIndex: result.pageIndex,
        strokes: originalStrokes,
        images: originalImages,
      ),
    );
    history.recordChange(
      EditorHistoryItem(
        type: .draw,
        pageIndex: result.pageIndex,
        strokes: List.of(result.strokes),
        images: List.of(result.images),
      ),
    );

    // wrap the selection tightly around what it now contains
    Rect? bounds;
    for (final stroke in result.strokes) {
      final strokeBounds = stroke.lowQualityPath.getBounds();
      bounds = bounds == null
          ? strokeBounds
          : bounds.expandToInclude(strokeBounds);
    }
    for (final image in result.images) {
      final imageBounds = _imageBounds(image);
      bounds = bounds == null
          ? imageBounds
          : bounds.expandToInclude(imageBounds);
    }
    if (bounds != null && !bounds.isEmpty) {
      result.path = Path()..addRect(bounds);
    }

    _updateSelectionPopupRect();
    setState(() {});
    autosaveAfterDelay();
  }

  /// The smallest page-coordinate rect that contains [image], rotation included.
  Rect _imageBounds(EditorImage image) {
    final rect = image.dstRect;
    if (image.rotation == 0) return rect;
    final c = cos(image.rotation);
    final s = sin(image.rotation);
    final center = rect.center;
    final corners = [
      for (final corner in [
        rect.topLeft,
        rect.topRight,
        rect.bottomLeft,
        rect.bottomRight,
      ])
        () {
          final d = corner - center;
          return center + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
        }(),
    ];
    return Rect.fromLTRB(
      corners.map((p) => p.dx).reduce(min),
      corners.map((p) => p.dy).reduce(min),
      corners.map((p) => p.dx).reduce(max),
      corners.map((p) => p.dy).reduce(max),
    );
  }

  /// Picks a sticker in the app and drops it in the middle of the screen,
  /// selected so it can be moved, resized and rotated right away.
  Future<void> _pickSticker() async {
    if (coreInfo.readOnly) return;

    final file = await StickerPicker.show(context);
    if (file == null || !mounted) return;

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      return;
    }
    final name = file.path.toLowerCase();
    final dot = name.lastIndexOf('.');
    final extension = dot < 0 ? '.png' : name.substring(dot);

    final canvasBox = _canvasAreaKey.currentContext?.findRenderObject();
    _PasteTarget? target;
    if (canvasBox is RenderBox && canvasBox.attached) {
      target = _pasteTargetAt(
        canvasBox.localToGlobal(canvasBox.size.center(Offset.zero)),
      );
    }

    final pageIndex = target?.pageIndex ?? currentPageIndex;
    final imageCountBefore = coreInfo.pages[pageIndex].images.length;
    final added = await _pickPhotos([
      (bytes: bytes, extension: extension),
    ], target);
    if (added == 0 || !mounted) return;

    final images = coreInfo.pages[pageIndex].images;
    if (images.length <= imageCountBefore) return;
    final image = images.last;

    // the selection frame replaces the image's own "just added" frame
    image.newImage = false;
    setTool(Select.currentSelect);
    _selectImageWhenLoaded(image);
  }

  void _selectImageWhenLoaded(EditorImage image) {
    void select() {
      if (!mounted) return;
      final tool = Select.currentSelect;
      tool.selectResult = SelectResult(
        pageIndex: image.pageIndex,
        strokes: [],
        images: [image],
        path: Path()..addRect(_imageBounds(image)),
      );
      tool.doneSelecting = true;
      _updateSelectionPopupRect();
      setState(() {});
    }

    if (!image.dstRect.isEmpty) {
      select();
      return;
    }

    void listener() {
      if (image.dstRect.isEmpty) return;
      image.removeListener(listener);
      // let the image finish centering itself first
      WidgetsBinding.instance.addPostFrameCallback((_) => select());
    }

    image.addListener(listener);
  }

  /// Moves the selected images one layer up or down. Within a page the order
  /// is: images below the strokes, the strokes, then images above the strokes.
  void _moveImagesLayer(bool forward) {
    final select = currentTool;
    if (select is! Select || !select.doneSelecting || coreInfo.readOnly) {
      return;
    }
    final result = select.selectResult;
    if (result.images.isEmpty) return;

    final page = coreInfo.pages[result.pageIndex];
    final selected = result.images.toSet();

    ImageLayers snapshot() => [
      for (final image in page.images)
        (image: image, above: image.aboveStrokes),
    ];
    final before = snapshot();

    final below = [
      for (final image in page.images)
        if (!image.aboveStrokes) image,
    ];
    final above = [
      for (final image in page.images)
        if (image.aboveStrokes) image,
    ];

    void swapUp(List<EditorImage> layer) {
      for (var i = layer.length - 2; i >= 0; i--) {
        if (selected.contains(layer[i]) && !selected.contains(layer[i + 1])) {
          final image = layer.removeAt(i);
          layer.insert(i + 1, image);
        }
      }
    }

    void swapDown(List<EditorImage> layer) {
      for (var i = 1; i < layer.length; i++) {
        if (selected.contains(layer[i]) && !selected.contains(layer[i - 1])) {
          final image = layer.removeAt(i);
          layer.insert(i - 1, image);
        }
      }
    }

    if (forward) {
      // selected images already on top of the lower layer cross over the strokes
      final crossing = <EditorImage>[];
      while (below.isNotEmpty && selected.contains(below.last)) {
        crossing.insert(0, below.removeLast());
      }
      swapUp(below);
      swapUp(above);
      above.insertAll(0, crossing);
    } else {
      final crossing = <EditorImage>[];
      while (above.isNotEmpty && selected.contains(above.first)) {
        crossing.add(above.removeAt(0));
      }
      swapDown(above);
      swapDown(below);
      below.addAll(crossing);
    }

    for (final image in below) {
      image.aboveStrokes = false;
    }
    for (final image in above) {
      image.aboveStrokes = true;
    }
    page.images
      ..clear()
      ..addAll(below)
      ..addAll(above);

    final after = snapshot();
    var changed = before.length != after.length;
    for (var i = 0; !changed && i < before.length; i++) {
      changed =
          before[i].image != after[i].image ||
          before[i].above != after[i].above;
    }
    if (!changed) return;

    history.recordChange(
      EditorHistoryItem(
        type: .layerChange,
        pageIndex: result.pageIndex,
        strokes: const [],
        images: const [],
        layerChange: Change(previous: before, current: after),
      ),
    );
    setState(() {});
    autosaveAfterDelay();
  }

  Widget _buildSelectionHandles(Rect rect, ColorScheme colorScheme) {
    const hit = 40.0;
    const dot = 14.0;
    final handles = [
      for (final handle in _SelectionHandle.values)
        (
          handle,
          switch (handle) {
            .rotate => rect.topCenter - const Offset(0, _rotateHandleDistance),
            _ => _handlePositionOn(rect, handle),
          },
        ),
    ];

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fromRect(
            rect: rect,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: colorScheme.primary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: rect.center.dx - 0.5,
            top: rect.top - _rotateHandleDistance,
            width: 1,
            height: _rotateHandleDistance,
            child: IgnorePointer(
              child: ColoredBox(
                color: colorScheme.primary.withValues(alpha: 0.7),
              ),
            ),
          ),
          for (final (handle, position) in handles)
            Positioned(
              left: position.dx - hit / 2,
              top: position.dy - hit / 2,
              width: hit,
              height: hit,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => _startHandleDrag(handle, event),
                onPointerMove: _updateHandleDrag,
                onPointerUp: _endHandleDrag,
                onPointerCancel: _endHandleDrag,
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      shape: handle == _SelectionHandle.rotate
                          ? BoxShape.circle
                          : BoxShape.rectangle,
                      borderRadius: handle == _SelectionHandle.rotate
                          ? null
                          : const BorderRadius.all(Radius.circular(3)),
                      border: Border.all(color: colorScheme.primary, width: 2),
                    ),
                    child: SizedBox.square(
                      dimension: handle == _SelectionHandle.rotate
                          ? dot + 4
                          : dot,
                      child: handle == _SelectionHandle.rotate
                          ? Icon(
                              Icons.rotate_right,
                              size: dot,
                              color: colorScheme.primary,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Recomputes the selection popup's position in canvas-area coordinates.
  void _updateSelectionPopupRect() {
    if (currentTool is! Select) {
      _selectionPopupRect.value = null;
      return;
    }

    final select = currentTool as Select;
    if (!select.doneSelecting || select.selectResult.isEmpty) {
      _selectionPopupRect.value = null;
      return;
    }

    final pageIndex = select.selectResult.pageIndex;
    if (pageIndex < 0 || pageIndex >= coreInfo.pages.length) {
      _selectionPopupRect.value = null;
      return;
    }

    final pageBox = coreInfo.pages[pageIndex].renderBox;
    final canvasBox = _canvasAreaKey.currentContext?.findRenderObject();
    if (pageBox == null ||
        !pageBox.attached ||
        canvasBox is! RenderBox ||
        !canvasBox.attached ||
        !canvasBox.hasSize) {
      _selectionPopupRect.value = null;
      return;
    }

    final bounds = select.selectResult.path.getBounds();
    if (bounds.isEmpty) {
      _selectionPopupRect.value = null;
      return;
    }

    final topLeft = canvasBox.globalToLocal(
      pageBox.localToGlobal(bounds.topLeft),
    );
    final bottomRight = canvasBox.globalToLocal(
      pageBox.localToGlobal(bounds.bottomRight),
    );
    _selectionPopupRect.value = Rect.fromLTRB(
      min(topLeft.dx, bottomRight.dx),
      min(topLeft.dy, bottomRight.dy),
      max(topLeft.dx, bottomRight.dx),
      max(topLeft.dy, bottomRight.dy),
    );
  }

  void _duplicateSelection() {
    if (coreInfo.readOnly || currentTool is! Select) return;
    final select = currentTool as Select;
    if (!select.doneSelecting || select.selectResult.isEmpty) return;

    setState(() {
      final result = select.selectResult;
      final page = coreInfo.pages[result.pageIndex];
      const offset = Offset(25, -25);

      final duplicatedStrokes = result.strokes
          .map((stroke) => stroke.copy()..shift(offset))
          .toList();
      final duplicatedImages = result.images.map((image) {
        final copy = image.copy()
          ..id = coreInfo.nextImageId++
          ..pageIndex = result.pageIndex;
        copy.dstRect = copy.dstRect.shift(offset);
        return copy;
      }).toList();

      page.strokes.addAll(duplicatedStrokes);
      page.images.addAll(duplicatedImages);

      select.selectResult = result.copyWith(
        strokes: duplicatedStrokes,
        images: duplicatedImages,
        path: result.path.shift(offset),
      );

      history.recordChange(
        EditorHistoryItem(
          type: .draw,
          pageIndex: result.pageIndex,
          strokes: duplicatedStrokes,
          images: duplicatedImages,
        ),
      );
      autosaveAfterDelay();
    });
    _updateSelectionPopupRect();
  }

  void _copySelection() {
    if (currentTool is! Select) return;
    final select = currentTool as Select;
    if (!select.doneSelecting || select.selectResult.isEmpty) return;

    final result = select.selectResult;
    _copiedSelection = result.copyWith(
      strokes: result.strokes.map((stroke) => stroke.copy()).toList(),
      images: result.images.map((image) => image.copy()).toList(),
    );
  }

  void _deleteSelection() {
    if (coreInfo.readOnly || currentTool is! Select) return;
    final select = currentTool as Select;
    if (!select.doneSelecting || select.selectResult.isEmpty) return;

    setState(() {
      final result = select.selectResult;
      final page = coreInfo.pages[result.pageIndex];
      final strokes = List<Stroke>.of(result.strokes);
      final images = List<EditorImage>.of(result.images);

      for (final stroke in strokes) {
        page.strokes.remove(stroke);
      }
      for (final image in images) {
        page.images.remove(image);
      }

      select.unselect();
      _selectionPopupRect.value = null;
      history.recordChange(
        EditorHistoryItem(
          type: .erase,
          pageIndex: result.pageIndex,
          strokes: strokes,
          images: images,
        ),
      );
      autosaveAfterDelay();
    });
  }

  /// Pastes the in-app copied selection onto the currently focused page.
  /// Returns false when the in-app clipboard is empty so the caller can fall
  /// back to the operating-system clipboard for images.
  bool _pasteCopiedSelection([_PasteTarget? target]) {
    final copied = _copiedSelection;
    if (copied == null || coreInfo.readOnly) return false;

    final pageIndex = target?.pageIndex ?? currentPageIndex;
    var offset = const Offset(25, -25);
    if (target != null) {
      // center the pasted selection on the long press
      final bounds = copied.path.getBounds();
      if (!bounds.isEmpty) offset = target.position - bounds.center;
    }
    final strokes = (copied.strokes as List<Stroke>).map((stroke) {
      return stroke.copy()
        ..pageIndex = pageIndex
        ..shift(offset);
    }).toList();
    final images = (copied.images as List<EditorImage>).map((image) {
      final copy = image.copy()
        ..id = coreInfo.nextImageId++
        ..pageIndex = pageIndex;
      copy.dstRect = copy.dstRect.shift(offset);
      return copy;
    }).toList();

    setState(() {
      createPage(pageIndex);
      coreInfo.pages[pageIndex].strokes.addAll(strokes);
      coreInfo.pages[pageIndex].images.addAll(images);
      history.recordChange(
        EditorHistoryItem(
          type: .draw,
          pageIndex: pageIndex,
          strokes: strokes,
          images: images,
        ),
      );
      autosaveAfterDelay();
    });
    return true;
  }

  /// How many screen pixels one page unit takes up at [globalPosition].
  double? _pageUnitOnScreen(Offset globalPosition) {
    final index = onWhichPageIsFocalPoint(globalPosition);
    final candidates = [
      if (index != null) coreInfo.pages[index],
      ...coreInfo.pages,
    ];
    for (final page in candidates) {
      final box = page.renderBox;
      if (box == null || !box.attached || !box.hasSize) continue;
      final origin = box.localToGlobal(Offset.zero);
      final unit = box.localToGlobal(const Offset(1, 0));
      return (unit - origin).distance;
    }
    return null;
  }

  void _updateEraserCircle(PointerEvent event) {
    final tool = currentTool;
    if (tool is! Eraser) {
      _eraserCircle.value = null;
      return;
    }
    final unit = _pageUnitOnScreen(event.position);
    if (unit == null) {
      _eraserCircle.value = null;
      return;
    }
    _eraserCircle.value = (
      center: event.localPosition,
      radius: max(tool.size * unit, 2.0),
    );
  }

  /// Touch has no hover, so the circle goes away when the finger lifts.
  /// Mouse and stylus keep it where they are.
  void _onEraserPointerUp(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch) _eraserCircle.value = null;
  }

  /// If the stylus button is pressed, or was pressed, during the current draw gesture.
  ///
  /// For now, this also includes when an [PointerDeviceKind.inverseStylus] is
  /// used since the stylus rear-end and stylus button currently act the same.
  /// If we add customized button bindings, we may have to separate this again.
  var stylusButtonWasPressed = false;

  @override
  void initState() {
    DynamicMaterialApp.addFullscreenListener(_setState);

    _initAsync();
    _assignKeybindings();

    super.initState();
  }

  void _initAsync() async {
    final filePath = await widget.initialPath;
    filenameTextEditingController.text = p.basename(filePath);

    if (needsNaming) {
      filenameTextEditingController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: filenameTextEditingController.text.length,
      );
    }

    await _loadCoreInfo(filePath);

    if (widget.pdfPath != null) {
      await importPdfFromFilePath(widget.pdfPath!);
    }
  }

  Future _loadCoreInfo(String filePath) async {
    coreInfo = await EditorCoreInfo.loadFromFilePath(filePath);
    if (coreInfo.readOnly) {
      log.info('Loaded file as read-only: ${coreInfo.readOnlyReason}');
    }

    for (int pageIndex = 0; pageIndex < coreInfo.pages.length; pageIndex++) {
      listenToQuillChanges(coreInfo.pages[pageIndex].quill, pageIndex);
    }

    if (coreInfo.isEmpty) {
      createPage(-1);
    } else {
      for (final page in coreInfo.pages) {
        page.backgroundImage?.onMoveImage = onMoveImage;
        page.backgroundImage?.onDeleteImage = onDeleteImage;
        page.backgroundImage?.onMiscChange = autosaveAfterDelay;
        for (final image in page.images) {
          image.onMoveImage = onMoveImage;
          image.onDeleteImage = onDeleteImage;
          image.onMiscChange = autosaveAfterDelay;
        }
      }
    }

    if (currentTool == Tool.textEditing) {
      int pageIndex;
      if (coreInfo.initialPageIndex != null) {
        pageIndex = coreInfo.initialPageIndex!;
      } else {
        pageIndex = 0;
      }
      assert(pageIndex < coreInfo.pages.length);

      quillFocus.value = coreInfo.pages[pageIndex].quill
        ..focusNode.requestFocus();
    }

    if (coreInfo.filePath == Whiteboard.filePath &&
        stows.autoClearWhiteboardOnExit.value &&
        Whiteboard.needsToAutoClearWhiteboard) {
      // clear whiteboard (and add to history)
      clearAllPages();

      // save cleared whiteboard
      await saveToFile();
      Whiteboard.needsToAutoClearWhiteboard = false;
    } else {
      setState(() {});
    }
  }

  void _setState() => setState(() {});

  Keybinding? _ctrlZ, _ctrlY, _ctrlShiftZ;
  void _assignKeybindings() {
    _ctrlZ = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyZ),
    ], inclusive: true);
    _ctrlY = Keybinding([
      KeyCode.ctrl,
      KeyCode.from(LogicalKeyboardKey.keyY),
    ], inclusive: true);
    _ctrlShiftZ = Keybinding([
      KeyCode.ctrl,
      KeyCode.shift,
      KeyCode.from(LogicalKeyboardKey.keyZ),
    ], inclusive: true);
    Keybinder.bind(_ctrlZ!, undo);
    Keybinder.bind(_ctrlY!, redo);
    Keybinder.bind(_ctrlShiftZ!, redo);
  }

  void _removeKeybindings() {
    if (_ctrlZ != null) Keybinder.remove(_ctrlZ!);
    if (_ctrlY != null) Keybinder.remove(_ctrlY!);
    if (_ctrlShiftZ != null) Keybinder.remove(_ctrlShiftZ!);
  }

  /// Creates pages until the given page index exists,
  /// plus an extra blank page
  void createPage(int pageIndex) {
    while (pageIndex >= coreInfo.pages.length - 1) {
      final page = EditorPage();
      coreInfo.pages.add(page);
      listenToQuillChanges(page.quill, coreInfo.pages.length - 1);
    }
  }

  void removeExcessPages() {
    bool removedAPage = false;

    // remove excess pages if all pages >= this one are empty
    for (int i = coreInfo.pages.length - 1; i >= 1; --i) {
      final thisPage = coreInfo.pages[i];
      final prevPage = coreInfo.pages[i - 1];
      if (thisPage.isEmpty && prevPage.isEmpty) {
        final page = coreInfo.pages.removeAt(i);
        page.dispose();
        removedAPage = true;
      } else {
        break;
      }
    }

    if (removedAPage) {
      // scroll to the last page (only if we're below the last page)

      final scrollY = this.scrollY;
      late final topOfLastPage = -CanvasGestureDetector.getTopOfPage(
        pageIndex: coreInfo.pages.length - 1,
        pages: coreInfo.pages,
        screenWidth: MediaQuery.sizeOf(context).width,
      );
      final bottomOfLastPage = -CanvasGestureDetector.getTopOfPage(
        pageIndex: coreInfo.pages.length,
        pages: coreInfo.pages,
        screenWidth: MediaQuery.sizeOf(context).width,
      );

      if (scrollY < bottomOfLastPage) {
        _transformationController.value = Matrix4.translationValues(
          0,
          // Slight upwards offset so that the page is not flush with the top of the screen
          topOfLastPage + 50,
          0,
        );
      }
    }
  }

  void undo([EditorHistoryItem? item]) {
    if (item == null) {
      if (!history.canUndo) return;

      // if we disabled redo, re-enable it
      if (!history.canRedo) {
        // no redo is possible, so clear the redo stack
        history.clearRedo();
        // don't disable redoing anymore
        history.canRedo = true;
      }

      item = history.undo();
    }

    setState(() {
      switch (item!.type) {
        case .draw:
          for (final stroke in item.strokes) {
            coreInfo.pages[stroke.pageIndex].strokes.remove(stroke);
          }
          for (final image in item.images) {
            coreInfo.pages[image.pageIndex].images.remove(image);
          }
          removeExcessPages();

        case .erase:
          for (final stroke in item.replacementStrokes) {
            coreInfo.pages[stroke.pageIndex].strokes.remove(stroke);
          }
          for (final stroke in item.strokes) {
            createPage(stroke.pageIndex);
            coreInfo.pages[stroke.pageIndex].insertStroke(stroke);
          }
          for (final image in item.images) {
            createPage(image.pageIndex);
            coreInfo.pages[image.pageIndex].images.add(image);
            image.newImage = true;
          }

        case .deletePage:
          // make sure we already have a (blank/otherwise) page at this index
          createPage(item.pageIndex - 1);

          // insert the page at the correct index
          coreInfo.pages.insert(item.pageIndex, item.page!);

          // fix the page indices of all pages after this one
          for (int i = item.pageIndex + 1; i < coreInfo.pages.length; ++i) {
            final page = coreInfo.pages[i];
            page.updatePageIndex(i);
          }

        case .insertPage:
          // remove the page at the given index
          coreInfo.pages.removeAt(item.pageIndex);

          // fix the page indices of all pages after this one
          for (int i = item.pageIndex; i < coreInfo.pages.length; ++i) {
            final page = coreInfo.pages[i];
            page.updatePageIndex(i);
          }

        case .move:
          for (final stroke in item.strokes) {
            stroke.shift(Offset(-item.offset!.left, -item.offset!.top));
          }
          final select = Select.currentSelect;
          if (select.doneSelecting) {
            select.selectResult.path = select.selectResult.path.shift(
              Offset(-item.offset!.left, -item.offset!.top),
            );
          }
          for (final image in item.images) {
            image.dstRect = .fromLTRB(
              image.dstRect.left - item.offset!.left,
              image.dstRect.top - item.offset!.top,
              image.dstRect.right - item.offset!.right,
              image.dstRect.bottom - item.offset!.bottom,
            );
          }

        case .quillChange:
          final quill = coreInfo.pages[item.pageIndex].quill;
          quill.controller.undo();

        case .quillUndoneChange:
          final quill = coreInfo.pages[item.pageIndex].quill;
          quill.controller.redo();

        case .changeColor:
          for (final stroke in item.strokes) {
            stroke.color = item.colorChange![stroke]!.previous;
          }

        case .backgroundPattern:
          coreInfo.backgroundPattern = item.backgroundPatternChange!.previous;

        case .layerChange:
          final page = coreInfo.pages[item.pageIndex];
          final layers = item.layerChange!.previous;
          page.images
            ..clear()
            ..addAll([for (final layer in layers) layer.image]);
          for (final layer in layers) {
            layer.image.aboveStrokes = layer.above;
          }
      }

      if (item.type != .move) {
        Select.currentSelect.unselect();
        _selectionPopupRect.value = null;
      }
    });

    if (item.type == .move) _updateSelectionPopupRect();
    autosaveAfterDelay();
  }

  void redo() {
    if (!history.canRedo) return;
    final item = history.redo();

    switch (item.type) {
      case .draw:
        undo(item.copyWith(type: .erase));
      case .erase:
        if (item.replacementStrokes.isEmpty) {
          undo(item.copyWith(type: .draw));
        } else {
          // Redo a partial erase: bring the pieces back and remove the
          // originals, which is the undo of the swapped item.
          undo(
            item.copyWith(
              strokes: item.replacementStrokes,
              replacementStrokes: item.strokes,
            ),
          );
        }
      case .deletePage:
        undo(item.copyWith(type: .insertPage));
      case .insertPage:
        undo(item.copyWith(type: .deletePage));
      case .move:
        undo(
          item.copyWith(
            offset: .fromLTRB(
              -item.offset!.left,
              -item.offset!.top,
              -item.offset!.right,
              -item.offset!.bottom,
            ),
          ),
        );
      case .quillChange:
        undo(item.copyWith(type: .quillUndoneChange));
      case .quillUndoneChange: // this will never happen
        throw Exception('history should not contain quillUndoneChange items');
      case .changeColor:
        undo(
          item.copyWith(
            colorChange: item.colorChange!.map(
              (key, value) => MapEntry(key, value.reverse()),
            ),
          ),
        );
      case .layerChange:
        undo(item.copyWith(layerChange: item.layerChange!.reverse()));
      case .backgroundPattern:
        undo(
          item.copyWith(
            backgroundPatternChange: item.backgroundPatternChange!.reverse(),
          ),
        );
    }
  }

  int? onWhichPageIsFocalPoint(Offset focalPoint) {
    for (int i = 0; i < coreInfo.pages.length; ++i) {
      if (coreInfo.pages[i].renderBox == null) continue;
      final pageBounds = Offset.zero & coreInfo.pages[i].size;
      if (pageBounds.contains(
        coreInfo.pages[i].renderBox!.globalToLocal(focalPoint),
      ))
        return i;
    }
    return null;
  }

  /// The position of the previous draw gesture event.
  /// Used to move a selection.
  Offset previousPosition = .zero;

  /// The total offset of the current move gesture.
  /// Used to record a move in the history.
  Offset moveOffset = .zero;

  /// Set while a lasso selection is dragged from one page onto another:
  /// the page it started on, and copies of its contents as they were before
  /// the drag. Used to record a single undoable change when the drag ends.
  int? _selectionOriginPage;
  List<Stroke>? _originStrokes;
  List<EditorImage>? _originImages;

  var isHovering = true;
  int? dragPageIndex;
  PointerDeviceKind? currentPointerKind;
  double? currentPressure;
  bool isDrawGesture(ScaleStartDetails details) {
    if (coreInfo.readOnly) return false;

    CanvasImage.activeListener
        .notifyListenersPlease(); // un-select active image

    _lastSeenPointerCountTimer?.cancel();
    if (lastSeenPointerCount >= 2) {
      // was a zoom gesture, ignore
      lastSeenPointerCount = lastSeenPointerCount;
      return false;
    } else if (details.pointerCount >= 2) {
      // is a zoom gesture, remove accidental stroke
      if (lastSeenPointerCount == 1 &&
          stows.editorFingerDrawing.value &&
          (currentTool is Pen || currentTool is Eraser)) {
        final item = history.removeAccidentalStroke();
        if (item != null) undo(item);
      }
      lastSeenPointerCount = details.pointerCount;
      return false;
    } else {
      // is a stroke
      lastSeenPointerCount = details.pointerCount;
    }

    dragPageIndex = onWhichPageIsFocalPoint(details.focalPoint);
    if (dragPageIndex == null) return false;

    if (currentTool == Tool.textEditing) {
      return false;
    } else if (stows.editorFingerDrawing.value ||
        currentPointerKind == PointerDeviceKind.stylus ||
        currentPointerKind == PointerDeviceKind.invertedStylus ||
        currentPressure != null) {
      return true;
    } else {
      log.fine('Non-stylus found, rejected stroke');
      return false;
    }
  }

  void onDrawStart(ScaleStartDetails details) {
    final page = coreInfo.pages[dragPageIndex!];
    final position = page.renderBox!.globalToLocal(details.focalPoint);
    history.canRedo = false;

    if (currentTool is Pen) {
      (currentTool as Pen).onDragStart(
        position,
        page,
        dragPageIndex!,
        currentPressure,
      );
    } else if (currentTool is Eraser) {
      (currentTool as Eraser).erase(position, position, page);
      removeExcessPages();
    } else if (currentTool is Select) {
      final select = currentTool as Select;
      if (select.doneSelecting &&
          select.selectResult.pageIndex == dragPageIndex! &&
          select.selectResult.path.contains(position)) {
        // drag selection in onDrawUpdate
      } else {
        _selectionPopupRect.value = null;
        select.onDragStart(position, dragPageIndex!);
        history.canRedo = true; // selection doesn't affect history
      }
    } else if (currentTool is LaserPointer) {
      (currentTool as LaserPointer).onDragStart(position, page, dragPageIndex!);
    }

    previousPosition = position;
    moveOffset = .zero;
    _selectionOriginPage = null;
    _originStrokes = null;
    _originImages = null;

    if (currentTool is! Select) {
      Select.currentSelect.unselect();
    }

    // setState to let canvas know about currentStroke
    setState(() {});
  }

  /// While dragging a lasso selection, moves it onto the page that is under
  /// the pointer, so it stays visible (and is saved) on the page it is
  /// dropped on.
  void _rehomeSelectionIfNeeded(Select select, Offset globalFocalPoint) {
    final to = onWhichPageIsFocalPoint(globalFocalPoint);
    final from = dragPageIndex!;
    if (to == null || to == from) return;

    final srcPage = coreInfo.pages[from];
    final dstPage = coreInfo.pages[to];
    final srcBox = srcPage.renderBox;
    final dstBox = dstPage.renderBox;
    if (srcBox == null ||
        dstBox == null ||
        !srcBox.attached ||
        !dstBox.attached) {
      return;
    }

    final result = select.selectResult;

    // remember what the selection looked like before this drag, once
    if (_selectionOriginPage == null) {
      _selectionOriginPage = from;
      _originStrokes = [
        for (final stroke in result.strokes) stroke.copy()..shift(-moveOffset),
      ];
      _originImages = [
        for (final image in result.images)
          image.copy()..dstRect = image.dstRect.shift(-moveOffset),
      ];
    }

    // converts page [from] coordinates into page [to] coordinates
    final delta = dstBox.globalToLocal(srcBox.localToGlobal(Offset.zero));

    for (final stroke in result.strokes) {
      srcPage.strokes.remove(stroke);
      stroke
        ..shift(delta)
        ..pageIndex = to
        ..page = dstPage;
      dstPage.insertStroke(stroke);
    }
    for (final image in result.images) {
      srcPage.images.remove(image);
      image
        ..pageIndex = to
        ..dstRect = image.dstRect.shift(delta);
      dstPage.images.add(image);
    }

    select.selectResult = result.copyWith(
      pageIndex: to,
      path: result.path.shift(delta),
    );

    dragPageIndex = to;
    previousPosition += delta;
    srcPage.redrawStrokes();
    dstPage.redrawStrokes();
    setState(() {});
  }

  void onDrawUpdate(ScaleUpdateDetails details) {
    if (currentTool is Select && (currentTool as Select).doneSelecting) {
      _rehomeSelectionIfNeeded(currentTool as Select, details.focalPoint);
    }

    final page = coreInfo.pages[dragPageIndex!];
    final position = page.renderBox!.globalToLocal(details.focalPoint);
    final offset = position - previousPosition;

    if (currentTool is Pen) {
      (currentTool as Pen).onDragUpdate(position, currentPressure);
      page.redrawStrokes();
    } else if (currentTool is Eraser) {
      (currentTool as Eraser).erase(previousPosition, position, page);
      page.redrawStrokes();
      removeExcessPages();
    } else if (currentTool is Select) {
      final select = currentTool as Select;
      if (select.doneSelecting) {
        for (final stroke in select.selectResult.strokes) {
          stroke.shift(offset);
        }
        for (final image in select.selectResult.images) {
          image.dstRect = image.dstRect.shift(offset);
        }
        select.selectResult.path = select.selectResult.path.shift(offset);
        _updateSelectionPopupRect();
      } else {
        select.onDragUpdate(position);
      }
      page.redrawStrokes();
    } else if (currentTool is LaserPointer) {
      (currentTool as LaserPointer).onDragUpdate(position);
      page.redrawStrokes();
    }
    previousPosition = position;
    moveOffset += offset;
  }

  void onDrawEnd(ScaleEndDetails details) {
    final page = coreInfo.pages[dragPageIndex!];
    bool shouldSave = true;
    setState(() {
      if (currentTool is Pen) {
        final newStroke = (currentTool as Pen).onDragEnd();
        if (newStroke == null) return;
        if (newStroke.isEmpty) return;

        if (currentTool is! ShapePen) {
          if (stows.autoStraightenHighlighterOnly.value) {
            // Highlighter strokes are always straightened, whatever their
            // length or shape. Pens and pencil are left exactly as drawn.
            if (newStroke.toolId == .highlighter &&
                newStroke.points.length >= 2 &&
                newStroke.points.first != newStroke.points.last) {
              newStroke.convertToLine();
            }
          } else if (stows.autoStraightenLines.value &&
              newStroke.isStraightLine()) {
            newStroke.convertToLine();
          }
        }

        createPage(newStroke.pageIndex);
        page.insertStroke(newStroke);
        history.recordChange(
          EditorHistoryItem(
            type: .draw,
            pageIndex: dragPageIndex!,
            strokes: [newStroke],
            images: [],
          ),
        );
      } else if (currentTool is Eraser) {
        final result = (currentTool as Eraser).onDragEnd();
        if (stylusButtonWasPressed || stows.disableEraserAfterUse.value) {
          // restore previous tool
          stylusButtonWasPressed = false;
          currentTool = _lastNonEraserTool;
        }
        if (result.erased.isEmpty) return;
        history.recordChange(
          EditorHistoryItem(
            type: .erase,
            pageIndex: dragPageIndex!,
            strokes: result.erased,
            replacementStrokes: result.added,
            images: [],
          ),
        );
      } else if (currentTool is Select) {
        if (moveOffset == .zero && _selectionOriginPage == null) return;
        final select = currentTool as Select;
        if (select.doneSelecting && _selectionOriginPage != null) {
          // the selection was dragged across pages: undo puts the original
          // back on its page, redo puts the dropped one back
          history.recordChange(
            EditorHistoryItem(
              type: .erase,
              pageIndex: _selectionOriginPage!,
              strokes: _originStrokes!,
              images: _originImages!,
            ),
          );
          history.recordChange(
            EditorHistoryItem(
              type: .draw,
              pageIndex: dragPageIndex!,
              strokes: List.of(select.selectResult.strokes),
              images: List.of(select.selectResult.images),
            ),
          );
          _selectionOriginPage = null;
          _originStrokes = null;
          _originImages = null;
          _updateSelectionPopupRect();
        } else if (select.doneSelecting) {
          history.recordChange(
            EditorHistoryItem(
              type: .move,
              pageIndex: dragPageIndex!,
              strokes: select.selectResult.strokes,
              images: select.selectResult.images,
              offset: .fromLTRB(
                moveOffset.dx,
                moveOffset.dy,
                moveOffset.dx,
                moveOffset.dy,
              ),
            ),
          );
        } else {
          shouldSave = false;
          select.onDragEnd(page.strokes, page.images);

          if (select.selectResult.isEmpty) {
            Select.currentSelect.unselect();
            _selectionPopupRect.value = null;
          } else {
            _updateSelectionPopupRect();
          }
        }
      } else if (currentTool is LaserPointer) {
        shouldSave = false;
        final newStroke = (currentTool as LaserPointer).onDragEnd(
          page.redrawStrokes,
          (Stroke stroke) {
            page.laserStrokes.remove(stroke);
          },
        );
        if (newStroke != null) page.laserStrokes.add(newStroke);
      }
    });

    if (shouldSave) autosaveAfterDelay();
  }

  void onInteractionEnd(ScaleEndDetails details) {
    // reset after 1ms to keep track of the same gesture only
    _lastSeenPointerCountTimer?.cancel();
    _lastSeenPointerCountTimer = Timer(const Duration(milliseconds: 10), () {
      lastSeenPointerCount = 0;
    });
  }

  void updatePointerData(PointerDeviceKind kind, double? pressure) {
    currentPointerKind = kind;
    currentPressure = pressure;
  }

  void onHovering() {
    isHovering = true;
  }

  void onHoveringEnd() {
    isHovering = false;
  }

  void onStylusButtonChanged(bool buttonIsPressed) {
    stylusButtonWasPressed |= buttonIsPressed;

    if (!isHovering) return;
    if (buttonIsPressed) {
      // button pressed while hovering, switch to Eraser
      if (currentTool is! Eraser) {
        currentTool = Eraser();
      }
    } else {
      // button was released while hovering, switch back to non-Eraser
      if (currentTool is Eraser) {
        currentTool = _lastNonEraserTool;
      }
    }

    if (mounted) setState(() {});
  }

  void onMoveImage(EditorImage image, Rect offset) {
    history.recordChange(
      EditorHistoryItem(
        type: .move,
        pageIndex: image.pageIndex,
        strokes: [],
        images: [image],
        offset: offset,
      ),
    );
    // setState to update undo button
    setState(() {});
    autosaveAfterDelay();
  }

  void onDeleteImage(EditorImage image) {
    history.recordChange(
      EditorHistoryItem(
        type: .erase,
        pageIndex: image.pageIndex,
        strokes: [],
        images: [image],
      ),
    );
    setState(() {
      coreInfo.pages[image.pageIndex].images.remove(image);
    });
    autosaveAfterDelay();
  }

  void listenToQuillChanges(QuillStruct quill, int pageIndex) {
    quill.changeSubscription?.cancel();
    quill.changeSubscription = quill.controller.changes.listen((event) {
      final undoRedoButtonsNeedUpdating = !history.canUndo || history.canRedo;
      _addQuillChangeToHistory(
        quill: quill,
        pageIndex: pageIndex,
        event: event,
      );
      createPage(pageIndex); // create empty last page
      if (undoRedoButtonsNeedUpdating) {
        setState(() {});
      }
      autosaveAfterDelay();
    });
    quill.focusNode.addListener(_onQuillFocusChange);
  }

  void _onQuillFocusChange() {
    for (final page in coreInfo.pages) {
      if (!page.quill.focusNode.hasFocus) continue;
      quillFocus.value = page.quill;
    }
  }

  void _addQuillChangeToHistory({
    required QuillStruct quill,
    required int pageIndex,
    required flutter_quill.DocChange event,
  }) {
    final eventWasUndo = quill.controller.hasRedo;
    if (eventWasUndo) return;

    // the change subscription sometimes fires multiple times for the same change
    // so compare the "before" of each change to merge them
    if (history.canUndo && !history.canRedo) {
      final lastChange = history.peekUndo();
      if (lastChange.type == .quillChange &&
          lastChange.pageIndex == pageIndex &&
          lastChange.quillChange!.before == event.before) {
        history.undo(); // remove the last change, to be replaced
      }
    }

    history.recordChange(
      EditorHistoryItem(
        type: .quillChange,
        pageIndex: pageIndex,
        strokes: const [],
        images: const [],
        quillChange: event,
      ),
    );
  }

  void _refreshCurrentNote() async {
    if (coreInfo.readOnlyReason != .watchingServer) return;
    if (!stows.loggedIn) return;

    final relativeFilePath = coreInfo.filePath;
    assert(relativeFilePath.isNotEmpty, 'Cannot refresh unnamed file');
    final syncFile = await SaberSyncFile.relative(
      relativeFilePath + Editor.extension,
    );

    final bestFile = await SaberSyncInterface.getBestFile(
      syncFile,
      onLocalFileNotFound: .local,
      onEqualFiles: .local,
      preferCache: false,
    );
    if (bestFile != .remote) return;

    late final StreamSubscription<SaberSyncFile> subscription;
    void listener(SaberSyncFile transferred) {
      if (transferred != syncFile) return;
      subscription.cancel();
      _loadCoreInfo(relativeFilePath)
          .then((_) => coreInfo.readOnlyReason = .watchingServer);
    }

    subscription = syncer.downloader.transferStream.listen(listener);

    await syncer.downloader.enqueue(syncFile: syncFile);
    syncer.downloader.bringToFront(syncFile);
  }

  void autosaveAfterDelay() {
    if (history.isCurrentStateSaved) return cancelAutosaveAndMarkSaved();

    late final void Function() callback;

    void startTimer() {
      _delayedSaveTimer?.cancel();
      if (stows.autosaveDelay.value < 0) return;
      _delayedSaveTimer = Timer(
        Duration(milliseconds: stows.autosaveDelay.value),
        callback,
      );
    }

    callback = () {
      if (Pen.currentStroke != null) {
        // don't save yet if the pen is currently drawing
        startTimer();
        return;
      }
      saveToFile();
    };

    savingState.value = .waitingToSave;
    startTimer();
  }

  void cancelAutosaveAndMarkSaved() {
    _delayedSaveTimer?.cancel();
    savingState.value = .saved;
    history.markLastChangeAsSaved();
  }

  Future<void> saveToFile() async {
    if (coreInfo.readOnly) return;

    switch (savingState.value) {
      case .saved:
        // avoid saving if nothing has changed
        return;
      case .saving:
        // avoid saving if already saving
        log.warning('saveToFile() called while already saving');
        return;
      case .waitingToSave:
        // continue
        _delayedSaveTimer?.cancel();
        savingState.value = .saving;
    }
    if (history.isCurrentStateSaved) return cancelAutosaveAndMarkSaved();

    await _renameFileNow();

    final filePath = coreInfo.filePath + Editor.extension;
    final Uint8List bson;
    final OrderedAssetCache assets;
    coreInfo.assetCache.allowRemovingAssets = false;
    try {
      (bson, assets) = coreInfo.saveToBinary(
        currentPageIndex: currentPageIndex,
      );
    } finally {
      coreInfo.assetCache.allowRemovingAssets = true;
    }
    try {
      await Future.wait([
        FileManager.writeFile(filePath, bson, awaitWrite: true),
        for (int i = 0; i < assets.length; ++i)
          assets
              .getBytes(i)
              .then(
                (bytes) => FileManager.writeFile(
                  '$filePath.$i',
                  bytes,
                  awaitWrite: true,
                ),
              ),
        FileManager.removeUnusedAssets(filePath, numAssets: assets.length),
      ]);
      savingState.value = .saved;
      history.markLastChangeAsSaved();
    } catch (e, st) {
      log.severe('Failed to save file: $e', e, st);
      savingState.value = .waitingToSave;
      if (kDebugMode) rethrow;
      return;
    }

    if (!mounted) return;
    final page = coreInfo.pages.first;
    final previewHeight = page.previewHeight(lineHeight: coreInfo.lineHeight);
    final thumbnailSize = Size(720, 720 * previewHeight / page.size.width);
    final thumbnail = await EditorExporter.screenshotPage(
      coreInfo: coreInfo,
      pageIndex: 0,
      rasterizeAllStrokes: true,
      targetSize: thumbnailSize,
      cropHeight: previewHeight,
      pixelRatio: 1,
    );
    final thumbnailPng = await thumbnail.toByteData(format: .png);
    thumbnail.dispose();
    await FileManager.writeFile(
      // Note that this ends with .sbn2.p
      '$filePath.p',
      thumbnailPng!.buffer.asUint8List(),
      awaitWrite: true,
    );
  }

  late final _filenameFormKey = GlobalKey<FormState>();
  late final filenameTextEditingController = TextEditingController();
  Timer? _renameTimer;
  void renameFile([String? _]) {
    _renameTimer?.cancel();
    _renameTimer = Timer(const Duration(seconds: 5), _renameFileNow);
  }

  Future<void> _renameFileNow() async {
    final newName = filenameTextEditingController.text.trim();
    if (newName == coreInfo.fileName) return;

    if (_filenameFormKey.currentState?.validate() ??
        _validateFilenameTextField(newName) == null) {
      coreInfo.filePath = await FileManager.moveFile(
        coreInfo.filePath + Editor.extension,
        newName.trim() + Editor.extension,
      );
      coreInfo.filePath = coreInfo.filePath.substring(
        0,
        coreInfo.filePath.lastIndexOf(Editor.extension),
      );
      needsNaming = false;
    }

    final actualName = coreInfo.fileName;
    if (actualName != newName) {
      // update text field if renamed differently
      filenameTextEditingController.value = filenameTextEditingController.value
          .copyWith(
            text: actualName,
            selection: TextSelection.fromPosition(
              TextPosition(offset: actualName.length),
            ),
            composing: TextRange.empty,
          );
    }
  }

  String? _validateFilenameTextField(String? newName) {
    if (newName == null) return null;
    return FileManager.validateFilename(newName);
  }

  void updateColorBar(Color color) {
    if (stows.recentColorsDontSavePresets.value) {
      if (ColorBar.colorPresets.any(
        (colorPreset) => colorPreset.color == color,
      )) {
        return;
      }
    }

    final newColorString = color.toARGB32().toString();

    // migrate from old pref format
    if (stows.recentColorsChronological.value.length !=
        stows.recentColorsPositioned.value.length) {
      log.info(
        'MIGRATING recentColors: ${stows.recentColorsChronological.value.length} vs ${stows.recentColorsPositioned.value.length}',
      );
      stows.recentColorsChronological.value = List.of(
        stows.recentColorsPositioned.value,
      );
    }

    if (stows.pinnedColors.value.contains(newColorString)) {
      // do nothing, color is already pinned
    } else if (stows.recentColorsPositioned.value.contains(newColorString)) {
      // if it's already a recent color, move it to the top
      stows.recentColorsChronological.value.remove(newColorString);
      stows.recentColorsChronological.value.add(newColorString);
      stows.recentColorsChronological.notifyListeners();
    } else {
      if (stows.recentColorsPositioned.value.length >=
          stows.recentColorsLength.value) {
        // if full, replace the oldest color with the new one
        final removedColorString = stows.recentColorsChronological.value
            .removeAt(0);
        stows.recentColorsChronological.value.add(newColorString);
        final int removedColorPosition = stows.recentColorsPositioned.value
            .indexOf(removedColorString);
        stows.recentColorsPositioned.value[removedColorPosition] =
            newColorString;
      } else {
        // if not full, add the new color to the end
        stows.recentColorsChronological.value.add(newColorString);
        stows.recentColorsPositioned.value.insert(0, newColorString);
      }
      stows.recentColorsChronological.notifyListeners();
      stows.recentColorsPositioned.notifyListeners();
    }
  }

  /// Prompts the user to pick photos from their device.
  /// Returns the number of photos picked.
  ///
  /// If [photoInfos] is provided, it will be used instead of the file picker.
  Future<int> _pickPhotos([
    List<_PhotoInfo>? photoInfos,
    _PasteTarget? target,
  ]) async {
    if (coreInfo.readOnly) return 0;

    final currentPageIndex = target?.pageIndex ?? this.currentPageIndex;

    photoInfos ??= await _pickPhotosWithFilePicker();
    if (photoInfos.isEmpty) return 0;

    // use the Select tool so that the user can move the new image
    currentTool = Select.currentSelect;

    final images = [
      for (final _PhotoInfo photoInfo in photoInfos)
        if (photoInfo.extension == '.svg')
          SvgEditorImage(
            id: coreInfo.nextImageId++,
            svgString: utf8.decode(photoInfo.bytes),
            svgFile: null,
            pageIndex: currentPageIndex,
            pageSize: coreInfo.pages[currentPageIndex].size,
            onMoveImage: onMoveImage,
            onDeleteImage: onDeleteImage,
            onMiscChange: autosaveAfterDelay,
            onLoad: () => setState(() {}),
            assetCache: coreInfo.assetCache,
          )
        else
          PngEditorImage(
            id: coreInfo.nextImageId++,
            extension: photoInfo.extension,
            imageProvider: MemoryImage(photoInfo.bytes),
            pageIndex: currentPageIndex,
            pageSize: coreInfo.pages[currentPageIndex].size,
            onMoveImage: onMoveImage,
            onDeleteImage: onDeleteImage,
            onMiscChange: autosaveAfterDelay,
            onLoad: () => setState(() {}),
            assetCache: coreInfo.assetCache,
          ),
    ];

    history.recordChange(
      EditorHistoryItem(
        type: .draw,
        pageIndex: currentPageIndex,
        strokes: [],
        images: images,
      ),
    );
    createPage(currentPageIndex);
    coreInfo.pages[currentPageIndex].images.addAll(images);
    if (target != null) {
      for (final image in images) {
        _centerImageOnceLoaded(image, target.position);
      }
    }
    autosaveAfterDelay();

    return images.length;
  }

  /// An image only gets its real size once it has loaded, so wait for that
  /// and then center it on [center] (keeping it inside its page).
  void _centerImageOnceLoaded(EditorImage image, Offset center) {
    void listener() {
      final size = image.dstRect.size;
      // not loaded yet (the real size is set when it loads)
      if (size.isEmpty) return;
      image.removeListener(listener);

      final pageSize = coreInfo.pages[image.pageIndex].size;
      final left = (center.dx - size.width / 2)
          .clamp(0.0, max(0.0, pageSize.width - size.width))
          .toDouble();
      final top = (center.dy - size.height / 2)
          .clamp(0.0, max(0.0, pageSize.height - size.height))
          .toDouble();
      image.dstRect = Offset(left, top) & size;
    }

    image.addListener(listener);
  }

  Future<List<_PhotoInfo>> _pickPhotosWithFilePicker() async {
    final List<PlatformFile> files = await FilePicker.pickFiles(
      type: FileType.custom,
      // Taken from
      // https://github.com/brendan-duncan/image/blob/main/doc/formats.md
      // (plus .svg)
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'tiff',
        'bmp',
        'tga',
        'ico',
        'pvrtc',
        'svg',
        'webp',
        'psd',
        'exr',
      ],
    );
    if (files.isEmpty) return const [];

    return Future.wait([
      for (final file in files)
        () async {
          final extension = p.extension(file.path ?? file.name);
          if (extension.isEmpty) return null;
          final bytes = await file.readAsBytes();
          return (bytes: bytes, extension: extension);
        }(),
    ]).then((list) => list.nonNulls.toList());
  }

  /// Prompts the user to pick a PDF to import.
  /// Returns whether a PDF was picked.
  Future<bool> importPdf() async {
    if (coreInfo.readOnly) return false;
    if (!Editor.canRasterPdf) return false;

    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null) return false;

    return importPdfFromFilePath(file.path!);
  }

  Future<bool> importPdfFromFilePath(String path) async {
    final pdfDocument = await coreInfo.assetCache.pdfDocumentCache.load(path);

    final emptyPage = coreInfo.pages.removeLast();
    assert(emptyPage.isEmpty);

    for (final pdfPage in pdfDocument.pages) {
      assert(pdfPage.pageNumber >= 1, 'pdfrx page numbers start at 1');

      // resize to [defaultWidth] to keep pen sizes consistent
      final pageSize = Size(
        EditorPage.defaultWidth,
        EditorPage.defaultWidth * pdfPage.height / pdfPage.width,
      );

      final page = EditorPage(
        size: pageSize,
        backgroundImage: PdfEditorImage(
          id: coreInfo.nextImageId++,
          pdfBytes: null,
          pdfFile: File(path),
          pdfPage: pdfPage.pageNumber - 1,
          pageIndex: coreInfo.pages.length,
          pageSize: pageSize,
          naturalSize: pdfPage.size,
          onMoveImage: onMoveImage,
          onDeleteImage: onDeleteImage,
          onMiscChange: autosaveAfterDelay,
          onLoad: () => setState(() {}),
          assetCache: coreInfo.assetCache,
        ),
      );
      coreInfo.pages.add(page);
      // TODO(adil192): Group multiple pages into one atomic change
      history.recordChange(
        EditorHistoryItem(
          type: .insertPage,
          pageIndex: coreInfo.pages.length - 1,
          strokes: const [],
          images: const [],
          page: page,
        ),
      );
    }

    coreInfo.pages.add(emptyPage);
    if (mounted) setState(() {});

    autosaveAfterDelay();

    return true;
  }

  Future paste({_PasteTarget? target}) async {
    if (_pasteCopiedSelection(target)) return;

    /// Maps image formats to their file extension.
    const Map<SimpleFileFormat, String> formats = {
      Formats.jpeg: '.jpeg',
      Formats.png: '.png',
      Formats.gif: '.gif',
      Formats.tiff: '.tiff',
      Formats.bmp: '.bmp',
      Formats.ico: '.ico',
      Formats.svg: '.svg',
      Formats.webp: '.webp',
    };

    final reader = await SystemClipboard.instance?.read();
    if (reader == null) return;

    final List<_PhotoInfo> photoInfos = [];
    final List<ReadProgress> progresses = [];

    for (final format in formats.keys) {
      if (!reader.canProvide(format)) continue;
      final progress = reader.getFile(format, (file) async {
        final stream = file.getStream();
        final List<int> bytes = [];
        await for (final chunk in stream) {
          bytes.addAll(chunk);
        }
        if (bytes.isEmpty) {
          log.warning('Pasted empty file: $file (${formats[format]})');
          return;
        }

        // On Android the clipboard's file name often has no extension,
        // so fall back to the one for the clipboard format.
        final fileName = file.fileName;
        final dot = fileName?.lastIndexOf('.') ?? -1;
        final String extension;
        if (fileName != null && dot > 0 && dot < fileName.length - 1) {
          extension = fileName.substring(dot);
        } else {
          extension = formats[format]!;
        }

        photoInfos.add((
          bytes: Uint8List.fromList(bytes),
          extension: extension,
        ));
      });
      if (progress != null) progresses.add(progress);
    }

    // Don't wait forever if the clipboard provider never finishes.
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (progresses.isNotEmpty && DateTime.now().isBefore(deadline)) {
      progresses.removeWhere((progress) => progress.fraction.value == 1);
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (photoInfos.isNotEmpty) {
      await _pickPhotos(photoInfos, target);
      return;
    }

    // No image on the clipboard: paste text into the current page's text.
    if (reader.canProvide(Formats.plainText)) {
      final text = await reader.readValue(Formats.plainText);
      if (text == null || text.isEmpty) return;
      _pasteText(text, target?.pageIndex);
    }
  }

  /// Inserts [text] into the current page's text layer at the cursor
  /// (or at the end if the cursor hasn't been placed yet).
  void _pasteText(String text, [int? pageIndex]) {
    if (coreInfo.readOnly) return;
    final controller =
        coreInfo.pages[pageIndex ?? currentPageIndex].quill.controller;
    final length = controller.document.length - 1; // excludes trailing '\n'
    final selection = controller.selection;
    final start = selection.isValid ? selection.start.clamp(0, length) : length;
    final end = selection.isValid ? selection.end.clamp(0, length) : length;
    setState(() {
      controller.replaceText(
        start,
        end - start,
        text,
        TextSelection.collapsed(offset: start + text.length),
      );
    });
    autosaveAfterDelay();
  }

  Future exportAsPdf(BuildContext context) async {
    final pdf = await EditorExporter.generatePdf(coreInfo, context);
    final bytes = await pdf.save();
    if (!context.mounted) return;
    await FileManager.exportFile(
      '${coreInfo.fileName}.pdf',
      bytes,
      context: context,
    );
  }

  /// Exports the current note as an SBA (Saber Archive) file.
  Future exportAsSba(BuildContext context) async {
    final sba = await coreInfo.saveToSba(currentPageIndex: currentPageIndex);
    if (!context.mounted) return;
    await FileManager.exportFile(
      '${coreInfo.fileName}.sba',
      Uint8List.fromList(sba),
      context: context,
    );
  }

  /// Exports the current page as a PNG image file.
  ///
  /// This captures the canvas natively via [EditorExporter.screenshotPage],
  /// which guarantees the correct background color and omits UI elements
  /// like selection bounds or the text cursor. It computes a dynamic [pixelRatio]
  /// to ensure high quality while averting Out-Of-Memory exceptions on large canvases.
  Future exportAsPng(BuildContext context) async {
    final page = coreInfo.pages[currentPageIndex];

    const maxRasterizableSize = 3000.0;
    var targetPixelRatio = maxRasterizableSize / page.size.longestSide;
    if (targetPixelRatio > 1) targetPixelRatio = 1;

    try {
      final image = await EditorExporter.screenshotPage(
        coreInfo: coreInfo,
        pageIndex: currentPageIndex,
        rasterizeAllStrokes: true,
        pixelRatio: targetPixelRatio,
      );
      final pngBytes = await image.toByteData(format: .png);
      image.dispose();

      if (!context.mounted) return;
      await FileManager.exportFile(
        '${coreInfo.fileName}_page_${currentPageIndex + 1}.png',
        pngBytes!.buffer.asUint8List(),
        isImage: true,
        context: context,
      );
    } catch (e, st) {
      log.severe('Failed to export PNG', e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);

    final Widget canvas = CanvasGestureDetector(
      key: _canvasGestureDetectorKey,
      filePath: coreInfo.filePath,
      isDrawGesture: isDrawGesture,
      onInteractionEnd: onInteractionEnd,
      onDrawStart: onDrawStart,
      onDrawUpdate: onDrawUpdate,
      onDrawEnd: onDrawEnd,
      onHovering: onHovering,
      onHoveringEnd: onHoveringEnd,
      onStylusButtonChanged: onStylusButtonChanged,
      updatePointerData: updatePointerData,
      undo: undo,
      redo: redo,
      pages: coreInfo.pages,
      initialPageIndex: coreInfo.initialPageIndex,
      pageBuilder: pageBuilder,
      isTextEditing: () => currentTool == Tool.textEditing,
      placeholderPageBuilder: (BuildContext context, int pageIndex) {
        return Canvas(
          path: coreInfo.filePath,
          page: coreInfo.pages[pageIndex],
          pageIndex: 0,
          textEditing: false,
          coreInfo: EditorCoreInfo.placeholder,
          currentStroke: null,
          currentStrokeDetectedShape: null,
          currentSelection: null,
          placeholder: true,
          setAsBackground: null,
          currentTool: currentTool,
          currentScale: double.minPositive,
        );
      },
      transformationController: _transformationController,
    );

    final readonlyBanner = ReadOnlyBanner(
      coreInfo.readOnlyReason,
      action: coreInfo.readOnlyReason == .versionTooNew
          ? showVersionTooNewDialog
          : null,
    );

    Widget buildToolbar(AxisDirection alignment) {
      final isToolbarVertical =
          alignment == AxisDirection.left || alignment == AxisDirection.right;
      return Collapsible(
        axis: isToolbarVertical
            ? CollapsibleAxis.horizontal
            : CollapsibleAxis.vertical,
        collapsed:
            DynamicMaterialApp.isFullscreen &&
            !stows.editorToolbarShowInFullscreen.value,
        maintainState: true,
        child: SafeArea(
          // The toolbar runs edge to edge, so don't inset it at the sides.
          left: isToolbarVertical && alignment == AxisDirection.left,
          right: isToolbarVertical && alignment == AxisDirection.right,
          bottom: alignment != AxisDirection.up,
          child: Toolbar(
            readOnly: coreInfo.readOnly,
            setTool: (tool) {
              if (tool is Eraser && currentTool is Eraser) {
                // setTool(Eraser) is a special case to toggle the eraser on/off
                tool = _lastNonEraserTool;
              }

              currentTool = tool;

              if (tool is Highlighter) {
                Highlighter.currentHighlighter = tool;
              } else if (tool is Pencil) {
                Pencil.currentPencil = tool;
              } else if (tool is Marker) {
                Marker.currentMarker = tool;
              } else if (tool is Pen) {
                Pen.currentPen = tool;
              }

              if (mounted) setState(() {});
            },
            currentTool: currentTool,
            setColor: (color) {
              setState(() {
                updateColorBar(color);

                if (currentTool is Highlighter) {
                  (currentTool as Highlighter).color = color.withAlpha(
                    Highlighter.alpha,
                  );
                } else if (currentTool is Pen) {
                  (currentTool as Pen).color = color;
                } else if (currentTool is Select) {
                  // Changes color of selected strokes
                  final select = currentTool as Select;
                  if (select.doneSelecting) {
                    final strokes = select.selectResult.strokes;
                    if (strokes.isNotEmpty) {
                      final colorChange = <Stroke, Change<Color>>{};
                      for (final stroke in strokes) {
                        colorChange[stroke] = Change(
                          previous: stroke.color,
                          current: color,
                        );
                        stroke.color = color;
                      }

                      history.recordChange(
                        EditorHistoryItem(
                          type: .changeColor,
                          pageIndex: select.selectResult.pageIndex,
                          strokes: strokes,
                          colorChange: colorChange,
                          images: [],
                        ),
                      );
                      autosaveAfterDelay();
                    }
                  }
                }
              });
            },
            quillFocus: quillFocus,
            textEditing: currentTool == Tool.textEditing,
            toggleTextEditing: () => setState(() {
              if (currentTool == Tool.textEditing) {
                currentTool = Pen.currentPen;
                for (final page in coreInfo.pages) {
                  // unselect text, but maintain cursor position
                  page.quill.controller.moveCursorToPosition(
                    page.quill.controller.selection.extentOffset,
                  );
                  page.quill.focusNode.unfocus();
                }
              } else {
                currentTool = Tool.textEditing;
                quillFocus.value = coreInfo.pages[currentPageIndex].quill
                  ..focusNode.requestFocus();
              }
            }),
            toggleFingerDrawing: () {
              stows.editorFingerDrawing.value =
                  !stows.editorFingerDrawing.value;
              lastSeenPointerCount = 0;
            },
            pickPhoto: _pickPhotos,
            pickSticker: _pickSticker,
            paste: paste,
            showExportOptions: showExportOptions,
            exportAsSba: exportAsSba,
            exportAsPdf: exportAsPdf,
            exportAsPng: exportAsPng,
          ),
        ),
      );
    }

    final isEraser = currentTool is Eraser;
    final Widget canvasArea = Stack(
      key: _canvasAreaKey,
      fit: StackFit.expand,
      children: [
        MouseRegion(
          cursor: isEraser ? SystemMouseCursors.precise : MouseCursor.defer,
          onExit: (_) => _eraserCircle.value = null,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onCanvasPointerDown,
            onPointerMove: _onCanvasPointerMove,
            onPointerUp: _onCanvasPointerEnd,
            onPointerCancel: _onCanvasPointerEnd,
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _updateEraserCircle,
              onPointerMove: _updateEraserCircle,
              onPointerHover: _updateEraserCircle,
              onPointerUp: _onEraserPointerUp,
              onPointerCancel: _onEraserPointerUp,
              child: canvas,
            ),
          ),
        ),
        if (isEraser)
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder(
                valueListenable: _eraserCircle,
                builder: (context, circle, _) => CustomPaint(
                  painter: EraserCursorPainter(
                    circle: circle,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
        if (DynamicMaterialApp.isFullscreen)
          Positioned.fill(
            child: SafeArea(
              minimum: const EdgeInsets.all(8),
              bottom: false,
              child: Align(
                alignment: Alignment.topRight,
                child: FloatingActionButton.small(
                  heroTag: null,
                  tooltip: t.editor.toolbar.fullscreen,
                  elevation: 2,
                  shape: const CircleBorder(),
                  backgroundColor: colorScheme.surfaceContainerHigh.withValues(
                    alpha: 0.92,
                  ),
                  foregroundColor: colorScheme.onSurfaceVariant,
                  onPressed: () => DynamicMaterialApp.setFullscreen(
                    false,
                    updateSystem: true,
                  ),
                  child: const Icon(Symbols.fullscreen_exit),
                ),
              ),
            ),
          ),
        ValueListenableBuilder<Rect?>(
          valueListenable: _selectionPopupRect,
          builder: (context, selectionRect, _) {
            if (selectionRect == null || coreInfo.readOnly) {
              return const SizedBox.shrink();
            }
            final tool = currentTool;
            final selectionHasImages =
                tool is Select &&
                tool.doneSelecting &&
                tool.selectResult.images.isNotEmpty;
            return SelectionPopup(
              selectionRect: selectionRect,
              duplicateSelection: _duplicateSelection,
              copySelection: _copySelection,
              deleteSelection: _deleteSelection,
              moveForward: selectionHasImages
                  ? () => _moveImagesLayer(true)
                  : null,
              moveBackward: selectionHasImages
                  ? () => _moveImagesLayer(false)
                  : null,
            );
          },
        ),
        ValueListenableBuilder<Rect?>(
          valueListenable: _selectionPopupRect,
          builder: (context, selectionRect, _) {
            if (selectionRect == null ||
                coreInfo.readOnly ||
                currentTool is! Select) {
              return const SizedBox.shrink();
            }
            return _buildSelectionHandles(selectionRect, colorScheme);
          },
        ),
        ValueListenableBuilder<Offset?>(
          valueListenable: _pasteMenuPosition,
          builder: (context, position, _) {
            if (position == null || coreInfo.readOnly) {
              return const SizedBox.shrink();
            }
            return CustomSingleChildLayout(
              delegate: _PasteMenuLayoutDelegate(position),
              child: SamsungPanel(
                borderRadius: 14,
                padding: const EdgeInsets.all(6),
                child: TextButton(
                  onPressed: () {
                    final target = _pasteTarget;
                    _pasteMenuPosition.value = null;
                    _pasteTarget = null;
                    paste(target: target);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.onSurface,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(10)),
                    ),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  child: const Text('Paste'),
                ),
              ),
            );
          },
        ),
      ],
    );

    // The toolbar edge is drag-controlled now: rebuild the layout
    // whenever the persisted alignment changes.
    final Widget body = ValueListenableBuilder(
      valueListenable: stows.editorToolbarAlignment,
      builder: (context, alignment, _) {
        final isToolbarVertical =
            alignment == AxisDirection.left || alignment == AxisDirection.right;
        if (isToolbarVertical) {
          return Row(
            textDirection: alignment == AxisDirection.left ? .ltr : .rtl,
            children: [
              buildToolbar(alignment),
              Expanded(
                child: Column(
                  children: [
                    Expanded(child: canvasArea),
                    readonlyBanner,
                  ],
                ),
              ),
            ],
          );
        } else {
          return Column(
            verticalDirection: alignment == AxisDirection.up
                ? VerticalDirection.up
                : VerticalDirection.down,
            children: [
              Expanded(child: canvasArea),
              buildToolbar(alignment),
              readonlyBanner,
            ],
          );
        }
      },
    );

    return ValueListenableBuilder(
      valueListenable: savingState,
      builder: (context, savingState, child) {
        // don't allow user to go back until saving is done
        return PopScope(
          canPop: savingState == .saved && !DynamicMaterialApp.isFullscreen,
          onPopInvokedWithResult: (didPop, _) {
            // In fullscreen, back leaves fullscreen instead of the note.
            if (!didPop && DynamicMaterialApp.isFullscreen) {
              DynamicMaterialApp.setFullscreen(false, updateSystem: true);
              return;
            }
            switch (savingState) {
              case .waitingToSave:
                assert(!didPop);
                saveToFile(); // trigger save now
                snackBarNeedsToSaveBeforeExiting();
              case .saving:
                assert(!didPop);
                snackBarNeedsToSaveBeforeExiting();
              case .saved:
                break;
            }
          },
          child: child!,
        );
      },
      child: Scaffold(
        appBar: DynamicMaterialApp.isFullscreen
            ? null
            : AppBar(
                toolbarHeight: kToolbarHeight,
                // Samsung Notes style: flat top bar, no elevation/shadow.
                elevation: 0,
                scrolledUnderElevation: 0,
                surfaceTintColor: Colors.transparent,
                shadowColor: Colors.transparent,
                title: widget.customTitle != null
                    ? Text(
                        widget.customTitle!,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                    : Form(
                        key: _filenameFormKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: TextFormField(
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                          ),
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                          controller: filenameTextEditingController,
                          onChanged: renameFile,
                          autofocus: needsNaming,
                          validator: _validateFilenameTextField,
                        ),
                      ),
                leading: SaveIndicator(
                  savingState: savingState,
                  triggerSave: saveToFile,
                ),
                actions: [
                  IconButton(
                    style: IconButton.styleFrom(
                      fixedSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    icon: const AdaptiveIcon(
                      icon: Icons.undo,
                      cupertinoIcon: CupertinoIcons.arrow_uturn_left,
                    ),
                    tooltip: t.editor.toolbar.undo,
                    onPressed: (!coreInfo.readOnly && history.canUndo)
                        ? undo
                        : null,
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      fixedSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    icon: const AdaptiveIcon(
                      icon: Icons.redo,
                      cupertinoIcon: CupertinoIcons.arrow_uturn_right,
                    ),
                    tooltip: t.editor.toolbar.redo,
                    onPressed: (!coreInfo.readOnly && history.canRedo)
                        ? redo
                        : null,
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      fixedSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    icon: const AdaptiveIcon(
                      icon: Icons.fullscreen,
                      cupertinoIcon: CupertinoIcons.fullscreen,
                    ),
                    tooltip: t.editor.toolbar.fullscreen,
                    onPressed: !coreInfo.readOnly
                        ? () => DynamicMaterialApp.setFullscreen(
                            !DynamicMaterialApp.isFullscreen,
                            updateSystem: true,
                          )
                        : null,
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      fixedSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    icon: const AdaptiveIcon(
                      icon: Icons.insert_page_break,
                      cupertinoIcon: CupertinoIcons.add,
                    ),
                    tooltip: t.editor.menu.insertPage,
                    onPressed: () => setState(() {
                      final currentPageIndex = this.currentPageIndex;
                      insertPageAfter(currentPageIndex);
                      CanvasGestureDetector.scrollToPage(
                        pageIndex: currentPageIndex + 1,
                        pages: coreInfo.pages,
                        screenWidth: MediaQuery.sizeOf(context).width,
                        transformationController: _transformationController,
                      );
                    }),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      fixedSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    icon: const AdaptiveIcon(
                      icon: Icons.grid_view,
                      cupertinoIcon: CupertinoIcons.rectangle_grid_2x2,
                    ),
                    tooltip: t.editor.pages,
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AdaptiveAlertDialog(
                          title: Text(t.editor.pages),
                          content: pageManager(context),
                          actions: const [],
                        ),
                      );
                    },
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      fixedSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    icon: const AdaptiveIcon(
                      icon: Icons.more_vert,
                      cupertinoIcon: CupertinoIcons.ellipsis_vertical,
                    ),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (context) => bottomSheet(context),
                        isScrollControlled: true,
                        showDragHandle: true,
                        backgroundColor: colorScheme.surface,
                        constraints: const BoxConstraints(maxWidth: 500),
                      );
                    },
                  ),
                ],
              ),
        body: body,
      ),
    );
  }

  void snackBarNeedsToSaveBeforeExiting() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(t.editor.needsToSaveBeforeExiting)));
  }

  Widget bottomSheet(BuildContext context) {
    final Brightness brightness = Theme.brightnessOf(context);
    final invert = stows.editorAutoInvert.value && brightness == .dark;
    final int currentPageIndex = this.currentPageIndex;

    return EditorBottomSheet(
      invert: invert,
      canExport: !coreInfo.readOnly,
      openExport: () => showExportOptions.value = true,
      coreInfo: coreInfo,
      currentPageIndex: currentPageIndex,
      setBackgroundPattern: (pattern) => setState(() {
        if (coreInfo.readOnly) return;
        final previous = coreInfo.backgroundPattern;
        coreInfo.backgroundPattern = pattern;
        stows.lastBackgroundPattern.value = pattern;
        history.recordChange(
          EditorHistoryItem(
            type: .backgroundPattern,
            pageIndex: currentPageIndex,
            backgroundPatternChange: Change(
              previous: previous,
              current: pattern,
            ),
            strokes: [],
            images: [],
          ),
        );
        autosaveAfterDelay();
      }),
      setLineHeight: (lineHeight) => setState(() {
        if (coreInfo.readOnly) return;
        coreInfo.lineHeight = lineHeight;
        stows.lastLineHeight.value = lineHeight;
        autosaveAfterDelay();
      }),
      setLineThickness: (lineThickness) => setState(() {
        if (coreInfo.readOnly) return;
        coreInfo.lineThickness = lineThickness;
        stows.lastLineThickness.value = lineThickness;
        autosaveAfterDelay();
      }),
      removeBackgroundImage: () => setState(() {
        if (coreInfo.readOnly) return;

        final page = coreInfo.pages[currentPageIndex];
        if (page.backgroundImage == null) return;
        page.images.add(page.backgroundImage!);
        page.backgroundImage = null;

        autosaveAfterDelay();
      }),
      redrawImage: () => setState(() {}),
      clearPage: () {
        clearPage(currentPageIndex);
      },
      clearAllPages: clearAllPages,
      redrawAndSave: () => setState(() {
        if (coreInfo.readOnly) return;
        autosaveAfterDelay();
      }),
      pickPhotos: _pickPhotos,
      importPdf: importPdf,
      canRasterPdf: Editor.canRasterPdf,
      getIsWatchingServer: () => _watchServerTimer?.isActive ?? false,
      setIsWatchingServer: (bool watch) {
        if (watch) {
          _watchServerTimer ??= Timer.periodic(
            const Duration(seconds: 5),
            (_) => _refreshCurrentNote(),
          );
          if (coreInfo.readOnlyReason != .watchingServer) {
            assert(coreInfo.readOnlyReason == null);
            coreInfo.readOnlyReason = .watchingServer;
            if (mounted) setState(() {});
          }
        } else {
          _watchServerTimer?.cancel();
          _watchServerTimer = null;
          if (coreInfo.readOnlyReason == .watchingServer) {
            coreInfo.readOnlyReason = null;
            if (mounted) setState(() {});
          }
        }
      },
    );
  }

  Widget pageBuilder(BuildContext context, int pageIndex) {
    final page = coreInfo.pages[pageIndex];
    final currentStroke = Pen.currentStroke?.pageIndex == pageIndex
        ? Pen.currentStroke
        : null;
    return Canvas(
      path: coreInfo.filePath,
      page: page,
      pageIndex: pageIndex,
      textEditing: currentTool == Tool.textEditing,
      coreInfo: coreInfo,
      currentStroke: currentStroke,
      currentStrokeDetectedShape:
          currentTool is ShapePen && currentStroke != null
          ? ShapePen.detectedShape
          : null,
      currentSelection: () {
        if (currentTool is! Select) return null;
        final selectResult = (currentTool as Select).selectResult;
        if (selectResult.pageIndex != pageIndex) return null;
        return selectResult;
      }(),
      setAsBackground: (EditorImage image) {
        if (page.backgroundImage != null) {
          // restore previous background image as normal image
          page.images.add(page.backgroundImage!);
        }
        page.images.remove(image);
        page.backgroundImage = image;

        CanvasImage.activeListener
            .notifyListenersPlease(); // un-select active image

        autosaveAfterDelay();
        setState(() {});
      },
      currentTool: currentTool,
      currentScale: _transformationController.value.approxScale,
    );
  }

  Widget pageManager(BuildContext context) {
    return EditorPageManager(
      coreInfo: coreInfo,
      currentPageIndex: currentPageIndex,
      redrawAndSave: () => setState(() {
        if (coreInfo.readOnly) return;
        autosaveAfterDelay();
      }),
      insertPageAfter: insertPageAfter,
      duplicatePage: (int pageIndex) => setState(() {
        if (coreInfo.readOnly) return;
        final page = coreInfo.pages[pageIndex];
        final newPage = page.copyWith(
          strokes: page.strokes
              .map((stroke) => stroke.copy()..pageIndex += 1)
              .toList(),
          images: page.images
              .map((image) => image.copy()..pageIndex += 1)
              .toList(),
          quill: QuillStruct(
            controller: flutter_quill.QuillController(
              document: flutter_quill.Document.fromDelta(
                page.quill.controller.document.toDelta(),
              ),
              selection: const TextSelection.collapsed(offset: 0),
            ),
            focusNode: FocusNode(debugLabel: 'Quill Focus Node'),
          ),
          backgroundImage: page.backgroundImage?.copy()?..pageIndex += 1,
        );
        coreInfo.pages.insert(pageIndex + 1, newPage);
        listenToQuillChanges(newPage.quill, pageIndex + 1);
        history.recordChange(
          EditorHistoryItem(
            type: .insertPage,
            pageIndex: pageIndex,
            strokes: const [],
            images: const [],
            page: newPage,
          ),
        );
        autosaveAfterDelay();
      }),
      clearPage: clearPage,
      deletePage: (int pageIndex) => setState(() {
        if (coreInfo.readOnly) return;
        final page = coreInfo.pages.removeAt(pageIndex);
        createPage(pageIndex - 1);
        history.recordChange(
          EditorHistoryItem(
            type: .deletePage,
            pageIndex: pageIndex,
            strokes: const [],
            images: const [],
            page: page,
          ),
        );
        autosaveAfterDelay();
      }),
      transformationController: _transformationController,
    );
  }

  void insertPageAfter(int pageIndex) => setState(() {
    if (coreInfo.readOnly) return;
    final page = EditorPage();
    coreInfo.pages.insert(pageIndex + 1, page);
    listenToQuillChanges(page.quill, pageIndex + 1);
    history.recordChange(
      EditorHistoryItem(
        type: .insertPage,
        pageIndex: pageIndex + 1,
        strokes: const [],
        images: const [],
        page: page,
      ),
    );
    autosaveAfterDelay();
  });

  void clearPage(int pageIndex) {
    if (coreInfo.readOnly) return;
    final page = coreInfo.pages[pageIndex];
    setState(() {
      final removedStrokes = page.strokes.toList();
      final removedImages = page.images.toList();
      page.strokes.clear();
      page.images.clear();
      removeExcessPages();
      history.recordChange(
        EditorHistoryItem(
          type: .erase,
          pageIndex: pageIndex,
          strokes: removedStrokes,
          images: removedImages,
        ),
      );
      autosaveAfterDelay();
    });
  }

  void clearAllPages() {
    if (coreInfo.readOnly) return;
    setState(() {
      final removedStrokes = <Stroke>[];
      final removedImages = <EditorImage>[];
      for (final page in coreInfo.pages) {
        removedStrokes.addAll(page.strokes);
        removedImages.addAll(page.images);
        page.strokes.clear();
        page.images.clear();
      }
      removeExcessPages();
      history.recordChange(
        EditorHistoryItem(
          type: .erase,
          pageIndex: 0,
          strokes: removedStrokes,
          images: removedImages,
        ),
      );
    });
    autosaveAfterDelay();
  }

  Future<void> showVersionTooNewDialog() async {
    final disableReadOnly =
        await showDialog(
          context: context,
          builder: (context) => AdaptiveAlertDialog(
            title: Text(t.editor.versionTooNew.title),
            content: Text(t.editor.versionTooNew.subtitle),
            actions: [
              CupertinoDialogAction(
                child: Text(t.common.cancel),
                onPressed: () => Navigator.pop(context, false),
              ),
              CupertinoDialogAction(
                child: Text(t.editor.versionTooNew.allowEditing),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted) return;
    if (!disableReadOnly) return;

    if (coreInfo.readOnlyReason == .versionTooNew) {
      coreInfo.readOnlyReason = null;
      if (mounted) setState(() {});
    }
  }

  late int _lastCurrentPageIndex = coreInfo.initialPageIndex ?? 0;

  /// The index of the page that is currently centered on screen.
  int get currentPageIndex {
    if (!mounted) return _lastCurrentPageIndex;

    final screenWidth = MediaQuery.sizeOf(context).width;

    return _lastCurrentPageIndex = getPageIndexFromScrollPosition(
      scrollY: -scrollY,
      screenWidth: screenWidth,
      pages: coreInfo.pages,
    );
  }

  @visibleForTesting
  static int getPageIndexFromScrollPosition({
    required double scrollY,
    required double screenWidth,
    required List<EditorPage> pages,
  }) {
    for (int pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      final bottomOfPage = CanvasGestureDetector.getTopOfPage(
        pageIndex: pageIndex + 1, // top of next page
        pages: pages,
        screenWidth: screenWidth,
      );

      if (scrollY < bottomOfPage) {
        return pageIndex;
      }
    }
    // below the last page
    return pages.length - 1;
  }

  @override
  void dispose() {
    unawaited(_cleanUpAsync());

    DynamicMaterialApp.removeFullscreenListener(_setState);

    _delayedSaveTimer?.cancel();
    _watchServerTimer?.cancel();
    _lastSeenPointerCountTimer?.cancel();

    _removeKeybindings();

    // manually save pen properties since the listeners don't fire if a property is changed
    stows.lastFountainPenOptions.notifyListeners();
    stows.lastBallpointPenOptions.notifyListeners();
    stows.lastHighlighterOptions.notifyListeners();
    stows.lastPencilOptions.notifyListeners();
    stows.lastShapePenOptions.notifyListeners();

    super.dispose();
    showExportOptions.dispose();
    _eraserCircle.dispose();
    _selectionPopupRect.dispose();
    _longPressTimer?.cancel();
    _pasteMenuPosition.dispose();
  }

  Future<void> _cleanUpAsync() async {
    try {
      if (_renameTimer?.isActive ?? false) {
        _renameTimer!.cancel();
        await _renameFileNow();
        filenameTextEditingController.dispose();
      }
      await saveToFile();
    } finally {
      coreInfo.dispose();
    }
  }
}

/// Places the long-press "Paste" button just above the pressed point
/// (or below it if there isn't room), never off the sides.
class _PasteMenuLayoutDelegate extends SingleChildLayoutDelegate {
  const _PasteMenuLayoutDelegate(this.anchor);

  final Offset anchor;

  static const _gap = 28.0;
  static const _margin = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = size.width - childSize.width - _margin;
    final x = (anchor.dx - childSize.width / 2)
        .clamp(_margin, maxX < _margin ? _margin : maxX)
        .toDouble();
    final above = anchor.dy - _gap - childSize.height;
    final y = above >= _margin ? above : anchor.dy + _gap;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PasteMenuLayoutDelegate oldDelegate) =>
      oldDelegate.anchor != anchor;
}
