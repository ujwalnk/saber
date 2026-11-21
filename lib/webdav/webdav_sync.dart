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
  const WebDavSyncStatus(this.state, [this.message = '', this.time]);

  final WebDavSyncState state;
  final String message;
  final DateTime? time;
}

class _LocalFile {
  const _LocalFile(this.file, this.modified, this.size);
  final File file;
  final int modified; // milliseconds since epoch
  final int size;
}

/// Two-way sync between the notes folder and a WebDAV folder.
///
/// Notes are stored as they are on the device (not encrypted), in the same
/// folder structure, so any WebDAV server works, and several devices can
/// share one folder.
///
/// What was in sync last time is remembered ([Stows.webdavState]): that is
/// how a change on one side is told apart from a deletion on the other.
/// A file changed on both sides keeps the newer version.
class WebDavSync {
  WebDavSync._();
  static final instance = WebDavSync._();

  static final log = Logger('WebDavSync');

  final status = ValueNotifier(const WebDavSyncStatus(.idle));

  Timer? _debounce;
  Timer? _periodic;
  bool _running = false;
  bool _runAgain = false;
  bool _started = false;

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
    _periodic = Timer.periodic(
      const Duration(minutes: 3),
      (_) => syncNow(),
    );
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

      final remoteList = await client.listAll();
      final remote = {for (final file in remoteList) file.path: file};
      final local = await _scanLocal();

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

      final newState = <String, Map<String, dynamic>>{};
      final uploaded = <String>[];
      var downloads = 0, deletions = 0, errors = 0;
      String? firstError;

      for (final path in paths) {
        final l = local[path];
        final r = remote[path];
        final s = known[path];
        final localChanged = l != null && (s == null || s['lm'] != l.modified);
        final remoteChanged =
            r != null && (s == null || s['rs'] != r.signature);

        // keep what we knew unless something below changes it
        if (s != null) newState[path] = s;

        try {
          _Action action;
          if (l != null && r != null) {
            if (s == null) {
              if (l.size == r.size) {
                // same on both sides as far as we can tell
                newState[path] = {'lm': l.modified, 'rs': r.signature};
                action = _Action.nothing;
              } else {
                action = _newer(l, r);
              }
            } else if (localChanged && remoteChanged) {
              action = _newer(l, r);
            } else if (localChanged) {
              action = _Action.upload;
            } else if (remoteChanged) {
              action = _Action.download;
            } else {
              action = _Action.nothing;
            }
          } else if (l != null) {
            if (s == null || localChanged) {
              action = _Action.upload;
            } else if (remoteLooksWiped) {
              action = _Action.nothing;
            } else {
              action = _Action.deleteLocal; // deleted on the server
            }
          } else if (r != null) {
            if (s == null || remoteChanged) {
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
              newState[path] = {'lm': l.modified, 'rs': ''};
            case _Action.download:
              final bytes = await client.get(path);
              await FileManager.writeFile(
                path,
                bytes,
                awaitWrite: true,
                alsoUpload: false,
              );
              final stat = await FileManager.getFile(path).stat();
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

      _saveState(location, newState);

      final parts = [
        if (uploaded.isNotEmpty) '${uploaded.length} uploaded',
        if (downloads > 0) '$downloads downloaded',
        if (deletions > 0) '$deletions deleted',
      ];
      final summary = parts.isEmpty ? 'Everything is up to date' : parts.join(', ');
      if (errors > 0) {
        throw WebDavException(
          '$summary; $errors failed ($firstError)',
        );
      }
      return summary;
    } finally {
      client.close();
    }
  }

  /// Which version wins when both changed: the newer one.
  _Action _newer(_LocalFile l, WebDavRemoteFile r) {
    final remoteTime = r.lastModified?.millisecondsSinceEpoch;
    if (remoteTime == null || l.modified >= remoteTime) return _Action.upload;
    return _Action.download;
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

      final stat = await entity.stat();
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
    stows.webdavState.value = jsonEncode({'location': location, 'files': files});
  }
}

enum _Action { nothing, upload, download, deleteLocal, deleteRemote }
