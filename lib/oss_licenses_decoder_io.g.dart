// GENERATED CODE - DO NOT MODIFY BY HAND
// flutter_oss_manager: 2.0.0
// content-hash: crc32:0f8378ff
// ignore_for_file: type=lint

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> decodeGzipBase64(String encoded) async {
  final gzipped = base64.decode(encoded);
  final raw = gzip.decode(gzipped);
  return raw is Uint8List ? raw : Uint8List.fromList(raw);
}
