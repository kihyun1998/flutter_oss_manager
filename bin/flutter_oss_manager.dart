import 'package:args/args.dart';
import 'package:flutter/material.dart';
import 'package:flutter_oss_manager/src/license_generator.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser();
  parser.addFlag('verbose', abbr: 'v', help: 'Show verbose output.');

  final commandParser = ArgParser();
  commandParser.addOption('output',
      abbr: 'o',
      help: 'Output .dart file path.',
      defaultsTo: 'lib/oss_licenses.dart');

  parser.addCommand(
      'generate',
      commandParser
        ..addOption('license-file',
            abbr: 'l', help: 'Path to the license file.', mandatory: true));
  parser.addCommand('scan', commandParser);

  final results = parser.parse(args);

  if (results['verbose']) {
    debugPrint('Verbose output enabled.');
  }

  final generator = LicenseGenerator();

  if (results.command != null) {
    final command = results.command!;
    if (command.name == 'generate') {
      final licenseFilePath = command['license-file'];
      final outputFilePath = command['output'];
      generator.generateLicenses(
        licenseFilePath: licenseFilePath,
        outputFilePath: outputFilePath,
      );
    } else if (command.name == 'scan') {
      final outputFilePath = command['output'];
      await generator.scanPackages(outputFilePath: outputFilePath);
    }
  } else {
    debugPrint('Please provide a command: generate or scan.');
    debugPrint(parser.usage);
  }
}
