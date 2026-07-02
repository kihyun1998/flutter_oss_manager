import 'package:example/main.dart';
import 'package:example/oss_licenses.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(OssLicenses.resetForTest);

  testWidgets('loads and renders the open-source license list',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // The scaffold renders immediately; the list is still loading.
    expect(find.text('Open Source Licenses'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    // Once the decoded list resolves, the spinner is replaced by license
    // cards and no error is shown.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Failed to load'), findsNothing);
    expect(find.byType(Card), findsWidgets);
  });
}
