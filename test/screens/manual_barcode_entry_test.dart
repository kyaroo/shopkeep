import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/screens/manual_barcode_entry.dart';

/// The manual barcode entry is the fallback when a label is damaged or gone,
/// so it has to hand the exact same string to the caller as a camera detection
/// would — no second lookup path, no silently dropped input.
///
/// All phases share ONE widget tree: EasyLocalization's in-memory singleton
/// leaks locale state across separate `testWidgets` invocations, which makes
/// later tests see an unloaded asset bundle (the same reason widget_test.dart
/// runs its phases in one test).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final submitted = <String>[];

  testWidgets('manual barcode entry behaves like a scan', (tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
        path: 'assets/lang',
        fallbackLocale: const Locale('fr'),
        startLocale: const Locale('fr'),
        child: Builder(
          builder: (context) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Scaffold(
              body: ManualBarcodeEntry(onSubmit: submitted.add),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Phase 1 — the check button submits the typed barcode.
    await tester.enterText(find.byType(TextField), '6111053001673');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    expect(submitted, ['6111053001673']);

    // Phase 2 — the keyboard done action submits too.
    await tester.enterText(find.byType(TextField), '3505631400016');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submitted, ['6111053001673', '3505631400016']);

    // Phase 3 — surrounding whitespace is trimmed.
    await tester.enterText(find.byType(TextField), '  6701999116324  ');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    expect(submitted, ['6111053001673', '3505631400016', '6701999116324']);

    // Phase 4 — blank input is not a scan: nothing is handed over.
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pump();
    expect(submitted.length, 3);
  });
}
