import 'dart:convert';

import 'package:path/path.dart' as p;

import 'models/oss_license.dart';
import 'payload_codec.dart';

/// One generated Dart file: its target [path] and full [content]. The
/// content-hash (crc32) is embedded inside [content], not exposed separately.
class GeneratedFile {
  const GeneratedFile({required this.path, required this.content});

  final String path;
  final String content;
}

/// The four files this tool emits: the [main] file plus the three platform
/// decoder sidecars ([stub]/[io]/[web]).
class GeneratedFiles {
  const GeneratedFiles({
    required this.main,
    required this.stub,
    required this.io,
    required this.web,
  });

  final GeneratedFile main;
  final GeneratedFile stub;
  final GeneratedFile io;
  final GeneratedFile web;

  List<GeneratedFile> get all => [main, stub, io, web];
}

/// Pure renderer: turns [licenses] into the four generated file contents for
/// the given [outputPath]. Writes nothing — the caller persists the result.
GeneratedFiles renderGeneratedFiles(
  List<OssLicense> licenses,
  String outputPath,
) {
  final paths = resolveSidecarPaths(outputPath);
  final payload = encodePayload(licenses);
  return GeneratedFiles(
    main: GeneratedFile(
      path: paths.main,
      content: _finalizeHeader(_buildMainFileContent(paths, payload)),
    ),
    stub: GeneratedFile(
      path: paths.stub,
      content: _finalizeHeader(_buildStubContent()),
    ),
    io: GeneratedFile(
      path: paths.io,
      content: _finalizeHeader(_buildIoContent()),
    ),
    web: GeneratedFile(
      path: paths.web,
      content: _finalizeHeader(_buildWebContent()),
    ),
  );
}

const String _generatorVersion = '2.0.0';
const String _hashPlaceholderLine = '// content-hash: crc32:00000000';

/// Replaces the `crc32:00000000` placeholder in the header with the actual
/// CRC32 of the file body (with the placeholder still zeroed). Verification
/// later: read file, restore placeholder to zeros, compute CRC32, compare.
String _finalizeHeader(String body) {
  const placeholder = 'crc32:00000000';
  final crc = crc32(utf8.encode(body));
  final hex = crc.toRadixString(16).padLeft(8, '0');
  return body.replaceFirst(placeholder, 'crc32:$hex');
}

String _buildMainFileContent(SidecarPaths paths, String payload) {
  final stubName = p.basename(paths.stub);
  final ioName = p.basename(paths.io);
  final webName = p.basename(paths.web);
  return '''// GENERATED CODE - DO NOT MODIFY BY HAND
// flutter_oss_manager: $_generatorVersion
$_hashPlaceholderLine
// ignore_for_file: type=lint
//
// The entire license list is stored as a gzip+base64-encoded JSON blob
// below. For one-shot access prefer `OssLicenses.use((licenses) { ... })`,
// which releases the reference for you. For a long-lived holder, call
// `OssLicenses.acquire()` to obtain a reference-counted handle and
// `handle.close()` when done. When all handles are closed, the cache is
// released and becomes GC-eligible.
//
// Platform decoders are selected via conditional imports. Do not import
// the sidecar decoder files directly — only this main file.
//
// Dev note: static cache survives hot reload. After regenerating this
// file, use hot restart (not hot reload) to pick up the new payload.

import 'dart:async';
import 'dart:convert';

import '$stubName'
    if (dart.library.io) '$ioName'
    if (dart.library.js_interop) '$webName';

/// Information about a single open-source license used by the project.
class OssLicense {
  final String name;
  final String version;
  final String licenseText;
  final String licenseSummary;
  final String? repositoryUrl;
  final String? description;

  const OssLicense({
    required this.name,
    required this.version,
    required this.licenseText,
    required this.licenseSummary,
    this.repositoryUrl,
    this.description,
  });

  factory OssLicense._fromJson(Map<String, dynamic> j) => OssLicense(
        name: j['name'] as String,
        version: j['version'] as String,
        licenseText: j['licenseText'] as String,
        licenseSummary: j['licenseSummary'] as String,
        repositoryUrl: j['repositoryUrl'] as String?,
        description: j['description'] as String?,
      );
}

/// A reference-counted handle to the decoded license list.
///
/// Obtain via [OssLicenses.acquire]. Call [close] when finished. When the
/// last handle is closed, the cached list is released.
class OssLicensesHandle {
  /// The decoded list. Safe to read while this handle is open.
  final List<OssLicense> licenses;
  bool _closed = false;

  OssLicensesHandle._(this.licenses);

  /// Release this handle's reference. Idempotent.
  void close() {
    if (_closed) return;
    _closed = true;
    OssLicenses._releaseOne();
  }
}

/// Lifecycle controller for the embedded license list.
class OssLicenses {
  static const String _payload = '$payload';
  static Future<List<OssLicense>>? _loading;
  static int _refCount = 0;

  /// Acquire a handle to the license list. First call decodes the blob;
  /// subsequent calls share the same decoded list. Safe to call concurrently.
  ///
  /// Call [OssLicensesHandle.close] when done.
  static Future<OssLicensesHandle> acquire() async {
    _refCount++;
    _loading ??= _decode();
    try {
      final list = await _loading!;
      return OssLicensesHandle._(list);
    } catch (_) {
      _refCount--;
      if (_refCount == 0) _loading = null;
      rethrow;
    }
  }

  /// Runs [body] with the decoded license list and releases the reference when
  /// it completes — even if [body] throws. Prefer this for one-shot access:
  /// you never hold, or forget to close, a handle. Returns whatever [body]
  /// returns; [body] may be sync or async.
  static Future<T> use<T>(
    FutureOr<T> Function(List<OssLicense> licenses) body,
  ) async {
    final handle = await acquire();
    try {
      return await body(handle.licenses);
    } finally {
      handle.close();
    }
  }

  /// Test-only: resets the cached state. Do not call in production code.
  static void resetForTest() {
    _loading = null;
    _refCount = 0;
  }

  /// Test-only: the current outstanding-handle count. Do not use in
  /// production code — it exists so tests can assert that [use] releases its
  /// reference (returns to 0) even when the callback throws.
  static int get refCountForTest => _refCount;

  static void _releaseOne() {
    _refCount--;
    assert(
      _refCount >= 0,
      'OssLicenses: close() called more times than acquire()',
    );
    if (_refCount == 0) {
      _loading = null;
    }
  }

  static Future<List<OssLicense>> _decode() async {
    final bytes = await decodeGzipBase64(_payload);
    final list = jsonDecode(utf8.decode(bytes)) as List;
    return List.unmodifiable(
      list.map((j) => OssLicense._fromJson(j as Map<String, dynamic>)),
    );
  }
}
''';
}

String _buildStubContent() => '''// GENERATED CODE - DO NOT MODIFY BY HAND
// flutter_oss_manager: $_generatorVersion
$_hashPlaceholderLine
// ignore_for_file: type=lint

import 'dart:async';
import 'dart:typed_data';

Future<Uint8List> decodeGzipBase64(String encoded) =>
    throw UnsupportedError(
      'flutter_oss_manager: no decoder available for this platform. '
      'Expected either dart:io or dart:js_interop to be available.',
    );
''';

String _buildIoContent() => '''// GENERATED CODE - DO NOT MODIFY BY HAND
// flutter_oss_manager: $_generatorVersion
$_hashPlaceholderLine
// ignore_for_file: type=lint

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> decodeGzipBase64(String encoded) async {
  final gzipped = base64.decode(encoded);
  final raw = gzip.decode(gzipped);
  return raw is Uint8List ? raw : Uint8List.fromList(raw);
}
''';

String _buildWebContent() => '''// GENERATED CODE - DO NOT MODIFY BY HAND
// flutter_oss_manager: $_generatorVersion
$_hashPlaceholderLine
// ignore_for_file: type=lint

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('Response')
extension type _Response._(JSObject _) implements JSObject {
  external factory _Response(JSAny? body);
  external _ReadableStream? get body;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

@JS('ReadableStream')
extension type _ReadableStream._(JSObject _) implements JSObject {
  external _ReadableStream pipeThrough(_DecompressionStream transform);
}

@JS('DecompressionStream')
extension type _DecompressionStream._(JSObject _) implements JSObject {
  external factory _DecompressionStream(String format);
}

Future<Uint8List> decodeGzipBase64(String encoded) async {
  final Uint8List bytes = base64.decode(encoded);
  final source = _Response(bytes.toJS);
  final readable = source.body!;
  final decompressed = readable.pipeThrough(_DecompressionStream('gzip'));
  final buffer = await _Response(decompressed).arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}
''';
