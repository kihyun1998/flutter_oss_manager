import 'dart:io';

import 'package:flutter_oss_manager/src/version.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('packageVersion is kept in sync with pubspec.yaml', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(packageVersion, pubspec['version'].toString(),
        reason: 'bump packageVersion in lib/src/version.dart when pubspec '
            'version changes (the generated header stamps it)');
  });
}
