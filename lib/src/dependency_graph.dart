import 'dart:collection';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'package_locator.dart';

/// Resolves a package's `pubspec.yaml` content given its entry from the
/// project's `pubspec.lock`.
///
/// The graph walker depends only on this interface — it never touches the
/// filesystem directly. Tests supply an in-memory implementation; the runtime
/// production code uses `FilePubspecReader` (Phase 2) to read from the pub
/// cache, Flutter SDK, path sources, and git checkouts.
abstract class PubspecReader {
  /// Returns the parsed `pubspec.yaml` for [packageName], or `null` if the
  /// pubspec cannot be located or parsed. A `null` result causes the graph
  /// walker to treat the package as a leaf (no further descent), which is the
  /// conservative choice — we prefer including a package without following
  /// its transitives over dropping it entirely.
  ///
  /// [lockEntry] is the `pubspec.lock` entry for this package (the map under
  /// `packages.<name>`), so the reader can branch on `source` and use
  /// `description` / `version` to locate the file.
  Future<YamlMap?> read({
    required String packageName,
    required YamlMap lockEntry,
  });
}

/// Computes the set of package names reachable from the root project's
/// runtime dependencies, excluding `dev_dependencies` at every level of the
/// graph.
///
/// Usage (Phase 1 — filesystem-independent):
/// ```dart
/// final graph = RuntimeDependencyGraph(
///   rootPubspec: parsedRootPubspecYaml,
///   pubspecLockPackages: parsedLockPackagesMap,
///   reader: myPubspecReader,
/// );
/// final runtimeNames = await graph.compute();
/// ```
///
/// The set does NOT include the root project itself.
class RuntimeDependencyGraph {
  RuntimeDependencyGraph({
    required YamlMap rootPubspec,
    required YamlMap pubspecLockPackages,
    required PubspecReader reader,
  })  : _rootPubspec = rootPubspec,
        _lockPackages = pubspecLockPackages,
        _reader = reader;

  final YamlMap _rootPubspec;
  final YamlMap _lockPackages;
  final PubspecReader _reader;

  /// Performs a BFS from the root `dependencies:` keys, following each
  /// package's own `dependencies:` (never `dev_dependencies:` or
  /// `dependency_overrides:`). Visited set is the return value.
  Future<Set<String>> compute() async {
    final visited = <String>{};
    final queue = Queue<String>();

    for (final name in _extractDependencyNames(_rootPubspec)) {
      queue.add(name);
    }

    while (queue.isNotEmpty) {
      final name = queue.removeFirst();
      if (!visited.add(name)) continue;

      final lockEntry = _lockPackages[name];
      if (lockEntry is! YamlMap) continue;

      final pubspec = await _reader.read(
        packageName: name,
        lockEntry: lockEntry,
      );
      if (pubspec == null) continue;

      for (final depName in _extractDependencyNames(pubspec)) {
        if (!visited.contains(depName)) {
          queue.add(depName);
        }
      }
    }

    return visited;
  }

  /// Returns the keys under the `dependencies:` block of [pubspec].
  /// Explicitly ignores `dev_dependencies:` and `dependency_overrides:` — this
  /// is the heart of the dev-exclusion rule, and it must be applied at every
  /// node (not just the root), otherwise a runtime package's dev tools would
  /// leak into the runtime set.
  Iterable<String> _extractDependencyNames(YamlMap pubspec) {
    final deps = pubspec['dependencies'];
    if (deps is! YamlMap) return const [];
    return deps.keys.map((k) => k.toString());
  }
}

/// Reads package pubspecs from the real filesystem for the four source types
/// that `pubspec.lock` produces (`hosted`, `sdk`, `path`, `git`).
///
/// Delegates "where does this package live?" to [PackageLocator] and keeps only
/// the read-parse-tolerate logic: given the located directory, read its
/// `pubspec.yaml`, and treat a missing/unparseable file as a leaf (null).
class FilePubspecReader implements PubspecReader {
  FilePubspecReader({required this.locator});

  final PackageLocator locator;

  @override
  Future<YamlMap?> read({
    required String packageName,
    required YamlMap lockEntry,
  }) async {
    final dir = await locator.packageRootDir(
      name: packageName,
      lockEntry: lockEntry,
    );
    if (dir == null) return null;
    // SDK packages are located by directory existence, so a missing pubspec
    // there is an SDK-layout we don't model rather than an error — stay quiet.
    // For hosted/path/git a missing pubspec is worth a lightweight note.
    final source = lockEntry['source']?.toString();
    return _tryReadPubspec(
      p.join(dir.path, 'pubspec.yaml'),
      warnOnMissing: source != 'sdk',
    );
  }

  Future<YamlMap?> _tryReadPubspec(
    String filePath, {
    bool warnOnMissing = true,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      if (warnOnMissing) {
        // Keep this log lightweight — the graph walker recovers by treating
        // the package as a leaf, so we don't want to alarm users. Just
        // enough signal to notice a systemic cache miss during --verbose.
        print('  [graph] pubspec not found at $filePath (treating as leaf)');
      }
      return null;
    }
    try {
      final content = await file.readAsString();
      final parsed = loadYaml(content);
      return parsed is YamlMap ? parsed : null;
    } on Object catch (e) {
      print('  [graph] failed to read pubspec at $filePath: $e');
      return null;
    }
  }
}
