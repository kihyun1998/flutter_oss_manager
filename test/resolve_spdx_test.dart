import 'dart:io';

import 'package:flutter_oss_manager/src/license_cache.dart';
import 'package:flutter_oss_manager/src/license_generator.dart';
import 'package:flutter_oss_manager/src/pub_license_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records calls and returns preset values. [queue] drained FIFO; null when
/// exhausted.
class FakePubLicenseClient implements PubLicenseClient {
  FakePubLicenseClient({this.responses = const {}});

  final Map<String, String?> responses;
  final List<String> calls = [];

  @override
  Future<String?> fetchSpdxId(String name, String version) async {
    calls.add('$name@$version');
    return responses['$name@$version'];
  }

  @override
  void close() {}
}

/// A multi-paragraph MIT license body that the existing heuristic matches
/// reliably (see [LicenseGenerator._summarizeLicense]).
const _mitText = '''
MIT License

Copyright (c) 2020 Foo

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
''';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('resolve_spdx_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<LicenseCache> freshCache() async {
    final c = LicenseCache(projectRoot: tmp.path);
    await c.load();
    return c;
  }

  test('cache hit skips pub.dev and heuristic', () async {
    final cache = await freshCache();
    cache.put(
      'args',
      '2.4.2',
      CachedLicense(
        spdx: 'BSD-3-Clause',
        source: CacheSource.pubApi,
        fetchedAt: DateTime.now().toUtc(),
      ),
    );
    final fake = FakePubLicenseClient();
    final gen = LicenseGenerator(pubClient: fake, cache: cache);
    final r = await gen.resolveSpdxForTesting(
      packageName: 'args',
      version: '2.4.2',
      licenseText: 'whatever',
    );
    expect(r.spdx, 'BSD-3-Clause');
    expect(r.source, 'cache');
    expect(fake.calls, isEmpty, reason: 'cache hit must not call pub.dev');
  });

  test('pub.dev success returns spdx and caches it', () async {
    final cache = await freshCache();
    final fake = FakePubLicenseClient(responses: {'yaml@3.1.2': 'MIT'});
    final gen = LicenseGenerator(pubClient: fake, cache: cache);
    final r = await gen.resolveSpdxForTesting(
      packageName: 'yaml',
      version: '3.1.2',
      licenseText: _mitText,
    );
    expect(r.spdx, 'MIT');
    expect(r.source, 'pub-api');
    expect(fake.calls, ['yaml@3.1.2']);
    expect(cache.get('yaml', '3.1.2')!.source, CacheSource.pubApi);
  });

  test('pub.dev null falls back to heuristic and caches as heuristic',
      () async {
    final cache = await freshCache();
    final fake = FakePubLicenseClient(responses: {'priv@1.0.0': null});
    final gen = LicenseGenerator(pubClient: fake, cache: cache);
    final r = await gen.resolveSpdxForTesting(
      packageName: 'priv',
      version: '1.0.0',
      licenseText: _mitText,
    );
    expect(r.source, 'heuristic');
    expect(cache.get('priv', '1.0.0')!.source, CacheSource.heuristic);
  });

  test('heuristic Unknown becomes negative in cache', () async {
    final cache = await freshCache();
    final fake = FakePubLicenseClient(responses: {'weird@0.1.0': null});
    final gen = LicenseGenerator(pubClient: fake, cache: cache);
    final r = await gen.resolveSpdxForTesting(
      packageName: 'weird',
      version: '0.1.0',
      licenseText: 'gibberish content with no license pattern at all abc xyz',
    );
    expect(r.spdx, 'Unknown');
    expect(r.source, 'negative');
    expect(cache.get('weird', '0.1.0')!.source, CacheSource.negative);
  });

  test('offline mode skips pub.dev and uses heuristic directly', () async {
    final cache = await freshCache();
    final fake =
        FakePubLicenseClient(responses: {'args@2.4.2': 'BSD-3-Clause'});
    final gen = LicenseGenerator(pubClient: fake, cache: cache, offline: true);
    final r = await gen.resolveSpdxForTesting(
      packageName: 'args',
      version: '2.4.2',
      licenseText: _mitText,
    );
    expect(fake.calls, isEmpty,
        reason: 'offline mode must not call pub.dev even on cache miss');
    expect(r.source, 'heuristic');
  });

  test('no cache: still works, pipeline falls through stages', () async {
    final fake =
        FakePubLicenseClient(responses: {'args@2.4.2': 'BSD-3-Clause'});
    final gen = LicenseGenerator(pubClient: fake /* no cache */);
    final r = await gen.resolveSpdxForTesting(
      packageName: 'args',
      version: '2.4.2',
      licenseText: _mitText,
    );
    expect(r.spdx, 'BSD-3-Clause');
    expect(r.source, 'pub-api');
  });

  test('cache populated by pub.dev is used on second call', () async {
    final cache = await freshCache();
    final fake =
        FakePubLicenseClient(responses: {'args@2.4.2': 'BSD-3-Clause'});
    final gen = LicenseGenerator(pubClient: fake, cache: cache);
    await gen.resolveSpdxForTesting(
      packageName: 'args',
      version: '2.4.2',
      licenseText: _mitText,
    );
    await gen.resolveSpdxForTesting(
      packageName: 'args',
      version: '2.4.2',
      licenseText: _mitText,
    );
    expect(fake.calls, hasLength(1),
        reason: 'second call should hit the cache');
  });
}
