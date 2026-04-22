import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_oss_manager/src/license_cache.dart';
import 'package:flutter_oss_manager/src/license_generator.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser();
  parser.addFlag('verbose', abbr: 'v', help: 'Show verbose output.');

  ArgParser buildCommandParser() => ArgParser()
    ..addOption('output',
        abbr: 'o',
        help: 'Output .dart file path (main file; 3 sidecars are derived).',
        defaultsTo: 'lib/oss_licenses.g.dart');

  parser.addCommand(
      'generate',
      buildCommandParser()
        ..addOption('license-file',
            abbr: 'l', help: 'Path to the license file.', mandatory: true));

  final scanParser = buildCommandParser()
    ..addFlag('offline',
        help: 'Skip pub.dev API; use cache + heuristic only.',
        defaultsTo: false,
        negatable: false)
    ..addFlag('refresh-cache',
        help:
            'Ignore and clear the cache before scanning; re-fetch everything.',
        defaultsTo: false,
        negatable: false)
    ..addFlag('no-cache',
        help: 'Do not read or write the SPDX cache file.',
        defaultsTo: false,
        negatable: false);
  parser.addCommand('scan', scanParser);

  final results = parser.parse(args);

  if (results['verbose']) {
    print('Verbose output enabled.');
  }

  if (results.command != null) {
    final command = results.command!;
    if (command.name == 'generate') {
      final licenseFilePath = command['license-file'];
      final outputFilePath = command['output'];
      final generator = LicenseGenerator();
      generator.generateLicenses(
        licenseFilePath: licenseFilePath,
        outputFilePath: outputFilePath,
      );
    } else if (command.name == 'scan') {
      final outputFilePath = command['output'];
      final offline = command['offline'] as bool;
      final refresh = command['refresh-cache'] as bool;
      final noCache = command['no-cache'] as bool;

      LicenseCache? cache;
      if (!noCache) {
        cache = LicenseCache(projectRoot: Directory.current.path);
        await cache.load();
        if (refresh) cache.clear();
      }

      final generator = LicenseGenerator(cache: cache, offline: offline);
      await generator.scanPackages(outputFilePath: outputFilePath);
    }
  } else {
    print('Please provide a command: generate or scan.');
    print(parser.usage);
  }
}
