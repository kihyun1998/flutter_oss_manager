import 'dart:convert';
import 'dart:io';

import 'package:flutter_oss_manager/src/license_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late LicenseCache cache;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('license_cache_test_');
    cache = LicenseCache(projectRoot: tmp.path);
    await cache.load();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('load() on missing file yields empty cache', () {
    expect(cache.length, 0);
    expect(cache.get('args', '2.4.2'), isNull);
  });

  test('put/save/load roundtrip preserves entries', () async {
    cache.put(
      'args',
      '2.4.2',
      CachedLicense(
        spdx: 'BSD-3-Clause',
        source: CacheSource.pubApi,
        fetchedAt: DateTime.utc(2026, 4, 22, 10, 15),
      ),
    );
    cache.put(
      'foo',
      '1.0.0',
      CachedLicense(
        spdx: 'MIT',
        source: CacheSource.heuristic,
        fetchedAt: DateTime.utc(2026, 4, 22, 10, 16),
      ),
    );
    await cache.save();

    final cache2 = LicenseCache(projectRoot: tmp.path);
    await cache2.load();
    expect(cache2.length, 2);
    final args = cache2.get('args', '2.4.2')!;
    expect(args.spdx, 'BSD-3-Clause');
    expect(args.source, CacheSource.pubApi);
    expect(args.fetchedAt, DateTime.utc(2026, 4, 22, 10, 15));
    final foo = cache2.get('foo', '1.0.0')!;
    expect(foo.source, CacheSource.heuristic);
  });

  test('version-specific keys: different versions don\'t collide', () async {
    cache.put(
      'yaml',
      '3.1.2',
      CachedLicense(
        spdx: 'MIT',
        source: CacheSource.pubApi,
        fetchedAt: DateTime.now().toUtc(),
      ),
    );
    expect(cache.get('yaml', '3.1.2'), isNotNull);
    expect(cache.get('yaml', '3.1.3'), isNull,
        reason: 'different version must miss');
  });

  test('negative entries roundtrip', () async {
    cache.put(
      'bar',
      '0.1.0',
      CachedLicense(
        spdx: 'Unknown',
        source: CacheSource.negative,
        fetchedAt: DateTime.now().toUtc(),
      ),
    );
    await cache.save();

    final cache2 = LicenseCache(projectRoot: tmp.path);
    await cache2.load();
    expect(cache2.get('bar', '0.1.0')!.source, CacheSource.negative);
  });

  test('schema version mismatch → load silently empties the cache', () async {
    final file = File(p.join(tmp.path, '.dart_tool', 'flutter_oss_manager',
        'pub_license_cache.json'));
    file.parent.createSync(recursive: true);
    await file.writeAsString(jsonEncode({
      'schemaVersion': 999,
      'entries': {
        'args@2.4.2': {'spdx': 'BSD-3-Clause'}
      },
    }));

    final cache2 = LicenseCache(projectRoot: tmp.path);
    await cache2.load();
    expect(cache2.length, 0);
  });

  test('corrupt JSON → load silently empties the cache', () async {
    final file = File(p.join(tmp.path, '.dart_tool', 'flutter_oss_manager',
        'pub_license_cache.json'));
    file.parent.createSync(recursive: true);
    await file.writeAsString('{{{ not valid json');

    final cache2 = LicenseCache(projectRoot: tmp.path);
    await cache2.load();
    expect(cache2.length, 0);
  });

  test('clear() empties in-memory state', () {
    cache.put(
      'args',
      '2.4.2',
      CachedLicense(
        spdx: 'BSD-3-Clause',
        source: CacheSource.pubApi,
        fetchedAt: DateTime.now().toUtc(),
      ),
    );
    expect(cache.length, 1);
    cache.clear();
    expect(cache.length, 0);
  });

  test('cache file lives under .dart_tool/flutter_oss_manager/', () async {
    cache.put(
      'args',
      '2.4.2',
      CachedLicense(
        spdx: 'BSD-3-Clause',
        source: CacheSource.pubApi,
        fetchedAt: DateTime.now().toUtc(),
      ),
    );
    await cache.save();
    expect(
      File(p.join(tmp.path, '.dart_tool', 'flutter_oss_manager',
              'pub_license_cache.json'))
          .existsSync(),
      isTrue,
    );
  });
}
