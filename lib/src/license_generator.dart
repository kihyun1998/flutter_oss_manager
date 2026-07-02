import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'dependency_graph.dart';
import 'generated_files.dart';
import 'license_cache.dart';
import 'license_matcher.dart';
import 'models/oss_license.dart';
import 'package_locator.dart';
import 'pub_license_client.dart';

/// Result of the 3-stage SPDX resolution pipeline.
class _ResolvedSpdx {
  const _ResolvedSpdx(this.spdx, this.source);
  final String spdx;
  final String source;
}

/// A utility class responsible for generating and scanning open-source licenses.
///
/// This class provides methods to generate license information from a single file
/// or to scan an entire Flutter project's dependencies to collect and summarize
/// their licenses.
class LicenseGenerator {
  LicenseGenerator({
    PubLicenseClient? pubClient,
    LicenseCache? cache,
    bool offline = false,
    int concurrency = 8,
  })  : _pubClient = pubClient ?? HttpPubLicenseClient(),
        _cache = cache,
        _offline = offline,
        _concurrency = concurrency;

  final PubLicenseClient _pubClient;
  final LicenseCache? _cache;
  final bool _offline;
  final int _concurrency;

  /// Single authority on where dependencies live on disk, shared by the
  /// runtime dependency reader and the hosted-license lookup. Built once per
  /// [scanPackages] run (env roots resolved once), so the two no longer
  /// duplicate the pub-cache layout.
  PackageLocator? _packageLocator;

  static const List<String> _licenseFileNames = [
    'LICENSE',
    'LICENSE.txt',
    'COPYING',
    'COPYING.txt',
    'LICENCE',
    'LICENCE.txt',
  ];

  /// Licenses that may cause legal issues in commercial or proprietary software.
  /// These licenses typically require source code disclosure or have copyleft requirements.
  static const List<String> _problematicLicenses = [
    'GPL-2.0',
    'GPL-3.0',
    'LGPL-2.1',
    'LGPL-3.0',
    'AGPL-3.0',
  ];

  String _readLicenseFile(String filePath) {
    return File(filePath).readAsStringSync();
  }

  /// Computes the runtime-reachable subset of [entries] by walking the
  /// dependency graph from the root project's `dependencies:` section,
  /// excluding `dev_dependencies:` at every level.
  ///
  /// Exposed as a pure function (no direct filesystem access) so tests can
  /// drive it with a [FakePubspecReader]. Logs the kept/skipped counts for
  /// CLI transparency.
  Future<List<MapEntry>> filterToRuntimeEntries({
    required List<MapEntry> entries,
    required YamlMap rootPubspec,
    required YamlMap lockPackages,
    required PubspecReader reader,
  }) async {
    final runtimeNames = await RuntimeDependencyGraph(
      rootPubspec: rootPubspec,
      pubspecLockPackages: lockPackages,
      reader: reader,
    ).compute();
    final filtered =
        entries.where((e) => runtimeNames.contains(e.key.toString())).toList();
    final skipped = entries.length - filtered.length;
    print(
      'Runtime-only mode: keeping ${filtered.length} packages, '
      'skipping $skipped dev/dev-transitive packages.',
    );
    return filtered;
  }

  /// Test-only seam around [_resolveSpdx]. The `ForTesting` suffix signals
  /// that production code should not call this.
  Future<({String spdx, String source})> resolveSpdxForTesting({
    required String packageName,
    required String version,
    required String licenseText,
  }) async {
    final r = await _resolveSpdx(
      packageName: packageName,
      version: version,
      licenseText: licenseText,
    );
    return (spdx: r.spdx, source: r.source);
  }

  /// 3-stage SPDX resolution: cache → pub.dev API → heuristic.
  /// Hosted packages only; SDK packages keep the heuristic-only path.
  Future<_ResolvedSpdx> _resolveSpdx({
    required String packageName,
    required String version,
    required String licenseText,
  }) async {
    final cache = _cache;

    final cached = cache?.get(packageName, version);
    if (cached != null) {
      return _ResolvedSpdx(cached.spdx, 'cache');
    }

    if (!_offline) {
      final spdx = await _pubClient.fetchSpdxId(packageName, version);
      if (spdx != null) {
        cache?.put(
          packageName,
          version,
          CachedLicense(
            spdx: spdx,
            source: CacheSource.pubApi,
            fetchedAt: DateTime.now().toUtc(),
          ),
        );
        return _ResolvedSpdx(spdx, 'pub-api');
      }
    }

    final heuristic = matchLicense(licenseText).spdx;
    final source =
        heuristic == 'Unknown' ? CacheSource.negative : CacheSource.heuristic;
    cache?.put(
      packageName,
      version,
      CachedLicense(
        spdx: heuristic,
        source: source,
        fetchedAt: DateTime.now().toUtc(),
      ),
    );
    return _ResolvedSpdx(
      heuristic,
      source == CacheSource.negative ? 'negative' : 'heuristic',
    );
  }

  /// Writes the 4 generated files (main + stub/io/web decoders). Silently
  /// overwrites any existing files at the resolved paths — the `.g.dart`
  /// suffix signals that these are tool-owned and will be regenerated.
  void _writeGeneratedFiles(String outputPath, List<OssLicense> licenses) {
    final files = renderGeneratedFiles(licenses, outputPath);
    for (final f in files.all) {
      final file = File(f.path);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(f.content);
    }

    print('Generated 4 files:');
    print('  main: ${files.main.path}');
    print('  stub: ${files.stub.path}');
    print('  io:   ${files.io.path}');
    print('  web:  ${files.web.path}');
  }

  /// Generates a single [OssLicense] object from a specified license file.
  ///
  /// This method is useful for including a project's own license or any other
  /// standalone license file into the generated `oss_licenses.g.dart`.
  ///
  /// [licenseFilePath] The absolute path to the license file to read.
  /// [outputFilePath] The path where the generated Dart file will be saved.
  ///                 Defaults to `lib/oss_licenses.g.dart` if not provided.
  void generateLicenses({
    String? licenseFilePath,
    String? outputFilePath,
  }) {
    if (licenseFilePath == null) {
      print(
          'Error: License file path must be provided for the generate command.');
      return;
    }
    final licenseContent = _readLicenseFile(licenseFilePath);
    final licenseSummary = matchLicense(licenseContent).spdx;

    final license = OssLicense(
      name: p.basenameWithoutExtension(licenseFilePath),
      version: 'N/A',
      licenseText: licenseContent,
      licenseSummary: licenseSummary,
    );

    _writeGeneratedFiles(
      outputFilePath ?? 'lib/oss_licenses.g.dart',
      [license],
    );
  }

  /// Scans all Flutter project dependencies from `pubspec.lock`,
  /// identifies their licenses, and generates a Dart file containing
  /// the collected license information.
  ///
  /// The generated file will contain a list of [OssLicense] objects.
  ///
  /// [outputFilePath] The path where the generated Dart file will be saved.
  ///                 Defaults to `lib/oss_licenses.g.dart` if not provided.
  Future<void> scanPackages({
    String? outputFilePath,
    bool runtimeOnly = false,
  }) async {
    print('Scanning packages for licenses...');
    final pubspecLockFile =
        File(p.join(Directory.current.path, 'pubspec.lock'));
    if (!pubspecLockFile.existsSync()) {
      print('Error: pubspec.lock not found. Run \'flutter pub get\' first.');
      return;
    }
    final pubspecLockContent = pubspecLockFile.readAsStringSync();
    final pubspecLockMap = loadYaml(pubspecLockContent) as YamlMap;

    await _cache?.load();

    final List<Map<String, String>> problematicPackages = [];

    final packages = pubspecLockMap['packages'] as YamlMap?;
    var entries = packages?.entries.toList() ?? const <MapEntry>[];

    // Only the runtime-only dependency walk needs the Flutter SDK path; the
    // hosted-license lookup uses pubCacheDir alone. Probing the SDK eagerly
    // would spawn `flutter --version` (and print an error when Flutter is
    // absent) on every plain scan — including pure-hosted/pure-Dart projects
    // that never touched it before. Resolve it only when runtime-only asks.
    _packageLocator = PackageLocator(
      pubCachePath: _getPubCacheDir(),
      flutterSdkPath: runtimeOnly ? await _getFlutterSdkPath() : null,
      projectRoot: Directory.current.path,
    );

    if (runtimeOnly) {
      final rootPubspecFile =
          File(p.join(Directory.current.path, 'pubspec.yaml'));
      if (!rootPubspecFile.existsSync()) {
        print('Error: pubspec.yaml not found at project root.');
        return;
      }
      final rootPubspec =
          loadYaml(rootPubspecFile.readAsStringSync()) as YamlMap;
      final reader = FilePubspecReader(locator: _packageLocator!);
      entries = await filterToRuntimeEntries(
        entries: entries,
        rootPubspec: rootPubspec,
        lockPackages: packages ?? YamlMap(),
        reader: reader,
      );
    }

    final results = List<OssLicense?>.filled(entries.length, null);

    // Process in fixed-size batches so that hosted packages hit pub.dev
    // concurrently (capped at [_concurrency]) without flooding the API or
    // reordering the output list.
    for (var i = 0; i < entries.length; i += _concurrency) {
      final end = (i + _concurrency) < entries.length
          ? i + _concurrency
          : entries.length;
      await Future.wait([
        for (var j = i; j < end; j++)
          _scanOne(entries[j]).then((lic) => results[j] = lic),
      ]);
    }

    final List<OssLicense> collectedLicenses = [
      for (final lic in results)
        if (lic != null) lic,
    ];

    for (final license in collectedLicenses) {
      if (_problematicLicenses.contains(license.licenseSummary)) {
        problematicPackages.add({
          'name': license.name,
          'version': license.version,
          'license': license.licenseSummary,
        });
      }
    }

    await _cache?.save();

    // Display warnings for problematic licenses
    if (problematicPackages.isNotEmpty) {
      _printLicenseWarnings(problematicPackages,
          runtimeOnlyActive: runtimeOnly);
    }

    if (outputFilePath != null) {
      _writeGeneratedFiles(
        p.join(Directory.current.path, outputFilePath),
        collectedLicenses,
      );
    } else {
      print('No output file path provided. Skipping .dart file generation.');
    }
  }

  Future<OssLicense?> _scanOne(MapEntry<dynamic, dynamic> entry) async {
    // Capture every [print] emitted while processing this one package into a
    // buffer, then flush the buffer as a single atomic write. Without this,
    // parallel batch workers interleave their "- name (ver)" headers and
    // "  → spdx [source]" results, making the log unreadable.
    final buf = StringBuffer();
    final result = await runZoned<Future<OssLicense?>>(
      () => _scanOneInner(entry),
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) => buf.writeln(line),
      ),
    );
    stdout.write(buf.toString());
    return result;
  }

  Future<OssLicense?> _scanOneInner(MapEntry<dynamic, dynamic> entry) async {
    final packageName = entry.key.toString();
    final packageInfo = entry.value as YamlMap;
    final source = packageInfo['source'].toString();

    if (source == 'hosted') {
      final packageVersion = packageInfo['version'].toString();
      print('- $packageName ($packageVersion) [hosted]');
      return _findAndSummarizeHostedLicense(packageName, packageInfo);
    } else if (source == 'sdk') {
      print('- $packageName [sdk]');
      return _findAndSummarizeSdkLicense(packageName);
    } else {
      print('- $packageName [unknown source: $source]');
      return null;
    }
  }

  Future<OssLicense?> _findAndSummarizeHostedLicense(
      String packageName, YamlMap lockEntry) async {
    final packageVersion = lockEntry['version'].toString();
    final dir = await _packageLocator!
        .packageRootDir(name: packageName, lockEntry: lockEntry);
    if (dir == null) {
      print('  No license file found for $packageName');
      return null;
    }
    final packagePath = dir.path;

    String? repositoryUrl;
    String? description;
    final packagePubspecFile = File(p.join(packagePath, 'pubspec.yaml'));
    if (packagePubspecFile.existsSync()) {
      final packagePubspecContent = packagePubspecFile.readAsStringSync();
      final packageYamlMap = loadYaml(packagePubspecContent) as YamlMap;
      repositoryUrl = packageYamlMap['repository']?.toString() ??
          packageYamlMap['homepage']?.toString();
      description = packageYamlMap['description']?.toString();
    }

    for (final fileName in _licenseFileNames) {
      final licenseFilePath = p.join(packagePath, fileName);
      final licenseFile = File(licenseFilePath);
      if (licenseFile.existsSync()) {
        final licenseContent = licenseFile.readAsStringSync();
        final resolved = await _resolveSpdx(
          packageName: packageName,
          version: packageVersion,
          licenseText: licenseContent,
        );
        print('  → ${resolved.spdx} [${resolved.source}]');
        return OssLicense(
            name: packageName,
            version: packageVersion,
            licenseText: licenseContent,
            licenseSummary: resolved.spdx,
            repositoryUrl: repositoryUrl,
            description: description);
      }
    }
    print('  No license file found for $packageName');
    return null;
  }

  Future<OssLicense?> _findAndSummarizeSdkLicense(String packageName) async {
    final flutterSdkPath = await _getFlutterSdkPath();
    if (flutterSdkPath == null) {
      print('  Flutter SDK path not found.');
      return null;
    }

    final licenseFilePath = p.join(flutterSdkPath, 'LICENSE');
    final licenseFile = File(licenseFilePath);

    String? repositoryUrl;
    String? description;
    String sdkVersion = '0.0.0';

    try {
      final result = await Process.run(
          Platform.isWindows ? 'flutter.bat' : 'flutter',
          ['--version', '--machine']);
      if (result.exitCode == 0) {
        final jsonOutput = jsonDecode(result.stdout.toString());
        sdkVersion = jsonOutput['frameworkVersion'];
      }
    } catch (e) {
      print('Error getting Flutter SDK version: $e');
    }

    if (packageName == 'flutter') {
      repositoryUrl = 'https://github.com/flutter/flutter';
      description = 'Flutter SDK';
    } else if (packageName == 'flutter_test') {
      repositoryUrl =
          'https://github.com/flutter/flutter/tree/master/packages/flutter_test';
      description = 'Flutter Test Framework';
    } else if (packageName == 'sky_engine') {
      repositoryUrl = 'https://github.com/flutter/engine';
      description = 'Flutter Engine Sky Engine';
    }

    if (licenseFile.existsSync()) {
      final licenseContent = licenseFile.readAsStringSync();
      final licenseSummary = matchLicense(licenseContent).spdx;
      print('  → $licenseSummary [heuristic]');
      return OssLicense(
          name: packageName,
          version: sdkVersion,
          licenseText: licenseContent,
          licenseSummary: licenseSummary,
          repositoryUrl: repositoryUrl,
          description: description);
    }
    print('  No license file found for SDK package: $packageName');
    return null;
  }

  String _getPubCacheDir() {
    if (Platform.isWindows) {
      return p.join(Platform.environment['LOCALAPPDATA']!, 'Pub', 'Cache');
    } else {
      return p.join(Platform.environment['HOME']!, '.pub-cache');
    }
  }

  Future<String?> _getFlutterSdkPath() async {
    try {
      final executable = Platform.isWindows ? 'flutter.bat' : 'flutter';
      final result = await Process.run(executable, ['--version', '--machine']);
      if (result.exitCode == 0) {
        final jsonOutput = jsonDecode(result.stdout.toString());
        return jsonOutput['flutterRoot'];
      }
    } catch (e) {
      print('Error getting Flutter SDK path: $e');
    }
    return null;
  }

  /// Prints prominent warnings for packages with potentially problematic licenses.
  ///
  /// This method displays a highly visible warning message when GPL, LGPL, or other
  /// copyleft licenses are detected, as these may have legal implications for
  /// commercial or proprietary software.
  void _printLicenseWarnings(
    List<Map<String, String>> problematicPackages, {
    required bool runtimeOnlyActive,
  }) {
    final separator = '=' * 80;
    final warningLine = '!' * 80;

    print('\n');
    print(separator);
    print(warningLine);
    print(
        '!!!                           LICENSE WARNING                            !!!');
    print(warningLine);
    print(separator);
    print('');
    print(
        '  ATTENTION: The following packages use licenses that may have legal');
    print('  implications for commercial or proprietary software:');
    print('');

    for (final package in problematicPackages) {
      print('  >>> ${package['name']} v${package['version']}');
      print('      License: ${package['license']}');
      print('');
    }

    print('  IMPORTANT LEGAL CONSIDERATIONS:');
    print('');
    print('  - GPL (v2/v3): Requires derived works to be released under GPL.');
    print('    This may require you to open-source your entire application.');
    print('');
    print(
        '  - LGPL (v2.1/v3): Allows linking but may require source disclosure');
    print('    for modifications to the library itself.');
    print('');
    print('  - AGPL: Similar to GPL but with network use triggers.');
    print('');
    print('  RECOMMENDED ACTIONS:');
    print('');
    print('  1. Review the license terms carefully');
    print('  2. Consult with your legal team');
    print(
        '  3. Consider finding alternative packages with more permissive licenses');
    print('  4. Ensure compliance with all license requirements');
    print('');
    if (!runtimeOnlyActive) {
      print(
          '  TIP: If any of the above are dev-only dependencies (build_runner,');
      print(
          '       test tooling, lints, etc.) they will not ship with your app.');
      print(
          '       Re-run with --runtime-only to filter dev packages out before');
      print('       evaluating compliance risk.');
      print('');
    }
    print(separator);
    print(warningLine);
    print(separator);
    print('\n');
  }
}
