import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'models/all_licenses.dart';
import 'models/oss_license.dart';
import 'models/template_license_info.dart';

/// A utility class responsible for generating and scanning open-source licenses.
///
/// This class provides methods to generate license information from a single file
/// or to scan an entire Flutter project's dependencies to collect and summarize
/// their licenses.
class LicenseGenerator {
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

  void _writeDartFile(String outputPath, List<OssLicense> ossLicenses) {
    final output = File(outputPath);
    final buffer = StringBuffer();

    buffer.writeln(
        '// This file is generated by flutter_oss_manager. Do not modify.');
    buffer.writeln('');
    buffer.writeln('class OssLicense {');
    buffer.writeln('  final String name;');
    buffer.writeln('  final String version;');
    buffer.writeln('  final String licenseText;');
    buffer.writeln('  final String licenseSummary;');
    buffer.writeln('  final String? repositoryUrl;');
    buffer.writeln('  final String? description;');
    buffer.writeln('');
    buffer.writeln('  const OssLicense({');
    buffer.writeln('    required this.name,');
    buffer.writeln('    required this.version,');
    buffer.writeln('    required this.licenseText,');
    buffer.writeln('    required this.licenseSummary,');
    buffer.writeln('    this.repositoryUrl,');
    buffer.writeln('    this.description,');
    buffer.writeln('  });');
    buffer.writeln('}');
    buffer.writeln('');
    buffer.writeln('const List<OssLicense> ossLicenses = [');
    for (final license in ossLicenses) {
      buffer.writeln('  OssLicense(');
      buffer.writeln('    name: ${jsonEncode(license.name)},');
      buffer.writeln('    version: ${jsonEncode(license.version)},');
      buffer.writeln('    licenseText: ${jsonEncode(license.licenseText)},');
      buffer.writeln(
          '    licenseSummary: ${jsonEncode(license.licenseSummary)},');
      buffer
          .writeln('    repositoryUrl: ${jsonEncode(license.repositoryUrl)},');
      buffer.writeln('    description: ${jsonEncode(license.description)},');
      buffer.writeln('  ),');
    }
    buffer.writeln('];');

    output.writeAsStringSync(buffer.toString());
    print('Generated Dart file: $outputPath');
  }

  /// Generates a single [OssLicense] object from a specified license file.
  ///
  /// This method is useful for including a project's own license or any other
  /// standalone license file into the generated `oss_licenses.dart`.
  ///
  /// [licenseFilePath] The absolute path to the license file to read.
  /// [outputFilePath] The path where the generated Dart file will be saved.
  ///                 Defaults to `lib/oss_licenses.dart` if not provided.
  void generateLicenses({String? licenseFilePath, String? outputFilePath}) {
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

    _writeDartFile(outputFilePath ?? 'lib/oss_licenses.dart', [license]);
  }

  /// Scans all Flutter project dependencies from `pubspec.lock`,
  /// identifies their licenses, and generates a Dart file containing
  /// the collected license information.
  ///
  /// The generated file will contain a list of [OssLicense] objects.
  ///
  /// [outputFilePath] The path where the generated Dart file will be saved.
  ///                 Defaults to `lib/oss_licenses.dart` if not provided.
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

    final List<OssLicense> collectedLicenses = [];
    final List<Map<String, String>> problematicPackages = [];

    final packages = pubspecLockMap['packages'] as YamlMap?;
    if (packages != null) {
      for (final entry in packages.entries) {
        final packageName = entry.key.toString();
        final packageInfo = entry.value as YamlMap;
        final source = packageInfo['source'].toString();

        OssLicense? license;
        if (source == 'hosted') {
          final packageVersion = packageInfo['version'].toString();
          print('- $packageName ($packageVersion) [hosted]');
          license =
              await _findAndSummarizeHostedLicense(packageName, packageVersion);
        } else if (source == 'sdk') {
          print('- $packageName [sdk]');
          license = await _findAndSummarizeSdkLicense(packageName);
        } else {
          print('- $packageName [unknown source: $source]');
        }

        if (license != null) {
          collectedLicenses.add(license);

          // Check if the license is problematic
          if (_problematicLicenses.contains(license.licenseSummary)) {
            problematicPackages.add({
              'name': license.name,
              'version': license.version,
              'license': license.licenseSummary,
            });
          }
        }
      }
    }

    // Display warnings for problematic licenses
    if (problematicPackages.isNotEmpty) {
      _printLicenseWarnings(problematicPackages);
    }

    if (outputFilePath != null) {
      _writeDartFile(
          p.join(Directory.current.path, outputFilePath), collectedLicenses);
    } else {
      print('No output file path provided. Skipping .dart file generation.');
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
        final licenseSummary = _summarizeLicense(licenseContent);
        return OssLicense(
            name: packageName,
            version: packageVersion,
            licenseText: licenseContent,
            licenseSummary: licenseSummary,
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
