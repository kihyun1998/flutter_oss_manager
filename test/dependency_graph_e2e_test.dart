import 'dart:io';

import 'package:flutter_oss_manager/src/dependency_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// End-to-end: [RuntimeDependencyGraph] + [FilePubspecReader] traversing a
/// real on-disk pub cache. Catches wiring bugs that the Fake/File tests
/// alone miss — e.g. reader path construction or BFS recursion into a
/// sub-source that exists in the cache.

YamlMap _y(String src) => loadYaml(src) as YamlMap;

/// Writes `<dir>/pubspec.yaml` with the given content.
void _writePubspec(String dir, String content) {
  Directory(dir).createSync(recursive: true);
  File(p.join(dir, 'pubspec.yaml')).writeAsStringSync(content);
}

/// Build a pubspec.lock packages map (as YamlMap) from a manifest.
YamlMap _lock(Map<String, Map<String, dynamic>> manifest) {
  final buf = StringBuffer();
  manifest.forEach((name, spec) {
    buf.writeln('$name:');
    buf.writeln('  dependency: "${spec['dependency'] ?? 'transitive'}"');
    buf.writeln('  source: ${spec['source']}');
    buf.writeln('  version: "${spec['version'] ?? '1.0.0'}"');
    final description = spec['description'];
    if (description is String) {
      buf.writeln('  description: $description');
    } else if (description is Map) {
      buf.writeln('  description:');
      description.forEach((k, v) {
        buf.writeln('    $k: ${_yamlScalar(v)}');
      });
    }
  });
  return loadYaml(buf.toString()) as YamlMap;
}

String _yamlScalar(Object? v) {
  if (v is bool || v is num) return v.toString();
  final s = v.toString();
  return '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
}

void main() {
  late Directory tmp;
  late String pubCache;
  late String flutterSdk;
  late String projectRoot;
  late FilePubspecReader reader;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('graph_e2e_test_');
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

  test('full pipeline: root → hosted → hosted chain is walked correctly',
      () async {
    // Simulate: root → http → async → collection.
    _writePubspec(
      p.join(pubCache, 'hosted', 'pub.dev', 'http-1.0.0'),
      'name: http\ndependencies:\n  async:\n',
    );
    _writePubspec(
      p.join(pubCache, 'hosted', 'pub.dev', 'async-2.0.0'),
      'name: async\ndependencies:\n  collection:\n',
    );
    _writePubspec(
      p.join(pubCache, 'hosted', 'pub.dev', 'collection-1.0.0'),
      'name: collection\n',
    );

    final root = _y('dependencies: { http: }');
    final lock = _lock({
      'http': {'source': 'hosted', 'version': '1.0.0'},
      'async': {'source': 'hosted', 'version': '2.0.0'},
      'collection': {'source': 'hosted', 'version': '1.0.0'},
    });

    final result = await RuntimeDependencyGraph(
      rootPubspec: root,
      pubspecLockPackages: lock,
      reader: reader,
    ).compute();

    expect(result, {'http', 'async', 'collection'});
  });

  test('full pipeline: mixed sources (hosted + sdk + path) resolve in one walk',
      () async {
    // root depends on a hosted package that depends on an SDK package,
    // and also a path package that depends on another hosted package.
    _writePubspec(
      p.join(pubCache, 'hosted', 'pub.dev', 'app_lib-1.0.0'),
      'name: app_lib\ndependencies:\n  flutter:\n    sdk: flutter\n',
    );
    _writePubspec(
      p.join(flutterSdk, 'packages', 'flutter'),
      'name: flutter\ndependencies:\n  sky_engine:\n    sdk: flutter\n',
    );
    _writePubspec(
      p.join(flutterSdk, 'bin', 'cache', 'pkg', 'sky_engine'),
      'name: sky_engine\n',
    );

    // Path dependency sitting next to the project.
    _writePubspec(
      p.join(projectRoot, '..', 'local_helper'),
      'name: local_helper\ndependencies:\n  utils:\n',
    );
    _writePubspec(
      p.join(pubCache, 'hosted', 'pub.dev', 'utils-1.0.0'),
      'name: utils\n',
    );

    final root = _y('''
dependencies:
  app_lib:
  local_helper:
''');

    final lock = _lock({
      'app_lib': {'source': 'hosted', 'version': '1.0.0'},
      'flutter': {
        'source': 'sdk',
        'description': 'flutter',
        'version': '0.0.0'
      },
      'sky_engine': {
        'source': 'sdk',
        'description': 'flutter',
        'version': '0.0.0'
      },
      'local_helper': {
        'source': 'path',
        'description': {'path': '../local_helper', 'relative': true},
      },
      'utils': {'source': 'hosted', 'version': '1.0.0'},
    });

    final result = await RuntimeDependencyGraph(
      rootPubspec: root,
      pubspecLockPackages: lock,
      reader: reader,
    ).compute();

    expect(result, {
      'app_lib',
      'flutter',
      'sky_engine',
      'local_helper',
      'utils',
    });
  });

  test('full pipeline: dev subtree (real files present) is not traversed',
      () async {
    // Both runtime and dev packages have real pubspecs on disk. Only the
    // runtime subtree should be walked.
    _writePubspec(
      p.join(pubCache, 'hosted', 'pub.dev', 'runtime_pkg-1.0.0'),
      'name: runtime_pkg\ndependencies:\n  runtime_tr:\n',
    );
    _writePubspec(
      p.join(pubCache, 'hosted', 'pub.dev', 'runtime_tr-1.0.0'),
      'name: runtime_tr\n',
    );
    _writePubspec(
      p.join(pubCache, 'hosted', 'pub.dev', 'dev_pkg-1.0.0'),
      'name: dev_pkg\ndependencies:\n  dev_tr:\n',
    );
    _writePubspec(
      p.join(pubCache, 'hosted', 'pub.dev', 'dev_tr-1.0.0'),
      'name: dev_tr\n',
    );

    final root = _y('''
dependencies:
  runtime_pkg:
dev_dependencies:
  dev_pkg:
''');

    final lock = _lock({
      'runtime_pkg': {'source': 'hosted', 'version': '1.0.0'},
      'runtime_tr': {'source': 'hosted', 'version': '1.0.0'},
      'dev_pkg': {'source': 'hosted', 'version': '1.0.0'},
      'dev_tr': {'source': 'hosted', 'version': '1.0.0'},
    });

    final result = await RuntimeDependencyGraph(
      rootPubspec: root,
      pubspecLockPackages: lock,
      reader: reader,
    ).compute();

    expect(result, {'runtime_pkg', 'runtime_tr'});
    expect(result, isNot(contains('dev_pkg')));
    expect(result, isNot(contains('dev_tr')));
  });

  test(
      'full pipeline: path package with its own dev_dependencies is not '
      'followed into dev', () async {
    // Mirrors the flutter_oss_manager → args/yaml case from the Phase 4
    // verification: a path dependency brings in its own runtime transitives
    // but NOT its dev_dependencies.
    _writePubspec(
      p.join(projectRoot, '..', 'mypkg'),
      '''
name: mypkg
dependencies:
  needed:
dev_dependencies:
  test_only:
''',
    );
    _writePubspec(
      p.join(pubCache, 'hosted', 'pub.dev', 'needed-1.0.0'),
      'name: needed\n',
    );
    _writePubspec(
      p.join(pubCache, 'hosted', 'pub.dev', 'test_only-1.0.0'),
      'name: test_only\n',
    );

    final root = _y('dependencies: { mypkg: }');
    final lock = _lock({
      'mypkg': {
        'source': 'path',
        'description': {'path': '../mypkg', 'relative': true},
      },
      'needed': {'source': 'hosted', 'version': '1.0.0'},
      'test_only': {'source': 'hosted', 'version': '1.0.0'},
    });

    final result = await RuntimeDependencyGraph(
      rootPubspec: root,
      pubspecLockPackages: lock,
      reader: reader,
    ).compute();

    expect(result, {'mypkg', 'needed'});
    expect(result, isNot(contains('test_only')));
  });

  test('full pipeline: missing on-disk pubspec is tolerated', () async {
    // Lock entry says hosted, but the cache directory is empty. Graph
    // should still return the node as a leaf and continue the walk.
    final root = _y('dependencies: { orphan:, neighbor: }');
    _writePubspec(
      p.join(pubCache, 'hosted', 'pub.dev', 'neighbor-1.0.0'),
      'name: neighbor\n',
    );
    final lock = _lock({
      'orphan': {'source': 'hosted', 'version': '1.0.0'},
      'neighbor': {'source': 'hosted', 'version': '1.0.0'},
    });

    final result = await RuntimeDependencyGraph(
      rootPubspec: root,
      pubspecLockPackages: lock,
      reader: reader,
    ).compute();

    expect(result, {'orphan', 'neighbor'});
  });
}
