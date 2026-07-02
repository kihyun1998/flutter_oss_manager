import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_oss_manager/src/pub_license_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractSpdxFromTags', () {
    test('MIT from license:mit', () {
      expect(
        extractSpdxFromTags([
          'license:mit',
          'license:fsf-libre',
          'license:osi-approved',
          'sdk:flutter',
        ]),
        'MIT',
      );
    });

    test('BSD-3-Clause canonical casing', () {
      expect(
        extractSpdxFromTags(['license:bsd-3-clause', 'license:osi-approved']),
        'BSD-3-Clause',
      );
    });

    test('Apache-2.0 canonical casing', () {
      expect(extractSpdxFromTags(['license:apache-2.0']), 'Apache-2.0');
    });

    test('classifier-only tags return null', () {
      expect(
        extractSpdxFromTags(['license:fsf-libre', 'license:osi-approved']),
        isNull,
      );
    });

    test('no license tag at all returns null', () {
      expect(
        extractSpdxFromTags(['sdk:flutter', 'platform:android']),
        isNull,
      );
    });

    test('empty tags returns null', () {
      expect(extractSpdxFromTags([]), isNull);
    });

    test('unknown SPDX id falls through as lowercase', () {
      expect(
        extractSpdxFromTags(['license:some-obscure-license-id']),
        'some-obscure-license-id',
      );
    });

    test('non-string entries are skipped', () {
      expect(
        extractSpdxFromTags([null, 42, 'license:mit']),
        'MIT',
      );
    });

    test('GPL-3.0 matches _problematicLicenses casing', () {
      expect(extractSpdxFromTags(['license:gpl-3.0']), 'GPL-3.0');
    });
  });

  group('HttpPubLicenseClient against local server', () {
    late HttpServer server;
    late Uri base;
    final requests = <String>[];
    Map<String, int> statusMap = {};
    Map<String, String> bodyMap = {};

    setUp(() async {
      requests.clear();
      statusMap = {};
      bodyMap = {};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
      server.listen((req) async {
        requests.add(req.uri.path);
        final status = statusMap[req.uri.path] ?? 200;
        final body = bodyMap[req.uri.path] ?? '{}';
        req.response.statusCode = status;
        req.response.headers.contentType = ContentType.json;
        req.response.write(body);
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('200 with valid tags returns SPDX', () async {
      bodyMap['/api/packages/args/score'] = jsonEncode({
        'tags': ['license:bsd-3-clause', 'license:osi-approved'],
      });
      final client = HttpPubLicenseClient(baseUri: base);
      expect(await client.fetchSpdxId('args', '2.4.2'), 'BSD-3-Clause');
      expect(requests, contains('/api/packages/args/score'));
    });

    test('404 returns null', () async {
      statusMap['/api/packages/missing/score'] = 404;
      final client = HttpPubLicenseClient(baseUri: base);
      expect(await client.fetchSpdxId('missing', '1.0.0'), isNull);
    });

    test('malformed JSON returns null', () async {
      bodyMap['/api/packages/bad/score'] = '{{{';
      final client = HttpPubLicenseClient(baseUri: base);
      expect(await client.fetchSpdxId('bad', '1.0.0'), isNull);
    });

    test('missing tags field returns null', () async {
      bodyMap['/api/packages/notags/score'] = jsonEncode({'other': 1});
      final client = HttpPubLicenseClient(baseUri: base);
      expect(await client.fetchSpdxId('notags', '1.0.0'), isNull);
    });

    test('tags without license entry returns null', () async {
      bodyMap['/api/packages/unlicensed/score'] = jsonEncode({
        'tags': ['sdk:dart']
      });
      final client = HttpPubLicenseClient(baseUri: base);
      expect(await client.fetchSpdxId('unlicensed', '1.0.0'), isNull);
    });

    test('serves multiple calls and survives close() (lazy recreate)',
        () async {
      bodyMap['/api/packages/a/score'] = jsonEncode({
        'tags': ['license:mit']
      });
      bodyMap['/api/packages/b/score'] = jsonEncode({
        'tags': ['license:apache-2.0']
      });
      final client = HttpPubLicenseClient(baseUri: base);
      expect(await client.fetchSpdxId('a', '1.0.0'), 'MIT');
      expect(await client.fetchSpdxId('b', '1.0.0'), 'Apache-2.0');
      client.close();
      client.close(); // idempotent
      // A fetch after close lazily recreates the underlying client.
      expect(await client.fetchSpdxId('a', '1.0.0'), 'MIT');
    });

    test('User-Agent header is sent', () async {
      bodyMap['/api/packages/ua/score'] = jsonEncode({
        'tags': ['license:mit']
      });
      final received = Completer<String?>();
      await server.close(force: true);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
      server.listen((req) async {
        if (!received.isCompleted) {
          received.complete(req.headers.value('user-agent'));
        }
        req.response.statusCode = 200;
        req.response.write(jsonEncode({
          'tags': ['license:mit']
        }));
        await req.response.close();
      });

      final client = HttpPubLicenseClient(
        baseUri: base,
        userAgent: 'test-agent/1.0',
      );
      await client.fetchSpdxId('ua', '1.0.0');
      expect(await received.future, 'test-agent/1.0');
    });
  });
}
