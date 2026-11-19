/// Widget test for the signer import screen with an injected fake store.
///
/// The screen offers both decision-2a entry points (QR scan + `.myhanoutseed`
/// file picker) and never renders a seed. Cryptography can't be awaited inside
/// a `testWidgets` FakeAsync zone, so this test exercises rendering, the two
/// entry points, and the synchronous rejection path; the full verification
/// matrix lives in `test/signer_import_test.dart` (normal zone).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/screens/signer_import_screen.dart';

import '../helpers/fake_settings.dart';

Future<void> _pump(WidgetTester tester, FakeSettingsService settings) async {
  await tester.pumpWidget(
    MaterialApp(home: SignerImportScreen(settings: settings)),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('renders both input paths with injected settings',
      (tester) async {
    await _pump(tester, FakeSettingsService());

    expect(find.text('Import signer key'), findsWidgets);
    expect(find.text('Scan QR'), findsOneWidget);
    expect(find.text('Choose .myhanoutseed file'), findsOneWidget);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue, reason: 'seed must never be shown');
  });

  testWidgets('malformed envelope is rejected and the buffer cleared',
      (tester) async {
    final settings = FakeSettingsService();
    await _pump(tester, settings);

    await tester.enterText(find.byType(TextField), '{not-json');
    await tester.tap(find.text('Import'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Invalid signer seed'), findsOneWidget);
    expect(find.text('{not-json'), findsNothing, reason: 'buffer not cleared');
    expect(settings.signerKeys, isEmpty);
    expect(settings.activeSignerId, isNull);
  });
}
