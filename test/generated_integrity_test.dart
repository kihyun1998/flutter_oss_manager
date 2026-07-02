import 'dart:convert';
import 'dart:io';

import 'package:flutter_oss_manager/src/payload_codec.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the committed generated files against being edited after generation
/// — most likely by a `dart format` pass, which rewrites the body and leaves
/// the embedded crc32 content-hash stale. The generator's output is not
/// `dart format`-clean (see docs/adr/0001), so this catches such corruption at
/// CI instead of shipping broken hashes. Regenerate (do not format) to fix.
void main() {
  final generated = [
    for (final dir in ['lib', 'example/lib'])
      if (Directory(dir).existsSync())
        ...Directory(dir)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.g.dart')),
  ];

  test('committed generated files were found', () {
    expect(generated, isNotEmpty,
        reason: 'expected lib/ and example/lib/ to contain .g.dart files');
  });

  for (final file in generated) {
    test('embedded content-hash matches the body: ${file.path}', () {
      // Normalize CRLF → LF so the check is stable regardless of the working
      // tree's line-ending setting; the generator hashes LF bodies.
      final body = file.readAsStringSync().replaceAll('\r\n', '\n');
      final match =
          RegExp(r'// content-hash: crc32:([0-9a-f]{8})').firstMatch(body);
      expect(match, isNotNull,
          reason: '${file.path}: no content-hash header found');
      final embedded = match!.group(1)!;
      final zeroed = body.replaceFirst('crc32:$embedded', 'crc32:00000000');
      final recomputed =
          crc32(utf8.encode(zeroed)).toRadixString(16).padLeft(8, '0');
      expect(recomputed, embedded,
          reason: '${file.path} was modified after generation (stale hash). '
              'Do not run `dart format` on generated files — regenerate them.');
    });
  }
}
