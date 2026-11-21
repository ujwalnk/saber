import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/webdav/webdav_client.dart';

enum WebDavSyncState { idle, syncing, done, error }

class WebDavSyncStatus {
  const new(this.state, [this.message = '', this.time]);

  final WebDavSyncState state;
  final String message;
  final DateTime? time;
}

class _LocalFile {
  const new(this.file, this.modified, this.size);
  final File file;
  final int modified; // milliseconds since epoch
  final int size;
}

enum _Action { nothing, upload, download, deleteLocal, deleteRemote }

enum _Side { local, remote }

/// Two-way sync between the notes folder and a WebDAV folder.
///
/// Notes are stored as they are on the device (not encrypted), in the same
/// folder structure, so any WebDAV server works, and several devices can
/// share one folder.
///
/// What was in sync last time is remembered ([Stows.webdavState]): that is
/// how a change on one side is told apart from a deletion on the other.
///
/// If a file was changed on two devices before they synced, the version
/// that was edited last is kept, and the other version is saved next to it
/// as "name (conflict …)", so nothing is lost. When was a file really
/// edited? The server only knows when it was uploaded, so every device
/// records the time of its edit in [_editTimesPath] on the server.
class WebDavSync {
  new _();
  static final instance = WebDavSync._();

  static final log = Logger('WebDavSync');

  /// A hidden file on the server: path -> when the file was last edited
  /// (milliseconds since epoch, on the device that edited it).
  static const _editTimesPath = '/.saber-edit-times.json';

  final status = ValueNotifier(const WebDavSyncStatus(.idle));

  Timer? _debounce;
  var _running = false;
  var _runAgain = false;
  var _started = false;

  bool get isConfigured =>
      stows.webdavEnabled.value &&
      stows.webdavUrl.value.trim().isNotEmpty &&
      stows.webdavUsername.value.trim().isNotEmpty;

  /// Starts syncing now, then every few minutes, and whenever the settings
  /// change or a note is saved (see [scheduleSync]).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await Future.wait([
      stows.webdavEnabled.waitUntilRead(),
      stows.webdavUrl.waitUntilRead(),
      stows.webdavUsername.waitUntilRead(),
      stows.webdavPassword.waitUntilRead(),
      stows.webdavState.waitUntilRead(),
    ]);

    for (final stow in [
      stows.webdavEnabled,
      stows.webdavUrl,
      stows.webdavUsername,
      stows.webdavPassword,
    ]) {
      stow.addListener(() => scheduleSync(const Duration(seconds: 3)));
    }
    Timer.periodic(const Duration(minutes: 3), (_) => syncNow());
    if (isConfigured) unawaited(syncNow());
  }

  /// Syncs soon, after things have settled down (e.g. while typing or
  /// writing). Does nothing if WebDAV isn't set up.
  void scheduleSync([Duration delay = const Duration(seconds: 5)]) {
    if (!isConfigured) return;
    _debounce?.cancel();
    _debounce = Timer(delay, syncNow);
  }

  Future<void> syncNow() async {
    if (!isConfigured) return;
    if (_running) {
      _runAgain = true;
      return;
    }
    _running = true;
    _debounce?.cancel();
    status.value = const WebDavSyncStatus(.syncing, 'Syncing…');
    try {
      final summary = await _run();
      status.value = WebDavSyncStatus(.done, summary, DateTime.now());
    } catch (e, st) {
      log.warning('WebDAV sync failed: $e', e, st);
      final message = switch (e) {
        SocketException() => 'Could not reach the server',
        TimeoutException() => 'The server took too long to answer',
        _ => e.toString(),
      };
      status.value = WebDavSyncStatus(.error, message, DateTime.now());
    } finally {
      _running = false;
      if (_runAgain) {
        _runAgain = false;
        scheduleSync(const Duration(seconds: 2));
      }
    }
  }

  // --- The sync itself ------------------------------------------------------

  Future<String> _run() async {
    final client = WebDavClient(
      url: stows.webdavUrl.value,
      username: stows.webdavUsername.value,
      password: stows.webdavPassword.value,
    );
    try {
      await client.check();

      // What was in sync last time. Forgotten if the location changed, so
      // that a new (empty) folder can't look like "everything was deleted".
      final location = WebDavClient.normalizeLocation(stows.webdavUrl.value);
      final saved = _loadState();
      final known = saved.location == location
          ? saved.files
          : <String, Map<String, dynamic>>{};

      final remote = {
        for (final file in await client.listAll())
          if (file.path != _editTimesPath) file.path: file,
      };
      final local = await _scanLocal();
      final editTimes = await _readEditTimes(client);

      // The server returned nothing although files were in sync before:
      // don't take that as "everything was deleted".
      final remoteLooksWiped = remote.isEmpty && known.isNotEmpty;

      final paths = {...local.keys, ...remote.keys, ...known.keys}.toList()
        // attachments and previews first, the note itself last
        ..sort((a, b) {
          final aNote = a.endsWith('.sbn2') ? 1 : 0;
          final bNote = b.endsWith('.sbn2') ? 1 : 0;
          return aNote != bNote ? aNote - bNote : a.compareTo(b);
        });

      bool localChanged(String path) {
        final l = local[path], s = known[path];
        return l != null && (s == null || s['lm'] != l.modified);
      }

      bool remoteChanged(String path) {
        final r = remote[path], s = known[path];
        return r != null && (s == null || s['rs'] != r.signature);
      }

      /// When the server's copy was last edited (see the class comment).
      int? remoteEdit(String path) =>
          editTimes[path] ?? remote[path]?.lastModified?.millisecondsSinceEpoch;

      // --- Find conflicts: changed on both sides since the last sync ---
      final conflicts = <String>{
        for (final path in paths)
          if (local[path] != null &&
              remote[path] != null &&
              localChanged(path) &&
              remoteChanged(path) &&
              // never synced before, but the same size: assume it's the same
              (known[path] != null ||
                  local[path]!.size != remote[path]!.size))
            path,
      };

      // A note and its attachments are resolved together.
      final conflictedGroups = <String, List<String>>{};
      for (final path in conflicts) {
        (conflictedGroups[_groupOf(path)] ??= []).add(path);
      }
      final winners = <String, _Side>{};
      final stamp = _stamp(DateTime.now());
      var conflictCopies = 0;

      for (final entry in conflictedGroups.entries) {
        final group = entry.key;
        final members = entry.value;

        // the side that was edited last wins
        final localEdit = members
            .map((path) => local[path]!.modified)
            .reduce((a, b) => a > b ? a : b);
        final remoteEdits = members.map(remoteEdit).nonNulls;
        final remoteEditMax = remoteEdits.isEmpty
            ? null
            : remoteEdits.reduce((a, b) => a > b ? a : b);
        final winner = remoteEditMax != null && remoteEditMax > localEdit
            ? _Side.remote
            : _Side.local;
        winners[group] = winner;

        // keep the other side's version of the whole group as a copy
        try {
          final loser = winner == _Side.local ? _Side.remote : _Side.local;
          final everyone = paths.where((path) => _groupOf(path) == group);
          final copyName = _uniqueConflictGroup(group, stamp, local, remote);
          for (final path in everyone) {
            final target = copyName + path.substring(group.length);
            if (loser == _Side.local) {
              final l = local[path];
              if (l == null) continue;
              await FileManager.writeFile(
                target,
                await l.file.readAsBytes(),
                awaitWrite: true,
                alsoUpload: false,
              );
            } else {
              if (remote[path] == null) continue;
              await FileManager.writeFile(
                target,
                await client.get(path),
                awaitWrite: true,
                alsoUpload: false,
              );
            }
          }
          conflictCopies++;
        } catch (e, st) {
          // Overwriting without a copy would lose data: stop here, and try
          // again next time.
          log.warning('Could not save conflict copy of $group: $e', e, st);
          throw WebDavException('Could not keep both versions of $group: $e');
        }
      }

      // --- Apply ---
      final newState = <String, Map<String, dynamic>>{};
      final uploaded = <String>[];
      final deletedRemotely = <String>[];
      var downloads = 0, deletions = 0, errors = 0;
      String? firstError;

      for (final path in paths) {
        final l = local[path];
        final r = remote[path];
        final s = known[path];
        final lChanged = localChanged(path);
        final rChanged = remoteChanged(path);

        // keep what we knew unless something below changes it
        if (s != null) newState[path] = s;

        try {
          _Action action;
          if (conflicts.contains(path)) {
            action = winners[_groupOf(path)] == _Side.remote
                ? _Action.download
                : _Action.upload;
          } else if (l != null && r != null) {
            if (s == null) {
              // same on both sides as far as we can tell
              newState[path] = {'lm': l.modified, 'rs': r.signature};
              action = _Action.nothing;
            } else if (lChanged) {
              action = _Action.upload;
            } else if (rChanged) {
              action = _Action.download;
            } else {
              action = _Action.nothing;
            }
          } else if (l != null) {
            if (s == null || lChanged) {
              action = _Action.upload;
            } else if (remoteLooksWiped) {
              action = _Action.nothing;
            } else {
              action = _Action.deleteLocal; // deleted on the server
            }
          } else if (r != null) {
            if (s == null || rChanged) {
              action = _Action.download;
            } else {
              action = _Action.deleteRemote; // deleted on this device
            }
          } else {
            newState.remove(path);
            action = _Action.nothing;
          }

          switch (action) {
            case _Action.nothing:
              break;
            case _Action.upload:
              final bytes = await l!.file.readAsBytes();
              await client.ensureDirectory(_parent(path));
              await client.put(path, bytes);
              uploaded.add(path);
              editTimes[path] = l.modified;
              newState[path] = {'lm': l.modified, 'rs': ''};
            case _Action.download:
              final bytes = await client.get(path);
              final edited = remoteEdit(path);
              await FileManager.writeFile(
                path,
                bytes,
                awaitWrite: true,
                alsoUpload: false,
                // the file keeps the time it was really edited
                lastModified: edited == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(edited),
              );
              final stat = FileManager.getFile(path).statSync();
              newState[path] = {
                'lm': stat.modified.millisecondsSinceEpoch,
                'rs': r!.signature,
              };
              downloads++;
            case _Action.deleteLocal:
              await FileManager.deleteFile(
                path,
                alsoUpload: false,
                alsoDeleteAssets: false,
              );
              newState.remove(path);
              deletions++;
            case _Action.deleteRemote:
              await client.delete(path);
              newState.remove(path);
              deletedRemotely.add(path);
              deletions++;
          }
        } catch (e, st) {
          log.warning('Failed to sync $path: $e', e, st);
          errors++;
          firstError ??= e.toString();
        }
      }

      // learn the server's version of what we just uploaded
      if (uploaded.isNotEmpty) {
        try {
          final fresh = {
            for (final file in await client.listAll()) file.path: file,
          };
          for (final path in uploaded) {
            final entry = newState[path];
            final file = fresh[path];
            if (entry != null && file != null) entry['rs'] = file.signature;
          }
        } catch (e, st) {
          log.warning('Could not refresh after upload: $e', e, st);
        }
      }

      if (uploaded.isNotEmpty || deletedRemotely.isNotEmpty) {
        await _writeEditTimes(client, uploaded, editTimes, deletedRemotely);
      }

      _saveState(location, newState);

      // the conflict copies are new files: upload them soon
      if (conflictCopies > 0) _runAgain = true;

      final parts = [
        if (uploaded.isNotEmpty) '${uploaded.length} uploaded',
        if (downloads > 0) '$downloads downloaded',
        if (deletions > 0) '$deletions deleted',
        if (conflictCopies > 0)
          '$conflictCopies ${conflictCopies == 1 ? 'conflict' : 'conflicts'} '
              '(both versions kept)',
      ];
      final summary = parts.isEmpty
          ? 'Everything is up to date'
          : parts.join(', ');
      if (errors > 0) {
        throw WebDavException('$summary; $errors failed ($firstError)');
      }
      return summary;
    } finally {
      client.close();
    }
  }

  // --- When files were edited -----------------------------------------------

  Future<Map<String, int>> _readEditTimes(WebDavClient client) async {
    try {
      final json = jsonDecode(utf8.decode(await client.get(_editTimesPath)));
      return {
        for (final entry in (json as Map).entries)
          if (entry.value is int) entry.key as String: entry.value as int,
      };
    } catch (_) {
      // doesn't exist yet (or unreadable): fall back to the server's times
      return {};
    }
  }

  /// Saves this device's edit times without losing the ones other devices
  /// wrote in the meantime.
  Future<void> _writeEditTimes(
    WebDavClient client,
    List<String> uploaded,
    Map<String, int> mine,
    List<String> deleted,
  ) async {
    try {
      final merged = await _readEditTimes(client);
      for (final path in uploaded) {
        final time = mine[path];
        if (time != null) merged[path] = time;
      }
      deleted.forEach(merged.remove);
      await client.ensureDirectory('/');
      await client.put(_editTimesPath, utf8.encode(jsonEncode(merged)));
    } catch (e, st) {
      // not fatal: the server's own times are used instead
      log.warning('Could not save edit times: $e', e, st);
    }
  }

  // --- Conflict copies --------------------------------------------------------

  static final _noteGroupRegExp = RegExp(r'^(.*\.sbn2)(\.\d+|\.p)?$');

  /// A note, its attachments (note.sbn2.0, …) and its preview (note.sbn2.p)
  /// belong together. Any other file is a group of its own.
  static String _groupOf(String path) =>
      _noteGroupRegExp.firstMatch(path)?.group(1) ?? path;

  static String _stamp(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}.${two(time.minute)}';
  }

  /// `/dir/name.sbn2` -> `/dir/name (conflict 2026-11-21 14.05).sbn2`
  /// (with a number added if that name is taken).
  static String _uniqueConflictGroup(
    String group,
    String stamp,
    Map<String, _LocalFile> local,
    Map<String, WebDavRemoteFile> remote,
  ) {
    final slash = group.lastIndexOf('/');
    final dot = group.lastIndexOf('.');
    final hasExtension = dot > slash + 1;
    final base = hasExtension ? group.substring(0, dot) : group;
    final extension = hasExtension ? group.substring(dot) : '';

    for (var n = 1; ; n++) {
      final label = n == 1 ? stamp : '$stamp $n';
      final candidate = '$base (conflict $label)$extension';
      final taken =
          local.keys.any((p) => _groupOf(p) == candidate) ||
          remote.keys.any((p) => _groupOf(p) == candidate);
      if (!taken) return candidate;
    }
  }

  static String _parent(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? '/' : path.substring(0, i);
  }

  Future<Map<String, _LocalFile>> _scanLocal() async {
    final result = <String, _LocalFile>{};
    final root = FileManager.getRootDirectory();
    if (!root.existsSync()) return result;

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      var path = entity.path
          .substring(FileManager.documentsDirectory.length)
          .replaceAll(Platform.pathSeparator, '/');
      if (!path.startsWith('/')) path = '/$path';
      // hidden and temporary files stay on this device
      if (path.split('/').any((s) => s.startsWith('.'))) continue;
      if (path.endsWith('.tmp')) continue;

      final stat = entity.statSync();
      result[path] = _LocalFile(
        entity,
        stat.modified.millisecondsSinceEpoch,
        stat.size,
      );
    }
    return result;
  }

  ({String location, Map<String, Map<String, dynamic>> files}) _loadState() {
    try {
      final json = jsonDecode(stows.webdavState.value) as Map<String, dynamic>;
      final files = (json['files'] as Map<String, dynamic>? ?? {}).map(
        (key, value) => MapEntry(key, Map<String, dynamic>.from(value as Map)),
      );
      return (location: json['location'] as String? ?? '', files: files);
    } catch (_) {
      return (location: '', files: <String, Map<String, dynamic>>{});
    }
  }

  void _saveState(String location, Map<String, Map<String, dynamic>> files) {
    stows.webdavState.value = jsonEncode({
      'location': location,
      'files': files,
    });
  }
}
