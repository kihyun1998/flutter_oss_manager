import 'dart:convert';
import 'dart:io';

import 'package:flutter_oss_manager/src/license_generator.dart';
import 'package:flutter_oss_manager/src/payload_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('flutter_oss_manager_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String mainPath() => p.join(tmp.path, 'lib', 'oss_licenses.g.dart');
  String sidecarPath(String variant) =>
      p.join(tmp.path, 'lib', 'oss_licenses_decoder_$variant.g.dart');

  void writeLicense(String text) {
    final f = File(p.join(tmp.path, 'LICENSE'));
    f.writeAsStringSync(text);
  }

  /// Extracts the 8-hex content-hash from a generated file's header.
  String extractHash(String content) {
    final m = RegExp(r'// content-hash: crc32:([0-9a-f]{8})')
        .firstMatch(content);
    if (m == null) throw StateError('no content-hash header in file');
    return m.group(1)!;
  }

  /// Recomputes the expected hash by resetting the hash field to zeros
  /// and CRC32-ing the whole body. Should match the embedded hash.
  String recomputeHash(String content) {
    final zeroed = content.replaceFirst(
      RegExp(r'// content-hash: crc32:[0-9a-f]{8}'),
      '// content-hash: crc32:00000000',
    );
    return crc32(utf8.encode(zeroed)).toRadixString(16).padLeft(8, '0');
  }

  test('generateLicenses writes 4 .g.dart files', () {
    writeLicense('MIT License\n\nPermission is hereby granted...');
    LicenseGenerator().generateLicenses(
      licenseFilePath: p.join(tmp.path, 'LICENSE'),
      outputFilePath: mainPath(),
    );
    expect(File(mainPath()).existsSync(), isTrue);
    expect(File(sidecarPath('stub')).existsSync(), isTrue);
    expect(File(sidecarPath('io')).existsSync(), isTrue);
    expect(File(sidecarPath('web')).existsSync(), isTrue);
  });

  test('main file contains OssLicenses and OssLicensesHandle classes', () {
    writeLicense('MIT License');
    LicenseGenerator().generateLicenses(
      licenseFilePath: p.join(tmp.path, 'LICENSE'),
      outputFilePath: mainPath(),
    );
    final content = File(mainPath()).readAsStringSync();
    expect(content, contains('class OssLicense'));
    expect(content, contains('class OssLicensesHandle'));
    expect(content, contains('class OssLicenses'));
    expect(content, contains('Future<OssLicensesHandle> acquire()'));
    expect(content, contains('void close()'));
    expect(content, contains('static void resetForTest()'));
    expect(content, contains('if (dart.library.io)'));
    expect(content, contains('if (dart.library.js_interop)'));
  });

  test('all 4 files have DO NOT MODIFY + version + hash + ignore headers', () {
    writeLicense('text');
    LicenseGenerator().generateLicenses(
      licenseFilePath: p.join(tmp.path, 'LICENSE'),
      outputFilePath: mainPath(),
    );
    for (final path in [
      mainPath(),
      sidecarPath('stub'),
      sidecarPath('io'),
      sidecarPath('web'),
    ]) {
      final content = File(path).readAsStringSync();
      expect(content, startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND'),
          reason: '$path missing DO NOT MODIFY header');
      expect(content, contains('// flutter_oss_manager: '),
          reason: '$path missing version line');
      expect(content, contains('// ignore_for_file: type=lint'),
          reason: '$path missing ignore_for_file directive');
      expect(content, matches(RegExp(r'// content-hash: crc32:[0-9a-f]{8}')),
          reason: '$path missing content-hash');
    }
  });

  test('embedded content-hash matches recomputed CRC32 for every file', () {
    writeLicense('some license body');
    LicenseGenerator().generateLicenses(
      licenseFilePath: p.join(tmp.path, 'LICENSE'),
      outputFilePath: mainPath(),
    );
    for (final path in [
      mainPath(),
      sidecarPath('stub'),
      sidecarPath('io'),
      sidecarPath('web'),
    ]) {
      final content = File(path).readAsStringSync();
      expect(extractHash(content), equals(recomputeHash(content)),
          reason: '$path hash mismatch');
    }
  });

  test('generated payload round-trips to original license', () {
    writeLicense('Custom License Body\n\n한글 포함');
    LicenseGenerator().generateLicenses(
      licenseFilePath: p.join(tmp.path, 'LICENSE'),
      outputFilePath: mainPath(),
    );
    final content = File(mainPath()).readAsStringSync();
    final match = RegExp(r"_payload = '([^']+)';").firstMatch(content);
    expect(match, isNotNull,
        reason: 'main file should contain a _payload const string');
    final decoded = decodePayloadForTesting(match!.group(1)!);
    expect(decoded, hasLength(1));
    expect(decoded[0].licenseText, 'Custom License Body\n\n한글 포함');
    expect(decoded[0].name, 'LICENSE');
  });

  test('regeneration with same input produces identical bytes', () {
    writeLicense('MIT License body');
    LicenseGenerator().generateLicenses(
      licenseFilePath: p.join(tmp.path, 'LICENSE'),
      outputFilePath: mainPath(),
    );
    final first = {
      'main': File(mainPath()).readAsBytesSync(),
      'stub': File(sidecarPath('stub')).readAsBytesSync(),
      'io': File(sidecarPath('io')).readAsBytesSync(),
      'web': File(sidecarPath('web')).readAsBytesSync(),
    };
    LicenseGenerator().generateLicenses(
      licenseFilePath: p.join(tmp.path, 'LICENSE'),
      outputFilePath: mainPath(),
    );
    expect(File(mainPath()).readAsBytesSync(), equals(first['main']));
    expect(File(sidecarPath('stub')).readAsBytesSync(), equals(first['stub']));
    expect(File(sidecarPath('io')).readAsBytesSync(), equals(first['io']));
    expect(File(sidecarPath('web')).readAsBytesSync(), equals(first['web']));
  });

  test('different license text yields different main-file content-hash', () {
    writeLicense('first license');
    LicenseGenerator().generateLicenses(
      licenseFilePath: p.join(tmp.path, 'LICENSE'),
      outputFilePath: mainPath(),
    );
    final hash1 = extractHash(File(mainPath()).readAsStringSync());

    writeLicense('second different license');
    LicenseGenerator().generateLicenses(
      licenseFilePath: p.join(tmp.path, 'LICENSE'),
      outputFilePath: mainPath(),
    );
    final hash2 = extractHash(File(mainPath()).readAsStringSync());

    expect(hash1, isNot(equals(hash2)));
  });

  test('silently overwrites hand-edited sidecar on regeneration', () {
    writeLicense('text');
    final gen = LicenseGenerator();
    gen.generateLicenses(
      licenseFilePath: p.join(tmp.path, 'LICENSE'),
      outputFilePath: mainPath(),
    );
    File(sidecarPath('stub')).writeAsStringSync('// hand-edited, will be lost');

    gen.generateLicenses(
      licenseFilePath: p.join(tmp.path, 'LICENSE'),
      outputFilePath: mainPath(),
    );
    final stub = File(sidecarPath('stub')).readAsStringSync();
    expect(stub, contains('UnsupportedError'));
    expect(stub, isNot(contains('hand-edited')));
  });

  test('re-running on unchanged input is safe (no error)', () {
    writeLicense('text');
    final gen = LicenseGenerator();
    gen.generateLicenses(
      licenseFilePath: p.join(tmp.path, 'LICENSE'),
      outputFilePath: mainPath(),
    );
    expect(
      () => gen.generateLicenses(
        licenseFilePath: p.join(tmp.path, 'LICENSE'),
        outputFilePath: mainPath(),
      ),
      returnsNormally,
    );
  });
}
