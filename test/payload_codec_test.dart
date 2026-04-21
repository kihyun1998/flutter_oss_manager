import 'dart:convert';
import 'dart:io';

import 'package:flutter_oss_manager/src/models/oss_license.dart';
import 'package:flutter_oss_manager/src/payload_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('crc32', () {
    // Reference values from https://rosettacode.org/wiki/CRC-32
    test('empty input', () {
      expect(crc32(const []), 0x00000000);
    });

    test('single byte "a"', () {
      expect(crc32(utf8.encode('a')), 0xE8B7BE43);
    });

    test('classic "The quick brown fox..." vector', () {
      final bytes = utf8.encode('The quick brown fox jumps over the lazy dog');
      expect(crc32(bytes), 0x414FA339);
    });

    test('"123456789" standard vector', () {
      expect(crc32(utf8.encode('123456789')), 0xCBF43926);
    });
  });

  group('gzipDeterministic', () {
    test('output is byte-stable across repeated encodes', () {
      final input = utf8.encode('The quick brown fox' * 50);
      final first = gzipDeterministic(input);
      for (var i = 0; i < 9; i++) {
        expect(gzipDeterministic(input), equals(first),
            reason: 'gzip output diverged on iteration $i');
      }
    });

    test('round-trips through dart:io gzip.decode', () {
      final input = utf8.encode('hello world, hello world, hello world');
      final gz = gzipDeterministic(input);
      expect(gzip.decode(gz), equals(input));
    });

    test('header has zeroed mtime and OS=0xFF', () {
      final gz = gzipDeterministic(utf8.encode('x'));
      // Bytes 4..7 = mtime (little endian); byte 9 = OS.
      expect(gz[4], 0x00);
      expect(gz[5], 0x00);
      expect(gz[6], 0x00);
      expect(gz[7], 0x00);
      expect(gz[9], 0xFF);
    });
  });

  group('encodePayload / decodePayloadForTesting', () {
    test('roundtrips empty list', () {
      final encoded = encodePayload(const []);
      expect(decodePayloadForTesting(encoded), isEmpty);
    });

    test('roundtrips a single license', () {
      final licenses = [
        const OssLicense(
          name: 'example',
          version: '1.0.0',
          licenseText: 'MIT License\n\nPermission is hereby granted...',
          licenseSummary: 'MIT',
          repositoryUrl: 'https://example.com',
          description: 'An example package',
        ),
      ];
      final encoded = encodePayload(licenses);
      final decoded = decodePayloadForTesting(encoded);
      expect(decoded, hasLength(1));
      expect(decoded[0].name, 'example');
      expect(decoded[0].version, '1.0.0');
      expect(decoded[0].licenseText, licenses[0].licenseText);
      expect(decoded[0].licenseSummary, 'MIT');
      expect(decoded[0].repositoryUrl, 'https://example.com');
      expect(decoded[0].description, 'An example package');
    });

    test('preserves null repositoryUrl / description', () {
      final licenses = [
        const OssLicense(
          name: 'foo',
          version: '2.3.4',
          licenseText: 'BSD',
          licenseSummary: 'BSD-3-Clause',
        ),
      ];
      final decoded = decodePayloadForTesting(encodePayload(licenses));
      expect(decoded[0].repositoryUrl, isNull);
      expect(decoded[0].description, isNull);
    });

    test('encode output is byte-stable across repeated calls', () {
      final licenses = [
        const OssLicense(
          name: 'a',
          version: '1',
          licenseText: 'Text A',
          licenseSummary: 'MIT',
        ),
        const OssLicense(
          name: 'b',
          version: '2',
          licenseText: 'Text B',
          licenseSummary: 'Apache-2.0',
        ),
      ];
      final first = encodePayload(licenses);
      for (var i = 0; i < 9; i++) {
        expect(encodePayload(licenses), equals(first),
            reason: 'encode diverged on iteration $i');
      }
    });

    test('handles unicode license text', () {
      final licenses = [
        const OssLicense(
          name: 'utf8-pkg',
          version: '1.0',
          licenseText: '저작권 © 2026 — 가나다라마바사',
          licenseSummary: 'Custom',
        ),
      ];
      final decoded = decodePayloadForTesting(encodePayload(licenses));
      expect(decoded[0].licenseText, '저작권 © 2026 — 가나다라마바사');
    });
  });

  group('resolveSidecarPaths', () {
    test('standard .dart extension', () {
      final paths = resolveSidecarPaths('lib/oss_licenses.dart');
      expect(paths.main, 'lib/oss_licenses.dart');
      expect(paths.stub, 'lib/oss_licenses_decoder_stub.dart');
      expect(paths.io, 'lib/oss_licenses_decoder_io.dart');
      expect(paths.web, 'lib/oss_licenses_decoder_web.dart');
    });

    test('nested path', () {
      final paths = resolveSidecarPaths('lib/src/licenses.dart');
      expect(paths.main, 'lib/src/licenses.dart');
      expect(paths.stub, 'lib/src/licenses_decoder_stub.dart');
    });

    test('.g.dart input preserves .g.dart on sidecars', () {
      final paths = resolveSidecarPaths('lib/gen/licenses.g.dart');
      expect(paths.main, 'lib/gen/licenses.g.dart');
      expect(paths.stub, 'lib/gen/licenses_decoder_stub.g.dart');
      expect(paths.io, 'lib/gen/licenses_decoder_io.g.dart');
      expect(paths.web, 'lib/gen/licenses_decoder_web.g.dart');
    });

    test('.dart input keeps plain .dart on sidecars', () {
      final paths = resolveSidecarPaths('lib/licenses.dart');
      expect(paths.stub, 'lib/licenses_decoder_stub.dart');
      expect(paths.io, 'lib/licenses_decoder_io.dart');
      expect(paths.web, 'lib/licenses_decoder_web.dart');
    });

    test('appends .dart when extension is missing', () {
      final paths = resolveSidecarPaths('lib/oss_licenses');
      expect(paths.main, 'lib/oss_licenses.dart');
      expect(paths.web, 'lib/oss_licenses_decoder_web.dart');
    });

    test('absolute path', () {
      final paths = resolveSidecarPaths('/abs/path/file.dart');
      expect(paths.main, '/abs/path/file.dart');
      expect(paths.stub, '/abs/path/file_decoder_stub.dart');
    });
  });
}
