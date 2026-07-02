import 'dart:io';

import 'package:flutter_oss_manager/src/flutter_sdk_probe.dart';
import 'package:flutter_oss_manager/src/license_generator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Records how many times the SDK is probed.
class SpyFlutterSdkProbe implements FlutterSdkProbe {
  SpyFlutterSdkProbe([this.result]);
  final FlutterSdkInfo? result;
  int calls = 0;

  @override
  Future<FlutterSdkInfo?> probe() async {
    calls++;
    return result;
  }
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('scan_sdk_probe_');
    File(p.join(tmp.path, 'pubspec.lock')).writeAsStringSync('packages:\n');
    File(p.join(tmp.path, 'pubspec.yaml'))
        .writeAsStringSync('name: t\ndependencies:\n');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('a plain scan never probes the Flutter SDK', () async {
    final spy = SpyFlutterSdkProbe();
    final gen = LicenseGenerator(sdkProbe: spy, offline: true);
    await gen.scanPackages(projectRoot: tmp.path);
    expect(spy.calls, 0, reason: 'plain scan must not spawn flutter');
  });

  test('a runtime-only scan probes the Flutter SDK', () async {
    final spy = SpyFlutterSdkProbe();
    final gen = LicenseGenerator(sdkProbe: spy, offline: true);
    await gen.scanPackages(projectRoot: tmp.path, runtimeOnly: true);
    expect(spy.calls, greaterThanOrEqualTo(1));
  });
}
