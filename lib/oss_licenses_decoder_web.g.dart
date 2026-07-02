// GENERATED CODE - DO NOT MODIFY BY HAND
// flutter_oss_manager: 2.3.0
// content-hash: crc32:eed77513
// ignore_for_file: type=lint

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('Response')
extension type _Response._(JSObject _) implements JSObject {
  external factory _Response(JSAny? body);
  external _ReadableStream? get body;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

@JS('ReadableStream')
extension type _ReadableStream._(JSObject _) implements JSObject {
  external _ReadableStream pipeThrough(_DecompressionStream transform);
}

@JS('DecompressionStream')
extension type _DecompressionStream._(JSObject _) implements JSObject {
  external factory _DecompressionStream(String format);
}

Future<Uint8List> decodeGzipBase64(String encoded) async {
  final Uint8List bytes = base64.decode(encoded);
  final source = _Response(bytes.toJS);
  final readable = source.body!;
  final decompressed = readable.pipeThrough(_DecompressionStream('gzip'));
  final buffer = await _Response(decompressed).arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}
