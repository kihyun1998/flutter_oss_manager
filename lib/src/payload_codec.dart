import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models/oss_license.dart';

/// Encodes the full license list as a deterministic, single
/// gzip+base64 string. Output is byte-stable across runs.
String encodePayload(List<OssLicense> licenses) {
  final jsonList = licenses
      .map((l) => <String, dynamic>{
            'name': l.name,
            'version': l.version,
            'licenseText': l.licenseText,
            'licenseSummary': l.licenseSummary,
            'repositoryUrl': l.repositoryUrl,
            'description': l.description,
          })
      .toList();
  final jsonStr = jsonEncode(jsonList);
  final utf8Bytes = utf8.encode(jsonStr);
  final gzipped = gzipDeterministic(utf8Bytes);
  return base64.encode(gzipped);
}

/// Decodes a payload string previously produced by [encodePayload].
/// Only usable on platforms with `dart:io` gzip (i.e. the test VM, the
/// generator itself, and app native builds). Web apps rely on the
/// generated sidecar files for decoding.
List<OssLicense> decodePayloadForTesting(String encoded) {
  final bytes = gzip.decode(base64.decode(encoded));
  final list = jsonDecode(utf8.decode(bytes)) as List;
  return list.map((j) {
    final m = j as Map<String, dynamic>;
    return OssLicense(
      name: m['name'] as String,
      version: m['version'] as String,
      licenseText: m['licenseText'] as String,
      licenseSummary: m['licenseSummary'] as String,
      repositoryUrl: m['repositoryUrl'] as String?,
      description: m['description'] as String?,
    );
  }).toList(growable: false);
}

/// Produces a gzip stream with a zeroed mtime and OS=unknown header,
/// so identical inputs always produce identical bytes.
Uint8List gzipDeterministic(List<int> data) {
  final deflated = ZLibCodec(raw: true, level: 9).encode(data);
  final crc = crc32(data);
  final isize = data.length & 0xFFFFFFFF;
  final b = BytesBuilder(copy: false);
  b.add(const [
    0x1F,
    0x8B,
    0x08,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0xFF,
  ]);
  b.add(deflated);
  b.add([
    crc & 0xFF,
    (crc >> 8) & 0xFF,
    (crc >> 16) & 0xFF,
    (crc >> 24) & 0xFF,
    isize & 0xFF,
    (isize >> 8) & 0xFF,
    (isize >> 16) & 0xFF,
    (isize >> 24) & 0xFF,
  ]);
  return b.toBytes();
}

final Uint32List _crc32Table = _buildCrc32Table();

Uint32List _buildCrc32Table() {
  final table = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[i] = c;
  }
  return table;
}

/// IEEE-polynomial CRC32 (same variant used by gzip).
int crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = _crc32Table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Resolves main + 3 sidecar decoder paths from the user's `--output` value.
/// Rules:
/// - Strip trailing `.dart`, then `.g` if present, to form `base`.
/// - Suffix is `.g.dart` if `.g` was stripped, otherwise `.dart`.
/// - Main = `base<suffix>` (ensures `.dart` even if user omitted it).
/// - Sidecars = `base_decoder_{stub,io,web}<suffix>`.
///
/// Examples:
/// - `lib/oss_licenses.dart` → main `lib/oss_licenses.dart`,
///   sidecars `lib/oss_licenses_decoder_*.dart`.
/// - `lib/oss_licenses.g.dart` → main `lib/oss_licenses.g.dart`,
///   sidecars `lib/oss_licenses_decoder_*.g.dart`.
/// - `lib/oss_licenses` (no ext) → main `lib/oss_licenses.dart`,
///   sidecars `lib/oss_licenses_decoder_*.dart`.
SidecarPaths resolveSidecarPaths(String outputPath) {
  var base = outputPath;
  if (base.endsWith('.dart')) {
    base = base.substring(0, base.length - 5);
  }
  var gSuffix = false;
  if (base.endsWith('.g')) {
    base = base.substring(0, base.length - 2);
    gSuffix = true;
  }
  final suffix = gSuffix ? '.g.dart' : '.dart';
  return SidecarPaths(
    main: '$base$suffix',
    stub: '${base}_decoder_stub$suffix',
    io: '${base}_decoder_io$suffix',
    web: '${base}_decoder_web$suffix',
  );
}

class SidecarPaths {
  final String main;
  final String stub;
  final String io;
  final String web;

  const SidecarPaths({
    required this.main,
    required this.stub,
    required this.io,
    required this.web,
  });
}
