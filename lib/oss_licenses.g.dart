// GENERATED CODE - DO NOT MODIFY BY HAND
// flutter_oss_manager: 2.0.0
// content-hash: crc32:b7ada5f9
// ignore_for_file: type=lint
//
// The entire license list is stored as a gzip+base64-encoded JSON blob
// below. Use `OssLicenses.acquire()` to obtain a reference-counted handle
// to the decoded list, and call `handle.close()` when done. When all
// handles are closed, the cache is released and becomes GC-eligible.
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
  static const String _payload =
      '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';
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

  /// Test-only: resets the cached state. Do not call in production code.
  static void resetForTest() {
    _loading = null;
    _refCount = 0;
  }

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
