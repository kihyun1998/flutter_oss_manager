import 'dart:async';
import 'dart:io';

import 'package:flutter_oss_manager/src/flutter_sdk_probe.dart';
import 'package:flutter_oss_manager/src/license_generator.dart';
import 'package:flutter_oss_manager/src/payload_codec.dart';
import 'package:flutter_oss_manager/src/pub_license_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A multi-paragraph MIT body the heuristic recognizes.
const _mit = '''
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

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
''';

class _FakeProbe implements FlutterSdkProbe {
  _FakeProbe(this.info);
  final FlutterSdkInfo? info;
  @override
  Future<FlutterSdkInfo?> probe() async => info;
}

/// Returns a preset SPDX id, so the problematic-license path can be exercised
/// without depending on the heuristic classifying planted text a certain way.
class _FakePubClient implements PubLicenseClient {
  _FakePubClient(this.responses);
  final Map<String, String?> responses;
  @override
  Future<String?> fetchSpdxId(String name, String version) async =>
      responses['$name@$version'];
  @override
  void close() {}
}

void main() {
  late Directory tmp;
  late Directory project;
  late Directory cache;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('scan_pkg_');
    project = Directory(p.join(tmp.path, 'proj'))..createSync(recursive: true);
    cache = Directory(p.join(tmp.path, 'cache'))..createSync(recursive: true);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  void writeLock(String body) =>
      File(p.join(project.path, 'pubspec.lock')).writeAsStringSync(body);

  void writeHosted(String name, String ver,
      {String? license, String? pubspec}) {
    final dir = Directory(p.join(cache.path, 'hosted', 'pub.dev', '$name-$ver'))
      ..createSync(recursive: true);
    if (license != null) {
      File(p.join(dir.path, 'LICENSE')).writeAsStringSync(license);
    }
    if (pubspec != null) {
      File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(pubspec);
    }
  }

  String mainPath() => p.join(project.path, 'lib', 'oss_licenses.g.dart');

  List decodedFromMain() {
    final content = File(mainPath()).readAsStringSync();
    final payload =
        RegExp(r"_payload = '([^']+)';").firstMatch(content)!.group(1)!;
    return decodePayloadForTesting(payload);
  }

  test('scans a hosted package end-to-end and writes decodable files',
      () async {
    writeLock('''
packages:
  foo:
    dependency: "direct main"
    source: hosted
    version: "1.2.3"
''');
    writeHosted('foo', '1.2.3', license: _mit);

    await LicenseGenerator(offline: true).scanPackages(
      projectRoot: project.path,
      pubCacheDir: cache.path,
      outputFilePath: 'lib/oss_licenses.g.dart',
    );

    expect(File(mainPath()).existsSync(), isTrue);
    final decoded = decodedFromMain();
    expect(decoded, hasLength(1));
    expect(decoded[0].name, 'foo');
    expect(decoded[0].version, '1.2.3');
    expect(decoded[0].licenseSummary, 'MIT');
  });

  test('carries repository and description from the package pubspec', () async {
    writeLock('''
packages:
  bar:
    dependency: "direct main"
    source: hosted
    version: "2.0.0"
''');
    writeHosted('bar', '2.0.0',
        license: _mit,
        pubspec: 'name: bar\n'
            'repository: https://example.com/bar\n'
            'description: A bar package\n');

    await LicenseGenerator(offline: true).scanPackages(
      projectRoot: project.path,
      pubCacheDir: cache.path,
      outputFilePath: 'lib/oss_licenses.g.dart',
    );

    final decoded = decodedFromMain();
    expect(decoded[0].repositoryUrl, 'https://example.com/bar');
    expect(decoded[0].description, 'A bar package');
  });

  test('skips a hosted package that has no license file', () async {
    writeLock('''
packages:
  ghost:
    dependency: "direct main"
    source: hosted
    version: "0.1.0"
''');
    writeHosted('ghost', '0.1.0'); // directory exists, but no LICENSE

    await LicenseGenerator(offline: true).scanPackages(
      projectRoot: project.path,
      pubCacheDir: cache.path,
      outputFilePath: 'lib/oss_licenses.g.dart',
    );

    expect(decodedFromMain(), isEmpty);
  });

  test('prints a prominent warning for a problematic (GPL) license', () async {
    writeLock('''
packages:
  copyleft:
    dependency: "direct main"
    source: hosted
    version: "3.0.0"
''');
    writeHosted('copyleft', '3.0.0', license: _mit);

    final out = StringBuffer();
    await runZoned(
      () => LicenseGenerator(
        pubClient: _FakePubClient({'copyleft@3.0.0': 'GPL-3.0'}),
      ).scanPackages(
        projectRoot: project.path,
        pubCacheDir: cache.path,
        outputFilePath: 'lib/oss_licenses.g.dart',
      ),
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) => out.writeln(line),
      ),
    );

    expect(out.toString(), contains('LICENSE WARNING'));
    expect(decodedFromMain().single.licenseSummary, 'GPL-3.0');
  });

  test('resolves an sdk package license via the sdk probe', () async {
    final sdkRoot = Directory(p.join(tmp.path, 'sdk'))
      ..createSync(recursive: true);
    File(p.join(sdkRoot.path, 'LICENSE')).writeAsStringSync(_mit);
    writeLock('''
packages:
  flutter:
    dependency: "direct main"
    source: sdk
    version: "0.0.0"
    description: flutter
''');

    await LicenseGenerator(
      offline: true,
      sdkProbe:
          _FakeProbe(FlutterSdkInfo(root: sdkRoot.path, version: '3.99.0')),
    ).scanPackages(
      projectRoot: project.path,
      pubCacheDir: cache.path,
      outputFilePath: 'lib/oss_licenses.g.dart',
    );

    final decoded = decodedFromMain();
    expect(decoded, hasLength(1));
    expect(decoded.single.name, 'flutter');
    expect(decoded.single.version, '3.99.0');
  });
}
