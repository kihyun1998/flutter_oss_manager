// GENERATED CODE - DO NOT MODIFY BY HAND
// flutter_oss_manager: 2.3.0
// content-hash: crc32:4049855a
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

import 'oss_licenses_decoder_stub.g.dart'
    if (dart.library.io) 'oss_licenses_decoder_io.g.dart'
    if (dart.library.js_interop) 'oss_licenses_decoder_web.g.dart';

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
  static const String _payload = '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';
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
