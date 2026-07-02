import 'package:example/oss_licenses.g.dart';
import 'package:flutter_test/flutter_test.dart';

/// Behavioral coverage of the generated `OssLicenses.use()` helper. This runs
/// against the *compiled* generated code, which the tool's own unit suite
/// cannot do (there `OssLicenses` exists only as a string template).
void main() {
  setUp(OssLicenses.resetForTest);

  test('use() returns the callback value', () async {
    expect(await OssLicenses.use((_) => 42), 42);
  });

  test('use() passes the decoded license list to the callback', () async {
    final list = await OssLicenses.use((licenses) => licenses);
    expect(list, isA<List<OssLicense>>());
  });

  test('use() supports async callbacks', () async {
    final v = await OssLicenses.use((_) async {
      await Future<void>.delayed(Duration.zero);
      return 'ok';
    });
    expect(v, 'ok');
  });

  test('use() releases its reference on success (ref-count back to 0)',
      () async {
    await OssLicenses.use((_) => 0);
    expect(OssLicenses.refCountForTest, 0);
  });

  test('use() releases its reference even when the callback throws', () async {
    await expectLater(
      OssLicenses.use<void>((_) => throw StateError('boom')),
      throwsStateError,
    );
    expect(
      OssLicenses.refCountForTest,
      0,
      reason: 'a thrown callback must not leave the ref-count stuck above zero',
    );
  });
}
