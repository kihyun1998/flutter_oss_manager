import 'package:flutter_oss_manager/src/dependency_graph.dart';
import 'package:flutter_oss_manager/src/license_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

YamlMap _y(String src) => loadYaml(src) as YamlMap;

class FakePubspecReader implements PubspecReader {
  FakePubspecReader(this._pubspecs);

  final Map<String, YamlMap?> _pubspecs;

  @override
  Future<YamlMap?> read({
    required String packageName,
    required YamlMap lockEntry,
  }) async =>
      _pubspecs[packageName];
}

/// Build a minimal `pubspec.lock` `packages:` map from package names.
YamlMap _lock(Iterable<String> names) {
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

List<MapEntry> _entriesFor(YamlMap lock) => lock.entries.toList();

void main() {
  group('LicenseGenerator.filterToRuntimeEntries', () {
    test('keeps only runtime-reachable packages', () async {
      final root = _y('''
dependencies:
  http:
dev_dependencies:
  build_runner:
''');
      final lock = _lock(['http', 'async', 'build_runner', 'analyzer']);
      final reader = FakePubspecReader({
        'http': _y('dependencies: { async: }'),
        'async': _y('dependencies: {}'),
        'build_runner': _y('dependencies: { analyzer: }'),
        'analyzer': _y('dependencies: {}'),
      });

      final filtered = await LicenseGenerator().filterToRuntimeEntries(
        entries: _entriesFor(lock),
        rootPubspec: root,
        lockPackages: lock,
        reader: reader,
      );

      final names = filtered.map((e) => e.key.toString()).toSet();
      expect(names, {'http', 'async'});
      expect(names, isNot(contains('build_runner')));
      expect(names, isNot(contains('analyzer')));
    });

    test('shared package reachable from both runtime and dev is kept',
        () async {
      final root = _y('''
dependencies:
  app_dep:
dev_dependencies:
  dev_tool:
''');
      final lock = _lock(['app_dep', 'dev_tool', 'shared']);
      final reader = FakePubspecReader({
        'app_dep': _y('dependencies: { shared: }'),
        'dev_tool': _y('dependencies: { shared: }'),
        'shared': _y('dependencies: {}'),
      });

      final filtered = await LicenseGenerator().filterToRuntimeEntries(
        entries: _entriesFor(lock),
        rootPubspec: root,
        lockPackages: lock,
        reader: reader,
      );

      final names = filtered.map((e) => e.key.toString()).toSet();
      expect(names, {'app_dep', 'shared'});
      expect(names, isNot(contains('dev_tool')));
    });

    test('preserves original entry order of the retained packages', () async {
      final root = _y('''
dependencies:
  a:
  c:
''');
      // Lock order: c, b, a, d — b and d are dev-only transitives.
      final lock = _lock(['c', 'b', 'a', 'd']);
      final reader = FakePubspecReader({
        'a': _y('dependencies: {}'),
        'b': _y('dependencies: { d: }'),
        'c': _y('dependencies: {}'),
        'd': _y('dependencies: {}'),
      });

      final filtered = await LicenseGenerator().filterToRuntimeEntries(
        entries: _entriesFor(lock),
        rootPubspec: root,
        lockPackages: lock,
        reader: reader,
      );

      // Order should follow the lock's original sequence, with b and d
      // dropped.
      expect(filtered.map((e) => e.key.toString()).toList(), ['c', 'a']);
    });

    test('empty runtime set when root has no dependencies: block', () async {
      final root = _y('''
name: myapp
dev_dependencies:
  only_dev:
''');
      final lock = _lock(['only_dev']);
      final reader = FakePubspecReader({
        'only_dev': _y('dependencies: {}'),
      });

      final filtered = await LicenseGenerator().filterToRuntimeEntries(
        entries: _entriesFor(lock),
        rootPubspec: root,
        lockPackages: lock,
        reader: reader,
      );

      expect(filtered, isEmpty);
    });
  });
}
