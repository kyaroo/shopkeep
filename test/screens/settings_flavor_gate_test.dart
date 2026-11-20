/// Flavor gate — the shopkeeper SettingsScreen must have no signing surface,
/// no provisioning surface and no editable business name.
///
/// `kIsAdmin` is a compile-time const, and `flutter test` compiles it false,
/// so this test sees exactly the shopkeeper view. The admin side (signers
/// directory + import, behind `if (kIsAdmin)`) is pinned by the source guard in
/// `tool/verify_flavor_gates.sh`.
///
/// No shop DB is opened any more: the attribution card that used to read it is
/// gone, so this file needs neither sqflite nor a throwaway shop file.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/settings_service.dart';
import 'package:myhanout/screens/settings_screen.dart';
import 'package:myhanout/theme.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_settings.dart';

const _shopKey = 'flavor-gate-test';
const _businessName = 'Atelier Test';

void main() {
  late FakeSettingsService settings;

  setUp(() async {
    settings = FakeSettingsService()
      ..currentShop = _shopKey
      ..businessName = _businessName;
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('fr'), Locale('ar')],
        path: 'assets/lang',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) => Provider<SettingsService>.value(
            value: settings,
            child: MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              theme: ThemeData().copyWith(
                extensions: const [AppTextStyles(null)],
              ),
              home: const SettingsScreen(shopKey: _shopKey),
            ),
          ),
        ),
      ),
    );
    // Bounded pumps: the catalog-version FutureBuilder settles asynchronously.
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('shopkeeper settings: no signer / provisioning surface, no '
      'editable business name, stored name still visible', (tester) async {
    await pumpSettings(tester);

    // The signer material moved to the admin Settings tab; none of it may
    // render in the shopkeeper flavor.
    expect(find.text('Security'), findsNothing,
        reason: 'the Security tab is gone (merged into Settings)');
    expect(find.text('Import signer key'), findsNothing,
        reason: 'no signing surface in the shopkeeper flavor');
    expect(find.text('Signers directory'), findsNothing);
    expect(find.text('Join shop'), findsNothing,
        reason: 'shop provisioning lives on the admin Shops tab');

    // No editable business-name field and no Save button.
    expect(find.byType(TextField), findsNothing,
        reason: 'shopkeeper must not expose an editable business-name field');
    expect(find.byType(ElevatedButton), findsNothing,
        reason: 'shopkeeper must not expose the Save button');

    // The stored provisioning value is still displayed as read-only text.
    expect(find.text(_businessName), findsOneWidget,
        reason: 'stored business name must remain visible as text');

    // Version rows are common to both flavors.
    expect(find.text('Catalog version'), findsOneWidget);
    expect(find.text('App version'), findsOneWidget);

    // Storage is untouched by merely viewing the screen.
    expect(settings.businessName, _businessName);
  });
}
