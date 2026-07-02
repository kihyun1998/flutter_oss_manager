import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Single authority on **where a dependency's source lives on disk**.
///
/// Given a package name and its `pubspec.lock` entry, resolves the package's
/// root [Directory] for every pub source type (hosted / sdk / path / git), so
/// filesystem-layout knowledge (e.g. `hosted/pub.dev/<name>-<version>`) lives
/// in exactly one place. Returns directories only — deciding which files
/// inside a directory count as licenses (or manifests) is the caller's concern.
///
/// Receives its environment roots pre-computed; it never probes env vars or
/// spawns `flutter --version` itself, which keeps it pure and temp-dir-testable.
class PackageLocator {
  PackageLocator({
    required this.pubCachePath,
    required this.flutterSdkPath,
    required this.projectRoot,
  });

  final String pubCachePath;

  /// Flutter SDK root. `null` means SDK packages cannot be located.
  final String? flutterSdkPath;

  /// Used to resolve relative `path:` sources from `pubspec.lock`.
  final String projectRoot;

  Directory get pubCacheDir => Directory(pubCachePath);

  Directory? get flutterSdkRoot =>
      flutterSdkPath == null ? null : Directory(flutterSdkPath!);

  /// Root directory of [name]'s source, for any source type. Returns `null`
  /// when the entry lacks the fields needed to locate it (or, for sdk, when no
  /// candidate directory exists). Does not verify existence for hosted / path /
  /// git — the caller checks for the file it wants inside the returned dir.
  Future<Directory?> packageRootDir({
    required String name,
    required YamlMap lockEntry,
  }) async {
    final source = lockEntry['source']?.toString();
    switch (source) {
      case 'hosted':
        final version = lockEntry['version']?.toString();
        if (version == null) return null;
        return Directory(
          p.join(pubCachePath, 'hosted', 'pub.dev', '$name-$version'),
        );
      case 'sdk':
        return _sdkDir(name);
      case 'path':
        final description = lockEntry['description'];
        if (description is! YamlMap) return null;
        final rawPath = description['path']?.toString();
        if (rawPath == null) return null;
        final isRelative = description['relative'] == true;
        return Directory(isRelative ? p.join(projectRoot, rawPath) : rawPath);
      case 'git':
        final description = lockEntry['description'];
        if (description is! YamlMap) return null;
        final resolvedRef = description['resolved-ref']?.toString();
        if (resolvedRef == null) return null;
        final subPath = description['path']?.toString() ?? '.';
        // pub checks git deps out to <pub-cache>/git/<name>-<resolved-ref>/.
        return Directory(
          p.join(pubCachePath, 'git', '$name-$resolvedRef', subPath),
        );
      default:
        return null;
    }
  }

  /// Most SDK packages live under `<sdk>/packages/<name>/`; `sky_engine` is the
  /// known exception at `<sdk>/bin/cache/pkg/<name>/`. Returns the first
  /// candidate directory that exists, or `null` (silent leaf) if neither does
  /// — that mostly means an SDK layout we don't model, not a real error.
  Future<Directory?> _sdkDir(String name) async {
    final root = flutterSdkPath;
    if (root == null) return null;
    final candidates = [
      Directory(p.join(root, 'packages', name)),
      Directory(p.join(root, 'bin', 'cache', 'pkg', name)),
    ];
    for (final dir in candidates) {
      if (await dir.exists()) return dir;
    }
    return null;
  }
}
