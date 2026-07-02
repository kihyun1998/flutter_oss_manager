import 'dart:io';

import 'package:flutter_oss_manager/src/package_locator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

YamlMap _y(String src) => loadYaml(src) as YamlMap;

/// Quote a path for YAML embedding — escape backslashes (Windows) and quotes
/// so drive-letter colons and separators don't confuse the parser.
String _yamlString(String s) {
  final escaped = s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}

void main() {
  late Directory tmp;
  late String pubCache;
  late String flutterSdk;
  late String projectRoot;
  late PackageLocator locator;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('package_locator_test_');
    pubCache = p.join(tmp.path, 'pub-cache');
    flutterSdk = p.join(tmp.path, 'flutter');
    projectRoot = p.join(tmp.path, 'project');
    Directory(projectRoot).createSync(recursive: true);
    locator = PackageLocator(
      pubCachePath: pubCache,
      flutterSdkPath: flutterSdk,
      projectRoot: projectRoot,
    );
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('hosted → pub-cache/hosted/pub.dev/<name>-<version>', () async {
    final dir = await locator.packageRootDir(
      name: 'args',
      lockEntry: _y('source: hosted\nversion: "2.7.0"'),
    );
    expect(dir, isNotNull);
    expect(dir!.path, p.join(pubCache, 'hosted', 'pub.dev', 'args-2.7.0'));
  });

  test('hosted without a version → null', () async {
    final dir = await locator.packageRootDir(
      name: 'args',
      lockEntry: _y('source: hosted'),
    );
    expect(dir, isNull);
  });

  group('sdk source', () {
    test('resolves <sdk>/packages/<name> when that directory exists', () async {
      Directory(p.join(flutterSdk, 'packages', 'flutter'))
          .createSync(recursive: true);
      final dir = await locator.packageRootDir(
        name: 'flutter',
        lockEntry: _y('source: sdk\ndescription: flutter\nversion: "0.0.0"'),
      );
      expect(dir, isNotNull);
      expect(dir!.path, p.join(flutterSdk, 'packages', 'flutter'));
    });

    test('falls back to <sdk>/bin/cache/pkg/<name>', () async {
      Directory(p.join(flutterSdk, 'bin', 'cache', 'pkg', 'sky_engine'))
          .createSync(recursive: true);
      final dir = await locator.packageRootDir(
        name: 'sky_engine',
        lockEntry: _y('source: sdk\ndescription: flutter\nversion: "0.0.0"'),
      );
      expect(dir, isNotNull);
      expect(dir!.path, p.join(flutterSdk, 'bin', 'cache', 'pkg', 'sky_engine'));
    });

    test('no matching candidate directory → null', () async {
      final dir = await locator.packageRootDir(
        name: 'unknown_sdk_pkg',
        lockEntry: _y('source: sdk\ndescription: flutter\nversion: "0.0.0"'),
      );
      expect(dir, isNull);
    });

    test('null flutterSdkPath → null for sdk source', () async {
      final noSdk = PackageLocator(
        pubCachePath: pubCache,
        flutterSdkPath: null,
        projectRoot: projectRoot,
      );
      final dir = await noSdk.packageRootDir(
        name: 'flutter',
        lockEntry: _y('source: sdk\ndescription: flutter\nversion: "0.0.0"'),
      );
      expect(dir, isNull);
    });
  });

  group('path source', () {
    test('relative path resolves against projectRoot', () async {
      final dir = await locator.packageRootDir(
        name: 'sibling',
        lockEntry: _y('''
source: path
version: "0.0.1"
description:
  path: "../sibling_pkg"
  relative: true
'''),
      );
      expect(dir, isNotNull);
      expect(p.equals(dir!.path, p.join(projectRoot, '..', 'sibling_pkg')),
          isTrue,
          reason: dir.path);
    });

    test('absolute path is used as-is', () async {
      final abs = p.join(tmp.path, 'abs_pkg');
      final dir = await locator.packageRootDir(
        name: 'abs',
        lockEntry: loadYaml('''
source: path
version: "0.0.1"
description:
  path: ${_yamlString(abs)}
  relative: false
''') as YamlMap,
      );
      expect(dir, isNotNull);
      expect(dir!.path, abs);
    });

    test('path source without a path field → null', () async {
      final dir = await locator.packageRootDir(
        name: 'ghost',
        lockEntry: _y('source: path\nversion: "0.0.1"\ndescription: {}'),
      );
      expect(dir, isNull);
    });
  });

  group('git source', () {
    test('resolves pub-cache/git/<name>-<resolved-ref>', () async {
      final dir = await locator.packageRootDir(
        name: 'foo',
        lockEntry: _y('''
source: git
version: "0.0.1"
description:
  url: "https://github.com/example/foo.git"
  resolved-ref: abc123def456
  path: "."
'''),
      );
      expect(dir, isNotNull);
      expect(p.equals(dir!.path, p.join(pubCache, 'git', 'foo-abc123def456')),
          isTrue,
          reason: dir.path);
    });

    test('follows description.path subdirectory', () async {
      final dir = await locator.packageRootDir(
        name: 'mono',
        lockEntry: _y('''
source: git
version: "0.0.1"
description:
  resolved-ref: def789
  path: "packages/inner"
'''),
      );
      expect(dir, isNotNull);
      expect(
          p.equals(dir!.path,
              p.join(pubCache, 'git', 'mono-def789', 'packages', 'inner')),
          isTrue,
          reason: dir.path);
    });

    test('git without resolved-ref → null', () async {
      final dir = await locator.packageRootDir(
        name: 'foo',
        lockEntry: _y('source: git\ndescription:\n  url: "x"'),
      );
      expect(dir, isNull);
    });
  });

  group('unrecognized', () {
    test('unknown source → null', () async {
      final dir = await locator.packageRootDir(
        name: 'mystery',
        lockEntry: _y('source: hg\nversion: "1.0.0"'),
      );
      expect(dir, isNull);
    });

    test('missing source → null', () async {
      final dir = await locator.packageRootDir(
        name: 'mystery',
        lockEntry: _y('version: "1.0.0"'),
      );
      expect(dir, isNull);
    });
  });

  group('environment roots', () {
    test('pubCacheDir / flutterSdkRoot expose the injected roots', () {
      expect(p.equals(locator.pubCacheDir.path, pubCache), isTrue);
      expect(locator.flutterSdkRoot, isNotNull);
      expect(p.equals(locator.flutterSdkRoot!.path, flutterSdk), isTrue);
    });

    test('flutterSdkRoot is null when no SDK path was provided', () {
      final noSdk = PackageLocator(
        pubCachePath: pubCache,
        flutterSdkPath: null,
        projectRoot: projectRoot,
      );
      expect(noSdk.flutterSdkRoot, isNull);
    });
  });
}
