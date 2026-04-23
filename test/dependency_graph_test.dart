import 'package:flutter_oss_manager/src/dependency_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Parse a YAML literal for test readability.
YamlMap _y(String src) => loadYaml(src) as YamlMap;

/// In-memory [PubspecReader]. Returns the pubspec keyed by package name,
/// or `null` to simulate a missing/unreadable pubspec. Records the sequence
/// of `read` calls so tests can assert traversal behavior.
class FakePubspecReader implements PubspecReader {
  FakePubspecReader(this._pubspecs);

  final Map<String, YamlMap?> _pubspecs;
  final List<String> readCalls = [];

  @override
  Future<YamlMap?> read({
    required String packageName,
    required YamlMap lockEntry,
  }) async {
    readCalls.add(packageName);
    return _pubspecs[packageName];
  }
}

/// Synthesize a minimal `pubspec.lock` `packages:` map — every referenced
/// package gets a stub entry so the graph walker will call the reader. The
/// reader's return value is what determines actual pubspec content.
YamlMap _stubLock(Iterable<String> names) {
  if (names.isEmpty) return _y('{}');
  final buf = StringBuffer();
  for (final name in names) {
    buf.writeln('$name:');
    buf.writeln('  dependency: "transitive"');
    buf.writeln('  source: hosted');
    buf.writeln('  version: "1.0.0"');
  }
  return loadYaml(buf.toString()) as YamlMap;
}

void main() {
  group('RuntimeDependencyGraph', () {
    test('basic transitive traversal includes all reachable packages', () async {
      final root = _y('''
dependencies:
  A:
  B:
''');
      final reader = FakePubspecReader({
        'A': _y('dependencies: { C: }'),
        'B': _y('dependencies: { D: }'),
        'C': _y('dependencies: {}'),
        'D': _y('dependencies: {}'),
      });

      final result = await RuntimeDependencyGraph(
        rootPubspec: root,
        pubspecLockPackages: _stubLock(['A', 'B', 'C', 'D']),
        reader: reader,
      ).compute();

      expect(result, {'A', 'B', 'C', 'D'});
    });

    test('dev_dependencies at root are excluded along with their transitives',
        () async {
      final root = _y('''
dependencies:
  A:
dev_dependencies:
  X:
''');
      final reader = FakePubspecReader({
        'A': _y('dependencies: {}'),
        'X': _y('dependencies: { Y: }'),
        'Y': _y('dependencies: {}'),
      });

      final result = await RuntimeDependencyGraph(
        rootPubspec: root,
        pubspecLockPackages: _stubLock(['A', 'X', 'Y']),
        reader: reader,
      ).compute();

      expect(result, {'A'});
      expect(result, isNot(contains('X')));
      expect(result, isNot(contains('Y')));
    });

    test('package reachable from both runtime and dev paths is included',
        () async {
      final root = _y('''
dependencies:
  A:
dev_dependencies:
  B:
''');
      final reader = FakePubspecReader({
        'A': _y('dependencies: { S: }'),
        'B': _y('dependencies: { S: }'),
        'S': _y('dependencies: {}'),
      });

      final result = await RuntimeDependencyGraph(
        rootPubspec: root,
        pubspecLockPackages: _stubLock(['A', 'B', 'S']),
        reader: reader,
      ).compute();

      expect(result, {'A', 'S'});
    });

    test('nested dev_dependencies inside a runtime package are not followed',
        () async {
      final root = _y('dependencies: { A: }');
      final reader = FakePubspecReader({
        'A': _y('''
dependencies:
  C:
dev_dependencies:
  Z:
'''),
        'C': _y('dependencies: {}'),
        'Z': _y('dependencies: { ZZ: }'),
        'ZZ': _y('dependencies: {}'),
      });

      final result = await RuntimeDependencyGraph(
        rootPubspec: root,
        pubspecLockPackages: _stubLock(['A', 'C', 'Z', 'ZZ']),
        reader: reader,
      ).compute();

      expect(result, {'A', 'C'});
      expect(result, isNot(contains('Z')));
      expect(result, isNot(contains('ZZ')));
    });

    test('dependency_overrides at root does not expand the name set', () async {
      final root = _y('''
dependencies:
  A:
dependency_overrides:
  OVERRIDE_ONLY:
''');
      final reader = FakePubspecReader({
        'A': _y('dependencies: {}'),
        'OVERRIDE_ONLY': _y('dependencies: {}'),
      });

      final result = await RuntimeDependencyGraph(
        rootPubspec: root,
        pubspecLockPackages: _stubLock(['A', 'OVERRIDE_ONLY']),
        reader: reader,
      ).compute();

      expect(result, {'A'});
      expect(result, isNot(contains('OVERRIDE_ONLY')));
    });

    test('missing pubspec (reader returns null) treats node as leaf', () async {
      final root = _y('dependencies: { A: }');
      final reader = FakePubspecReader({
        'A': _y('dependencies: { B: }'),
        'B': null,
        'C': _y('dependencies: {}'),
      });

      final result = await RuntimeDependencyGraph(
        rootPubspec: root,
        pubspecLockPackages: _stubLock(['A', 'B', 'C']),
        reader: reader,
      ).compute();

      expect(result, {'A', 'B'});
      expect(result, isNot(contains('C')));
    });

    test('cyclic dependency graph terminates without infinite loop', () async {
      final root = _y('dependencies: { A: }');
      final reader = FakePubspecReader({
        'A': _y('dependencies: { B: }'),
        'B': _y('dependencies: { A: }'),
      });

      final result = await RuntimeDependencyGraph(
        rootPubspec: root,
        pubspecLockPackages: _stubLock(['A', 'B']),
        reader: reader,
      ).compute();

      expect(result, {'A', 'B'});
      expect(reader.readCalls, ['A', 'B']);
    });

    test('package absent from pubspec.lock is still recorded but not expanded',
        () async {
      final root = _y('dependencies: { A: }');
      final reader = FakePubspecReader({
        'A': _y('dependencies: { GHOST: }'),
      });

      final result = await RuntimeDependencyGraph(
        rootPubspec: root,
        pubspecLockPackages: _stubLock(['A']),
        reader: reader,
      ).compute();

      expect(result, {'A', 'GHOST'});
      expect(reader.readCalls, ['A']);
    });

    test('empty or missing root dependencies: block yields empty set',
        () async {
      final reader = FakePubspecReader({});

      final emptyBlock = await RuntimeDependencyGraph(
        rootPubspec: _y('dependencies: {}'),
        pubspecLockPackages: _stubLock([]),
        reader: reader,
      ).compute();
      expect(emptyBlock, isEmpty);

      final missingBlock = await RuntimeDependencyGraph(
        rootPubspec: _y('name: myapp'),
        pubspecLockPackages: _stubLock([]),
        reader: reader,
      ).compute();
      expect(missingBlock, isEmpty);
    });
  });
}
