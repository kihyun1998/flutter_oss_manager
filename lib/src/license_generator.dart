import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'license_cache.dart';
import 'models/all_licenses.dart';
import 'models/oss_license.dart';
import 'models/template_license_info.dart';
import 'payload_codec.dart';
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

  final Map<String, TemplateLicenseInfo> _licensesMap = allLicenses;
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

  Set<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  double _calculateJaccardSimilarity(Set<String> set1, Set<String> set2) {
    if (set1.isEmpty && set2.isEmpty) return 1.0;
    if (set1.isEmpty || set2.isEmpty) return 0.0;

    final intersection = set1.intersection(set2).length;
    final union = set1.union(set2).length;

    return intersection / union;
  }

  String _normalizeText(String text) {
    // Remove copyright lines and email addresses
    text = text.replaceAll(
        RegExp(r'copyright \(c\) .+', caseSensitive: false, multiLine: true),
        '');
    text = text.replaceAll(
        RegExp(r'<[^>]+>'), ''); // Remove text in angle brackets like emails
    // Standardize whitespace
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  String _summarizeLicense(String licenseContent) {
    // Step 1: 새로운 휴리스틱 매칭 시도 (우선순위 순)
    final licensesByPriority = getLicensesByPriority();

    List<Map<String, dynamic>> heuristicResults = [];

    for (final licenseInfo in licensesByPriority) {
      final score = licenseInfo.calculateScore(licenseContent);

      if (score['matches'] >= licenseInfo.minMatches) {
        heuristicResults.add({
          'licenseId': licenseInfo.licenseId,
          'confidence': score['confidence'],
          'matches': score['matches'],
          'matchedPatterns': score['matchedPatterns'],
        });

        print(
            '  Matched via new heuristic: ${licenseInfo.licenseId} (${score['confidence'].toStringAsFixed(1)}% confidence, ${score['matches']} matches)');
      }
    }

    // 신뢰도순으로 정렬
    heuristicResults.sort((a, b) => b['confidence'].compareTo(a['confidence']));

    // 가장 높은 신뢰도 결과 반환
    if (heuristicResults.isNotEmpty) {
      final bestResult = heuristicResults.first;
      print(
          '  Best heuristic match: ${bestResult['licenseId']} with ${bestResult['confidence'].toStringAsFixed(1)}% confidence');
      return bestResult['licenseId'];
    }

    // Step 2: 휴리스틱 매칭이 실패한 경우, 기존 유사도 기반 매칭 사용
    print('  No heuristic match found, trying similarity matching...');

    final scannedParagraphs = _normalizeText(licenseContent)
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (scannedParagraphs.isEmpty) {
      return 'Unknown';
    }

    String bestMatch = 'Unknown';
    double highestAverageSimilarity = 0.0;

    for (final licenseEntry in _licensesMap.entries) {
      final templateParagraphs = _normalizeText(licenseEntry.value.licenseText)
          .split(RegExp(r'\n\s*\n'))
          .where((p) => p.isNotEmpty)
          .toList();
      if (templateParagraphs.isEmpty) {
        continue;
      }

      final templateParagraphTokens =
          templateParagraphs.map(_tokenize).toList();
      double totalSimilarity = 0;

      for (final scannedParagraph in scannedParagraphs) {
        final scannedTokens = _tokenize(scannedParagraph);
        double maxSimilarityForParagraph = 0;

        for (final templateTokens in templateParagraphTokens) {
          final similarity =
              _calculateJaccardSimilarity(scannedTokens, templateTokens);
          if (similarity > maxSimilarityForParagraph) {
            maxSimilarityForParagraph = similarity;
          }
        }
        totalSimilarity += maxSimilarityForParagraph;
      }

      final averageSimilarity = totalSimilarity / scannedParagraphs.length;

      if (averageSimilarity > highestAverageSimilarity) {
        highestAverageSimilarity = averageSimilarity;
        bestMatch = licenseEntry.key;
      }
    }

    // Step 3: 최종 결정
    if (highestAverageSimilarity > 0.5) {
      print(
          '  Matched via similarity: $bestMatch (${(highestAverageSimilarity * 100).toStringAsFixed(1)}%)');
      return bestMatch;
    }

    print(
        '  No match found (best similarity: ${(highestAverageSimilarity * 100).toStringAsFixed(1)}%)');
    return 'Unknown';
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

    final heuristic = _summarizeLicense(licenseText);
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
    final paths = resolveSidecarPaths(outputPath);
    final payload = encodePayload(licenses);
    final mainContent = _finalizeHeader(_buildMainFileContent(paths, payload));
    final stubContent = _finalizeHeader(_buildStubContent());
    final ioContent = _finalizeHeader(_buildIoContent());
    final webContent = _finalizeHeader(_buildWebContent());

    _writeFile(paths.main, mainContent);
    _writeFile(paths.stub, stubContent);
    _writeFile(paths.io, ioContent);
    _writeFile(paths.web, webContent);

    print('Generated 4 files:');
    print('  main: ${paths.main}');
    print('  stub: ${paths.stub}');
    print('  io:   ${paths.io}');
    print('  web:  ${paths.web}');
  }

  void _writeFile(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  /// Replaces the `crc32:00000000` placeholder in the header with the actual
  /// CRC32 of the file body (with the placeholder still zeroed). Verification
  /// later: read file, restore placeholder to zeros, compute CRC32, compare.
  String _finalizeHeader(String body) {
    const placeholder = 'crc32:00000000';
    final crc = crc32(utf8.encode(body));
    final hex = crc.toRadixString(16).padLeft(8, '0');
    return body.replaceFirst(placeholder, 'crc32:$hex');
  }

  static const String _generatorVersion = '2.0.0';
  static const String _hashPlaceholderLine = '// content-hash: crc32:00000000';

  String _buildMainFileContent(SidecarPaths paths, String payload) {
    final stubName = p.basename(paths.stub);
    final ioName = p.basename(paths.io);
    final webName = p.basename(paths.web);
    return '''// GENERATED CODE - DO NOT MODIFY BY HAND
// flutter_oss_manager: $_generatorVersion
$_hashPlaceholderLine
// ignore_for_file: type=lint
//
// The entire license list is stored as a gzip+base64-encoded JSON blob
// below. Use `OssLicenses.acquire()` to obtain a reference-counted handle
// to the decoded list, and call `handle.close()` when done. When all
// handles are closed, the cache is released and becomes GC-eligible.
//
// Platform decoders are selected via conditional imports. Do not import
// the sidecar decoder files directly — only this main file.
//
// Dev note: static cache survives hot reload. After regenerating this
// file, use hot restart (not hot reload) to pick up the new payload.

import 'dart:async';
import 'dart:convert';

import '$stubName'
    if (dart.library.io) '$ioName'
    if (dart.library.js_interop) '$webName';

/// Information about a single open-source license used by the project.
class OssLicense {
  final String name;
  final String version;
  final String licenseText;
  final String licenseSummary;
  final String? repositoryUrl;
  final String? description;

  const OssLicense({
    required this.name,
    required this.version,
    required this.licenseText,
    required this.licenseSummary,
    this.repositoryUrl,
    this.description,
  });

  factory OssLicense._fromJson(Map<String, dynamic> j) => OssLicense(
        name: j['name'] as String,
        version: j['version'] as String,
        licenseText: j['licenseText'] as String,
        licenseSummary: j['licenseSummary'] as String,
        repositoryUrl: j['repositoryUrl'] as String?,
        description: j['description'] as String?,
      );
}

/// A reference-counted handle to the decoded license list.
///
/// Obtain via [OssLicenses.acquire]. Call [close] when finished. When the
/// last handle is closed, the cached list is released.
class OssLicensesHandle {
  /// The decoded list. Safe to read while this handle is open.
  final List<OssLicense> licenses;
  bool _closed = false;

  OssLicensesHandle._(this.licenses);

  /// Release this handle's reference. Idempotent.
  void close() {
    if (_closed) return;
    _closed = true;
    OssLicenses._releaseOne();
  }
}

/// Lifecycle controller for the embedded license list.
class OssLicenses {
  static const String _payload = '$payload';
  static Future<List<OssLicense>>? _loading;
  static int _refCount = 0;

  /// Acquire a handle to the license list. First call decodes the blob;
  /// subsequent calls share the same decoded list. Safe to call concurrently.
  ///
  /// Call [OssLicensesHandle.close] when done.
  static Future<OssLicensesHandle> acquire() async {
    _refCount++;
    _loading ??= _decode();
    try {
      final list = await _loading!;
      return OssLicensesHandle._(list);
    } catch (_) {
      _refCount--;
      if (_refCount == 0) _loading = null;
      rethrow;
    }
  }

  /// Test-only: resets the cached state. Do not call in production code.
  static void resetForTest() {
    _loading = null;
    _refCount = 0;
  }

  static void _releaseOne() {
    _refCount--;
    assert(
      _refCount >= 0,
      'OssLicenses: close() called more times than acquire()',
    );
    if (_refCount == 0) {
      _loading = null;
    }
  }

  static Future<List<OssLicense>> _decode() async {
    final bytes = await decodeGzipBase64(_payload);
    final list = jsonDecode(utf8.decode(bytes)) as List;
    return List.unmodifiable(
      list.map((j) => OssLicense._fromJson(j as Map<String, dynamic>)),
    );
  }
}
''';
  }

  String _buildStubContent() => '''// GENERATED CODE - DO NOT MODIFY BY HAND
// flutter_oss_manager: $_generatorVersion
$_hashPlaceholderLine
// ignore_for_file: type=lint

import 'dart:async';
import 'dart:typed_data';

Future<Uint8List> decodeGzipBase64(String encoded) =>
    throw UnsupportedError(
      'flutter_oss_manager: no decoder available for this platform. '
      'Expected either dart:io or dart:js_interop to be available.',
    );
''';

  String _buildIoContent() => '''// GENERATED CODE - DO NOT MODIFY BY HAND
// flutter_oss_manager: $_generatorVersion
$_hashPlaceholderLine
// ignore_for_file: type=lint

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> decodeGzipBase64(String encoded) async {
  final gzipped = base64.decode(encoded);
  final raw = gzip.decode(gzipped);
  return raw is Uint8List ? raw : Uint8List.fromList(raw);
}
''';

  String _buildWebContent() => '''// GENERATED CODE - DO NOT MODIFY BY HAND
// flutter_oss_manager: $_generatorVersion
$_hashPlaceholderLine
// ignore_for_file: type=lint

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('Response')
extension type _Response._(JSObject _) implements JSObject {
  external factory _Response(JSAny? body);
  external _ReadableStream? get body;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

@JS('ReadableStream')
extension type _ReadableStream._(JSObject _) implements JSObject {
  external _ReadableStream pipeThrough(_DecompressionStream transform);
}

@JS('DecompressionStream')
extension type _DecompressionStream._(JSObject _) implements JSObject {
  external factory _DecompressionStream(String format);
}

Future<Uint8List> decodeGzipBase64(String encoded) async {
  final Uint8List bytes = base64.decode(encoded);
  final source = _Response(bytes.toJS);
  final readable = source.body!;
  final decompressed = readable.pipeThrough(_DecompressionStream('gzip'));
  final buffer = await _Response(decompressed).arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}
''';

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
    final licenseSummary = _summarizeLicense(licenseContent);

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
  Future<void> scanPackages({String? outputFilePath}) async {
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
    final entries = packages?.entries.toList() ?? const [];
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
      _printLicenseWarnings(problematicPackages);
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
      return _findAndSummarizeHostedLicense(packageName, packageVersion);
    } else if (source == 'sdk') {
      print('- $packageName [sdk]');
      return _findAndSummarizeSdkLicense(packageName);
    } else {
      print('- $packageName [unknown source: $source]');
      return null;
    }
  }

  Future<OssLicense?> _findAndSummarizeHostedLicense(
      String packageName, String packageVersion) async {
    final pubCacheDir = _getPubCacheDir();
    final packagePath = p.join(
        pubCacheDir, 'hosted', 'pub.dev', '$packageName-$packageVersion');

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
      final licenseSummary = _summarizeLicense(licenseContent);
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
  void _printLicenseWarnings(List<Map<String, String>> problematicPackages) {
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
    print(separator);
    print(warningLine);
    print(separator);
    print('\n');
  }
}
