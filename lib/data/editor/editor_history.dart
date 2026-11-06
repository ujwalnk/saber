import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/editor/page.dart';
import 'package:sbn/canvas_background_pattern.dart';
import 'package:sbn/change.dart';

class EditorHistory {
  static const maxHistoryLength = 100;

  /// A stack of the changes that have been made in the editor.
  /// The last element is used when undoing.
  ///
  /// See also: [_future]
  final List<Historic> _past = [];

  /// A stack of the changes that have been undone in the editor.
  /// The last element is used when redoing.
  ///
  /// See also: [_past]
  final List<Historic> _future = [];

  /// The last saved state in the history.
  /// This is used to determine whether an autosave is needed.
  Historic? _lastSaved;

  /// True if redo is possible.
  /// We don't directly clear [_future] because we sometimes need to
  /// reject strokes (i.e. accidental strokes when zooming).
  var _isRedoPossible = false;

  /// Removes an element from the [_past] stack,
  /// adds it to the [_future] stack, and returns it.
  ///
  /// Please check [canUndo] first: this method will
  /// throw an exception if there is nothing to undo.
  Historic undo() {
    if (_past.isEmpty) throw Exception('Nothing to undo');
    final item = _past.removeLast();
    _future.add(item);
    return item;
  }

  /// Removes an element from the [_future] stack,
  /// adds it to the [_past] stack, and returns it.
  ///
  /// Please check [canRedo] first: this method will
  /// throw an exception if there is nothing to redo.
  Historic redo() {
    if (_future.isEmpty) throw Exception('Nothing to redo');
    final item = _future.removeLast();
    _past.add(item);
    return item;
  }

  /// Allows you to see the last item in the [_past] stack
  /// without removing it.
  ///
  /// Please check [canUndo] first: this method will
  /// throw an exception if there is nothing to undo.
  Historic peekUndo() {
    if (_past.isEmpty) throw Exception('Nothing to undo');
    return _past.last;
  }

  /// Allows you to see the last item in the [_future] stack
  /// without removing it.
  ///
  /// Please check [canRedo] first: this method will
  /// throw an exception if there is nothing to redo.
  Historic peekRedo() {
    if (_future.isEmpty) throw Exception('Nothing to redo');
    return _future.last;
  }

  /// Adds an item to the [_past] stack.
  void recordChange(Historic item) {
    assert(
      item is! HistoricQuillReverseChange,
      'HistoricQuillReverseChange is just a hack to make undoing quill changes easier. It should just be recorded as a quill change.',
    );

    _past.add(item);
    if (_past.length > maxHistoryLength) _past.removeAt(0);
    _isRedoPossible = false;
  }

  /// Marks the last change as saved to disk.
  /// This does not modify the history stacks, but allows us to know
  /// whether the current state is saved or not.
  void markLastChangeAsSaved() {
    _lastSaved = _past.lastOrNull;
  }

  /// Whether the current state is saved to disk.
  ///
  /// Note that this explicitly checks the last change in the history,
  /// not whether _past is empty. This is because _past items can be discarded
  /// if the history exceeds [maxHistoryLength].
  bool get isCurrentStateSaved {
    return _past.lastOrNull == _lastSaved;
  }

  /// Removes the last history item due to a rejected stroke.
  /// This does essentially the opposite of [recordChange].
  Historic? removeAccidentalStroke() {
    _isRedoPossible = true;
    if (_past.isEmpty) return null;
    assert(
      _past.last is HistoricAdd,
      'Accidental stroke is not a draw, found ${_past.last}',
    );
    assert(
      (_past.last as HistoricAdd).strokes.length == 1,
      'Accidental strokes should be single-stroke',
    );
    assert(
      (_past.last as HistoricAdd).images.isEmpty,
      'Accidental strokes should not contain images',
    );
    return _past.removeLast();
  }

  /// Returns true if there is something to undo.
  bool get canUndo {
    return _past.isNotEmpty;
  }

  /// Returns true if there is something to redo.
  bool get canRedo {
    return _isRedoPossible && _future.isNotEmpty;
  }

  set canRedo(bool isRedoPossible) {
    _isRedoPossible = isRedoPossible;
  }

  void clearRedo() {
    _future.clear();
  }
}

/// The page's images in drawing order, and whether each is above the strokes.
typedef ImageLayers = List<({EditorImage image, bool above})>;

/// A history item representing a change in the editor state.
///
/// Undoing an item means applying the inverse of the change it records.
/// Redoing means undoing [reverse].
sealed class Historic {
  @protected
  const new();

  /// The reverse of this change,
  /// e.g. switching between [HistoricAdd] and [HistoricDelete].
  Historic reverse();
}

/// Strokes or images were drawn/added.
/// Undoing removes them.
class HistoricAdd extends Historic {
  const new({required this.strokes, required this.images});

  final List<Stroke> strokes;
  final List<EditorImage> images;

  @override
  HistoricDelete reverse() => HistoricDelete(strokes: strokes, images: images);
}

/// Strokes or images were erased/deleted. Undoing puts them back.
///
/// If a stroke was only partly erased, [replacementStrokes] holds the pieces
/// that took the place of [strokes]. Undoing puts [strokes] back and removes
/// these.
class HistoricDelete extends Historic {
  const new({
    required this.strokes,
    required this.images,
    this.replacementStrokes = const [],
  });

  final List<Stroke> strokes;
  final List<EditorImage> images;
  final List<Stroke> replacementStrokes;

  @override
  Historic reverse() {
    if (replacementStrokes.isEmpty) {
      return HistoricAdd(strokes: strokes, images: images);
    }
    // Redoing a partial erase brings the pieces back and removes the
    // originals, which is the undo of this swapped item.
    return HistoricDelete(
      strokes: replacementStrokes,
      images: images,
      replacementStrokes: strokes,
    );
  }
}

/// Strokes or images were moved by [offset].
class HistoricMove extends Historic {
  const new({
    required this.pageIndex,
    required this.strokes,
    required this.images,
    required this.offset,
  });

  final int pageIndex;
  final List<Stroke> strokes;
  final List<EditorImage> images;
  final Rect offset;

  @override
  HistoricMove reverse() => HistoricMove(
    pageIndex: pageIndex,
    strokes: strokes,
    images: images,
    offset: .fromLTRB(-offset.left, -offset.top, -offset.right, -offset.bottom),
  );
}

/// A [page] was inserted at [pageIndex]. Undoing removes it.
class HistoricPageInsert extends Historic {
  const new({required this.pageIndex, required this.page});

  final int pageIndex;
  final EditorPage page;

  @override
  HistoricPageDelete reverse() =>
      HistoricPageDelete(pageIndex: pageIndex, page: page);
}

/// The [page] at [pageIndex] was deleted. Undoing puts it back.
class HistoricPageDelete extends Historic {
  const new({required this.pageIndex, required this.page});

  final int pageIndex;
  final EditorPage page;

  @override
  HistoricPageInsert reverse() =>
      HistoricPageInsert(pageIndex: pageIndex, page: page);
}

/// A change in the Quill text editor. Undoing calls Quill's undo.
class HistoricQuillChange extends Historic {
  const new({
    required this.pageIndex,
    required this.quillChange,
  });

  final int pageIndex;
  final DocChange quillChange;

  @override
  HistoricQuillReverseChange reverse() =>
      HistoricQuillReverseChange(pageIndex: pageIndex, quillChange: quillChange);
}

/// A reversed change in the Quill text editor. Undoing calls Quill's redo.
///
/// The [quillChange] is equivalent to the non-reversed class' [quillChange].
/// This class is just a hack to make interfacing with Quill easier,
/// and is never recorded in the history.
class HistoricQuillReverseChange extends Historic {
  const new({
    required this.pageIndex,
    required this.quillChange,
  });

  final int pageIndex;
  final DocChange quillChange;

  @override
  HistoricQuillChange reverse() =>
      HistoricQuillChange(pageIndex: pageIndex, quillChange: quillChange);
}

/// Some strokes' colors were changed.
class HistoricColorChange extends Historic {
  const new({
    required this.pageIndex,
    required this.colorChanges,
  });

  final int pageIndex;
  final Map<Stroke, Change<Color>> colorChanges;

  @override
  HistoricColorChange reverse() => HistoricColorChange(
    pageIndex: pageIndex,
    colorChanges: colorChanges.map(
      (key, value) => MapEntry(key, value.reverse()),
    ),
  );
}

/// A page's background pattern was changed.
class HistoricBackgroundPatternChange extends Historic {
  const new({
    required this.pageIndex,
    required this.change,
  });

  final int pageIndex;
  final Change<CanvasBackgroundPattern> change;

  @override
  HistoricBackgroundPatternChange reverse() =>
      HistoricBackgroundPatternChange(pageIndex: pageIndex, change: change.reverse());
}

/// The order of a page's images relative to the strokes was changed.
class HistoricLayerChange extends Historic {
  const new({required this.pageIndex, required this.change});

  final int pageIndex;
  final Change<ImageLayers> change;

  @override
  HistoricLayerChange reverse() =>
      HistoricLayerChange(pageIndex: pageIndex, change: change.reverse());
}
