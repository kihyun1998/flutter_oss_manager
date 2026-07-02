import 'dart:io';

import 'package:flutter_oss_manager/src/license_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Content-level assertions (headers, content-hash, payload round-trip,
// byte-stability) live in `generated_files_test.dart`, driven purely through
// `renderGeneratedFiles` with no temp directory. These two tests only verify
// that the thin write loop in LicenseGenerator actually lands files on disk.
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

  test('generateLicenses writes 4 .g.dart files to disk', () {
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

  test('silently overwrites a hand-edited sidecar on regeneration', () {
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
}
