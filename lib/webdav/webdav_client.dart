import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class WebDavException implements Exception {
  const WebDavException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// A file on the WebDAV server.
class WebDavRemoteFile {
  const WebDavRemoteFile({
    required this.path,
    required this.size,
    this.lastModified,
    this.etag,
  });

  /// Path relative to the sync location, starting with a slash.
  final String path;
  final int size;
  final DateTime? lastModified;
  final String? etag;

  /// Changes whenever the file's content changes on the server.
  String get signature => etag != null
      ? 'e:$etag'
      : 'm:${lastModified?.millisecondsSinceEpoch}:$size';
}

/// A minimal WebDAV client (PROPFIND, GET, PUT, DELETE, MKCOL) over HTTP
/// basic auth. Paths are relative to the sync location and start with `/`.
class WebDavClient {
  WebDavClient({
    required String url,
    required this.username,
    required this.password,
    http.Client? client,
  }) : _base = _parseBase(url),
       _client = client ?? http.Client();

  final String username;
  final String password;
  final Uri _base;
  final http.Client _client;
  final _knownDirectories = <String>{};

  static Uri _parseBase(String url) {
    var trimmed = url.trim();
    if (!trimmed.contains('://')) trimmed = 'https://$trimmed';
    return Uri.parse(trimmed);
  }

  /// Normalizes a location so it can be compared with another.
  static String normalizeLocation(String url) {
    final uri = _parseBase(url);
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).join('/');
    return '${uri.scheme}://${uri.authority}/$segments'.toLowerCase();
  }

  List<String> get _baseSegments =>
      _base.pathSegments.where((s) => s.isNotEmpty).toList();

  Uri _uri(String path, {bool collection = false}) {
    final segments = [
      ..._baseSegments,
      ...path.split('/').where((s) => s.isNotEmpty),
      if (collection) '',
    ];
    return _base.replace(pathSegments: segments);
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = http.Request(method, uri)
      ..headers['Authorization'] =
          'Basic ${base64Encode(utf8.encode('$username:$password'))}'
      ..headers.addAll(headers);
    if (body != null) request.bodyBytes = Uint8List.fromList(body);
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 60));
    return http.Response.fromStream(streamed);
  }

  Never _fail(String action, http.Response response) {
    final code = response.statusCode;
    final reason = switch (code) {
      401 || 403 => 'wrong username or password',
      404 => 'not found',
      507 => 'server is out of storage',
      _ => 'HTTP $code',
    };
    throw WebDavException('$action failed: $reason', statusCode: code);
  }

  static const _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:getlastmodified/><d:getcontentlength/><d:getetag/>'
      '<d:resourcetype/></d:prop></d:propfind>';

  /// Checks the credentials. A location that doesn't exist yet is fine, it
  /// is created on the first upload.
  Future<void> check() async {
    final response = await _send(
      'PROPFIND',
      _uri('/', collection: true),
      headers: const {'Depth': '0', 'Content-Type': 'application/xml'},
      body: utf8.encode(_propfindBody),
    );
    if (response.statusCode == 404) return;
    if (response.statusCode != 207 && response.statusCode != 200) {
      _fail('Connecting', response);
    }
  }

  /// Every file below the sync location (the folders are walked one level
  /// at a time, since many servers refuse `Depth: infinity`).
  Future<List<WebDavRemoteFile>> listAll() async {
    final files = <WebDavRemoteFile>[];
    final queue = <String>['/'];
    while (queue.isNotEmpty) {
      final directory = queue.removeLast();
      final entries = await _list(directory);
      if (entries == null) continue; // doesn't exist (yet)
      for (final entry in entries) {
        if (entry.isCollection) {
          queue.add(entry.file.path);
        } else {
          files.add(entry.file);
        }
      }
    }
    return files;
  }

  Future<List<({bool isCollection, WebDavRemoteFile file})>?> _list(
    String directory,
  ) async {
    final response = await _send(
      'PROPFIND',
      _uri(directory, collection: true),
      headers: const {'Depth': '1', 'Content-Type': 'application/xml'},
      body: utf8.encode(_propfindBody),
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode != 207 && response.statusCode != 200) {
      _fail('Listing files', response);
    }

    final self = _normalize(directory);
    final entries = <({bool isCollection, WebDavRemoteFile file})>[];
    for (final match in _responseRegExp.allMatches(response.body)) {
      final block = match.group(1)!;
      final href = _tag(block, 'href');
      if (href == null) continue;
      final path = _relative(_unescape(href));
      if (path == null || path == self) continue;

      final lastModified = _tag(block, 'getlastmodified');
      final etag = _tag(block, 'getetag');
      entries.add((
        isCollection: _collectionRegExp.hasMatch(block),
        file: WebDavRemoteFile(
          path: path,
          size: int.tryParse(_tag(block, 'getcontentlength') ?? '') ?? 0,
          lastModified: _parseDate(lastModified),
          etag: etag == null ? null : _unescape(etag).replaceAll('"', ''),
        ),
      ));
    }
    return entries;
  }

  Future<Uint8List> get(String path) async {
    final response = await _send('GET', _uri(path));
    if (response.statusCode != 200) _fail('Downloading $path', response);
    return response.bodyBytes;
  }

  Future<void> put(String path, List<int> bytes) async {
    final response = await _send('PUT', _uri(path), body: bytes);
    if (const [200, 201, 204].contains(response.statusCode)) return;
    _fail('Uploading $path', response);
  }

  Future<void> delete(String path) async {
    final response = await _send('DELETE', _uri(path));
    if (const [200, 202, 204, 404].contains(response.statusCode)) return;
    _fail('Deleting $path', response);
  }

  /// Creates [directory] and its parents (and the sync location itself).
  Future<void> ensureDirectory(String directory) async {
    final segments = directory.split('/').where((s) => s.isNotEmpty).toList();
    var current = '';
    for (var i = -1; i < segments.length; i++) {
      if (i >= 0) current = '$current/${segments[i]}';
      final key = current.isEmpty ? '/' : current;
      if (_knownDirectories.contains(key)) continue;

      final response = await _send(
        'MKCOL',
        _uri(current.isEmpty ? '/' : current, collection: true),
      );
      final code = response.statusCode;
      // 405 (and some servers' 301): it already exists
      if (code == 201 || code == 405 || code == 301 || code == 200) {
        _knownDirectories.add(key);
      } else {
        _fail('Creating folder $key', response);
      }
    }
  }

  void close() => _client.close();

  // --- Parsing ------------------------------------------------------------

  static final _responseRegExp = RegExp(
    r'<(?:[\w.-]+:)?response\b[^>]*>(.*?)</(?:[\w.-]+:)?response>',
    dotAll: true,
    caseSensitive: false,
  );
  static final _collectionRegExp = RegExp(
    r'<(?:[\w.-]+:)?collection\b',
    caseSensitive: false,
  );

  static String? _tag(String block, String name) {
    final match = RegExp(
      '<(?:[\\w.-]+:)?$name\\b[^>]*>(.*?)</(?:[\\w.-]+:)?$name>',
      dotAll: true,
      caseSensitive: false,
    ).firstMatch(block);
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  static DateTime? _parseDate(String? value) {
    if (value == null) return null;
    try {
      return HttpDate.parse(_unescape(value));
    } catch (_) {
      return null;
    }
  }

  /// No trailing slash, except for the root which is `/`.
  static String _normalize(String path) {
    var p = path;
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p.isEmpty ? '/' : p;
  }

  /// Turns a server path from a PROPFIND response into a path relative to
  /// the sync location, or null if it is outside of it.
  String? _relative(String href) {
    var path = href.trim();
    final parsed = Uri.tryParse(path);
    if (parsed != null && parsed.hasScheme) path = parsed.path;
    try {
      path = Uri.decodeFull(path);
    } catch (_) {
      return null;
    }
    final prefix = _baseSegments.isEmpty ? '' : '/${_baseSegments.join('/')}';
    if (!path.startsWith(prefix)) return null;
    var relative = path.substring(prefix.length);
    if (!relative.startsWith('/')) relative = '/$relative';
    return _normalize(relative);
  }
}
