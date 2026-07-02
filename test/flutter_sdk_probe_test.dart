import 'dart:io';

import 'package:flutter_oss_manager/src/flutter_sdk_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses root and version from `flutter --version --machine` JSON',
      () async {
    final probe = ProcessFlutterSdkProbe(
      runProcess: (exe, args) async => ProcessResult(
        0,
        0,
        '{"frameworkVersion":"3.4.0","flutterRoot":"/opt/flutter"}',
        '',
      ),
    );
    final info = await probe.probe();
    expect(info, isNotNull);
    expect(info!.root, '/opt/flutter');
    expect(info.version, '3.4.0');
  });

  test('non-zero exit code → null', () async {
    final probe = ProcessFlutterSdkProbe(
      runProcess: (exe, args) async => ProcessResult(0, 1, '', 'not found'),
    );
    expect(await probe.probe(), isNull);
  });

  test('a thrown process error → null (Flutter absent)', () async {
    final probe = ProcessFlutterSdkProbe(
      runProcess: (exe, args) async =>
          throw const ProcessException('flutter', []),
    );
    expect(await probe.probe(), isNull);
  });

  test('memoizes a successful result: the process runs at most once', () async {
    var calls = 0;
    final probe = ProcessFlutterSdkProbe(
      runProcess: (exe, args) async {
        calls++;
        return ProcessResult(
            0, 0, '{"frameworkVersion":"3.4.0","flutterRoot":"/x"}', '');
      },
    );
    await probe.probe();
    await probe.probe();
    await probe.probe();
    expect(calls, 1);
  });

  test('memoizes a null result too: an absent Flutter is not re-probed',
      () async {
    var calls = 0;
    final probe = ProcessFlutterSdkProbe(
      runProcess: (exe, args) async {
        calls++;
        throw const ProcessException('flutter', []);
      },
    );
    expect(await probe.probe(), isNull);
    expect(await probe.probe(), isNull);
    expect(calls, 1);
  });
}
