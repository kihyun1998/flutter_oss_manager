import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Source that produced the cached SPDX value. Retained for debug logs and
/// potential future invalidation policies.
enum CacheSource {
  pubApi,
  heuristic,

  /// Negative entry: neither pub.dev nor heuristic could identify the license.
  /// Kept to avoid re-fetching within the same build and across runs until
  /// the user explicitly runs `--refresh-cache`.
  negative,
}

String _sourceToString(CacheSource s) => switch (s) {
      CacheSource.pubApi => 'pub-api',
      CacheSource.heuristic => 'heuristic',
      CacheSource.negative => 'negative',
    };

CacheSource? _sourceFromString(String s) => switch (s) {
      'pub-api' => CacheSource.pubApi,
      'heuristic' => CacheSource.heuristic,
      'negative' => CacheSource.negative,
      _ => null,
    };

class CachedLicense {
  CachedLicense({
    required this.spdx,
    required this.source,
    required this.fetchedAt,
  });

  final String spdx;
  final CacheSource source;
  final DateTime fetchedAt;

  Map<String, dynamic> toJson() => {
        'spdx': spdx,
        'source': _sourceToString(source),
        'fetchedAt': fetchedAt.toUtc().toIso8601String(),
      };

  static CachedLicense? tryFromJson(Object? v) {
    if (v is! Map) return null;
    final spdx = v['spdx'];
    final source = v['source'];
    final fetchedAt = v['fetchedAt'];
    if (spdx is! String || source is! String || fetchedAt is! String) {
      return null;
    }
    final parsedSource = _sourceFromString(source);
    final parsedTime = DateTime.tryParse(fetchedAt);
    if (parsedSource == null || parsedTime == null) return null;
    return CachedLicense(
      spdx: spdx,
      source: parsedSource,
      fetchedAt: parsedTime,
    );
  }
}

/// JSON-backed cache keyed by `<name>@<version>`. Lives under
/// `.dart_tool/flutter_oss_manager/pub_license_cache.json`, which Flutter
/// gitignores by default, so the file is never committed.
///
/// Lifecycle: [load] once, [get]/[put] during a scan, [save] once at the end.
class LicenseCache {
  LicenseCache({required this.projectRoot});

  static const int _schemaVersion = 1;
  static const String _relativePath =
      '.dart_tool/flutter_oss_manager/pub_license_cache.json';

  final String projectRoot;
  final Map<String, CachedLicense> _entries = {};
  bool _loaded = false;

  File get cacheFile => File(p.join(projectRoot, _relativePath));

  String _key(String name, String version) => '$name@$version';

  Future<void> load() async {
    _loaded = true;
    _entries.clear();
    final file = cacheFile;
    if (!file.existsSync()) return;
    try {
      final body = await file.readAsString();
      final decoded = jsonDecode(body);
      if (decoded is! Map) return;
      final schema = decoded['schemaVersion'];
      if (schema != _schemaVersion) return;
      final entries = decoded['entries'];
      if (entries is! Map) return;
      for (final e in entries.entries) {
        final key = e.key;
        if (key is! String) continue;
        final parsed = CachedLicense.tryFromJson(e.value);
        if (parsed != null) _entries[key] = parsed;
      }
    } catch (_) {
      // Corrupt file → treat as empty; the next save() will overwrite it.
      _entries.clear();
    }
  }

  CachedLicense? get(String name, String version) {
    assert(_loaded, 'LicenseCache.get called before load()');
    return _entries[_key(name, version)];
  }

  void put(String name, String version, CachedLicense entry) {
    _entries[_key(name, version)] = entry;
  }

  void clear() {
    _entries.clear();
  }

  int get length => _entries.length;

  Future<void> save() async {
    final file = cacheFile;
    file.parent.createSync(recursive: true);
    final payload = {
      'schemaVersion': _schemaVersion,
      'entries': {
        for (final e in _entries.entries) e.key: e.value.toJson(),
      },
    };
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  }
}
