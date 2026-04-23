import 'dart:io';

import 'package:flutter_oss_manager/src/dependency_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

YamlMap _y(String src) => loadYaml(src) as YamlMap;

/// Wrap a path for YAML embedding — escape backslashes on Windows and quote it
/// so YAML doesn't choke on colons (drive letters) or special chars.
String _yamlString(String s) {
  final escaped = s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}

void _writePubspec(String dirPath, String content) {
  Directory(dirPath).createSync(recursive: true);
  File(p.join(dirPath, 'pubspec.yaml')).writeAsStringSync(content);
}

void main() {
  late Directory tmp;
  late String pubCache;
  late String flutterSdk;
  late String projectRoot;
  late FilePubspecReader reader;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('file_pubspec_reader_test_');
    pubCache = p.join(tmp.path, 'pub-cache');
    flutterSdk = p.join(tmp.path, 'flutter');
    projectRoot = p.join(tmp.path, 'project');
    Directory(projectRoot).createSync(recursive: true);
    reader = FilePubspecReader(
      pubCachePath: pubCache,
      flutterSdkPath: flutterSdk,
      projectRoot: projectRoot,
    );
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('hosted source', () {
    test('reads pubspec from pub-cache/hosted/pub.dev/<name>-<version>',
        () async {
      _writePubspec(
        p.join(pubCache, 'hosted', 'pub.dev', 'args-2.7.0'),
        'name: args\ndependencies:\n  meta:\n',
      );

      final result = await reader.read(
        packageName: 'args',
        lockEntry: _y('''
source: hosted
version: "2.7.0"
description: { name: args, url: "https://pub.dev" }
'''),
      );

      expect(result, isNotNull);
      expect(result!['name'], 'args');
    });

    test('missing hosted pubspec returns null', () async {
      final result = await reader.read(
        packageName: 'ghost',
        lockEntry: _y('source: hosted\nversion: "1.0.0"'),
      );
      expect(result, isNull);
    });

    test('hosted without version returns null', () async {
      final result = await reader.read(
        packageName: 'args',
        lockEntry: _y('source: hosted'),
      );
      expect(result, isNull);
    });
  });

  group('sdk source', () {
    test('reads from <sdk>/packages/<name>/pubspec.yaml', () async {
      _writePubspec(
        p.join(flutterSdk, 'packages', 'flutter'),
        'name: flutter\ndependencies:\n  sky_engine:\n',
      );

      final result = await reader.read(
        packageName: 'flutter',
        lockEntry: _y('source: sdk\ndescription: flutter\nversion: "0.0.0"'),
      );

      expect(result, isNotNull);
      expect(result!['name'], 'flutter');
    });

    test('sky_engine falls back to <sdk>/bin/cache/pkg/<name>/pubspec.yaml',
        () async {
      _writePubspec(
        p.join(flutterSdk, 'bin', 'cache', 'pkg', 'sky_engine'),
        'name: sky_engine\n',
      );

      final result = await reader.read(
        packageName: 'sky_engine',
        lockEntry: _y('source: sdk\ndescription: flutter\nversion: "0.0.0"'),
      );

      expect(result, isNotNull);
      expect(result!['name'], 'sky_engine');
    });

    test('sdk package with no matching path returns null (silent leaf)',
        () async {
      final result = await reader.read(
        packageName: 'unknown_sdk_pkg',
        lockEntry: _y('source: sdk\ndescription: flutter\nversion: "0.0.0"'),
      );
      expect(result, isNull);
    });

    test('flutterSdkPath null returns null for sdk source', () async {
      final nullSdkReader = FilePubspecReader(
        pubCachePath: pubCache,
        flutterSdkPath: null,
        projectRoot: projectRoot,
      );

      final result = await nullSdkReader.read(
        packageName: 'flutter',
        lockEntry: _y('source: sdk\ndescription: flutter\nversion: "0.0.0"'),
      );
      expect(result, isNull);
    });
  });

  group('path source', () {
    test('resolves relative path against projectRoot', () async {
      _writePubspec(
        p.join(projectRoot, '..', 'sibling_pkg'),
        'name: sibling\n',
      );

      final result = await reader.read(
        packageName: 'sibling',
        lockEntry: _y('''
source: path
version: "0.0.1"
description:
  path: "../sibling_pkg"
  relative: true
'''),
      );

      expect(result, isNotNull);
      expect(result!['name'], 'sibling');
    });

    test('absolute path is used as-is', () async {
      final abs = p.join(tmp.path, 'abs_pkg');
      _writePubspec(abs, 'name: abs\n');

      final result = await reader.read(
        packageName: 'abs',
        lockEntry: _y('''
source: path
version: "0.0.1"
description:
  path: ${_yamlString(abs)}
  relative: false
'''),
      );

      expect(result, isNotNull);
      expect(result!['name'], 'abs');
    });

    test('missing path pubspec returns null', () async {
      final result = await reader.read(
        packageName: 'ghost',
        lockEntry: _y('''
source: path
description:
  path: "../nope"
  relative: true
'''),
      );
      expect(result, isNull);
    });
  });

  group('git source', () {
    test('reads from pub-cache/git/<name>-<resolved-ref>/', () async {
      _writePubspec(
        p.join(pubCache, 'git', 'foo-abc123def456'),
        'name: foo\n',
      );

      final result = await reader.read(
        packageName: 'foo',
        lockEntry: _y('''
source: git
version: "0.0.1"
description:
  url: "https://github.com/example/foo.git"
  ref: main
  resolved-ref: abc123def456
  path: "."
'''),
      );

      expect(result, isNotNull);
      expect(result!['name'], 'foo');
    });

    test('follows description.path subdirectory', () async {
      _writePubspec(
        p.join(pubCache, 'git', 'mono-def789', 'packages', 'inner'),
        'name: inner\n',
      );

      final result = await reader.read(
        packageName: 'mono',
        lockEntry: _y('''
source: git
version: "0.0.1"
description:
  url: "https://github.com/example/mono.git"
  ref: main
  resolved-ref: def789
  path: "packages/inner"
'''),
      );

      expect(result, isNotNull);
      expect(result!['name'], 'inner');
    });

    test('git without resolved-ref returns null', () async {
      final result = await reader.read(
        packageName: 'foo',
        lockEntry: _y('''
source: git
description:
  url: "https://github.com/example/foo.git"
'''),
      );
      expect(result, isNull);
    });
  });

  group('unknown source', () {
    test('returns null for sources we do not handle', () async {
      final result = await reader.read(
        packageName: 'mystery',
        lockEntry: _y('source: hg\nversion: "1.0.0"'),
      );
      expect(result, isNull);
    });

    test('missing source returns null', () async {
      final result = await reader.read(
        packageName: 'mystery',
        lockEntry: _y('version: "1.0.0"'),
      );
      expect(result, isNull);
    });
  });
}
