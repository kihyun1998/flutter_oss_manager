import 'dart:convert';

import 'package:flutter_oss_manager/src/generated_files.dart';
import 'package:flutter_oss_manager/src/models/oss_license.dart';
import 'package:flutter_oss_manager/src/payload_codec.dart';
import 'package:flutter_oss_manager/src/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sample = OssLicense(
    name: 'example',
    version: '1.0.0',
    licenseText: 'MIT License\n\nPermission is hereby granted...',
    licenseSummary: 'MIT',
  );

  test('renders main + 3 sidecar files at the resolved paths', () {
    final files = renderGeneratedFiles([sample], 'lib/oss_licenses.g.dart');
    expect(files.main.path, 'lib/oss_licenses.g.dart');
    expect(files.stub.path, 'lib/oss_licenses_decoder_stub.g.dart');
    expect(files.io.path, 'lib/oss_licenses_decoder_io.g.dart');
    expect(files.web.path, 'lib/oss_licenses_decoder_web.g.dart');
    expect(files.all, hasLength(4));
  });

  test('main file declares the OssLicenses lifecycle API', () {
    final main = renderGeneratedFiles([sample], 'lib/oss_licenses.g.dart')
        .main
        .content;
    expect(main, contains('class OssLicense'));
    expect(main, contains('class OssLicensesHandle'));
    expect(main, contains('class OssLicenses'));
    expect(main, contains('Future<OssLicensesHandle> acquire()'));
    expect(main, contains('void close()'));
    expect(main, contains('if (dart.library.io)'));
    expect(main, contains('if (dart.library.js_interop)'));
  });

  test('every file header stamps the current package version', () {
    final files = renderGeneratedFiles([sample], 'lib/oss_licenses.g.dart');
    for (final f in files.all) {
      expect(f.content, contains('// flutter_oss_manager: $packageVersion'),
          reason: f.path);
    }
  });

  test('main file exposes the scoped use() helper', () {
    final main =
        renderGeneratedFiles([sample], 'lib/oss_licenses.g.dart').main.content;
    expect(main, contains('static Future<T> use<T>('));
    expect(main, contains('FutureOr<T> Function(List<OssLicense>'));
    // acquire()/close() stay for the long-lived pattern.
    expect(main, contains('Future<OssLicensesHandle> acquire()'));
  });

  test('every file carries the standard generated header', () {
    final files = renderGeneratedFiles([sample], 'lib/oss_licenses.g.dart');
    for (final f in files.all) {
      expect(f.content, startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND'),
          reason: f.path);
      expect(f.content, contains('// flutter_oss_manager: '), reason: f.path);
      expect(f.content, contains('// ignore_for_file: type=lint'),
          reason: f.path);
      expect(f.content, matches(RegExp(r'// content-hash: crc32:[0-9a-f]{8}')),
          reason: f.path);
    }
  });

  test('each file embeds a content-hash matching its recomputed crc32', () {
    final files = renderGeneratedFiles([sample], 'lib/oss_licenses.g.dart');
    for (final f in files.all) {
      final embedded = RegExp(r'// content-hash: crc32:([0-9a-f]{8})')
          .firstMatch(f.content)!
          .group(1);
      final zeroed = f.content.replaceFirst(
        RegExp(r'// content-hash: crc32:[0-9a-f]{8}'),
        '// content-hash: crc32:00000000',
      );
      final expected =
          crc32(utf8.encode(zeroed)).toRadixString(16).padLeft(8, '0');
      expect(embedded, expected, reason: f.path);
    }
  });

  test('main file embeds a payload that decodes back to the original license',
      () {
    final files = renderGeneratedFiles([
      const OssLicense(
        name: 'utf8-pkg',
        version: '9.9.9',
        licenseText: 'Custom Body\n\n한글 포함',
        licenseSummary: 'Custom',
        repositoryUrl: 'https://example.com/repo',
      ),
    ], 'lib/oss_licenses.g.dart');
    final payload = RegExp(r"_payload = '([^']+)';")
        .firstMatch(files.main.content)!
        .group(1)!;
    final decoded = decodePayloadForTesting(payload);
    expect(decoded, hasLength(1));
    expect(decoded[0].name, 'utf8-pkg');
    expect(decoded[0].version, '9.9.9');
    expect(decoded[0].licenseText, 'Custom Body\n\n한글 포함');
    expect(decoded[0].repositoryUrl, 'https://example.com/repo');
  });

  test('rendering the same input twice is byte-identical', () {
    final a = renderGeneratedFiles([sample], 'lib/oss_licenses.g.dart');
    final b = renderGeneratedFiles([sample], 'lib/oss_licenses.g.dart');
    for (var i = 0; i < a.all.length; i++) {
      expect(b.all[i].content, a.all[i].content, reason: a.all[i].path);
    }
  });

  test('different license text yields a different main content-hash', () {
    String mainHash(String text) {
      final files = renderGeneratedFiles([
        OssLicense(
          name: 'x',
          version: '1',
          licenseText: text,
          licenseSummary: '?',
        ),
      ], 'lib/oss_licenses.g.dart');
      return RegExp(r'// content-hash: crc32:([0-9a-f]{8})')
          .firstMatch(files.main.content)!
          .group(1)!;
    }

    expect(mainHash('first license'),
        isNot(mainHash('second different license')));
  });
}
