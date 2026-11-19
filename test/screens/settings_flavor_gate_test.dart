/// Flavor gate — the shopkeeper SettingsScreen must have no signing surface
/// and no business-name editing affordance.
///
/// `kIsAdmin` is a compile-time const, and `flutter test` compiles it false,
/// so this test sees exactly the shopkeeper view. The admin side is pinned by
/// the source guard in `tool/verify_flavor_gates.sh`.
///
/// The screen's attribution card reads the shop DB, so the throwaway shop DB
/// is cleared in BOTH setUp and tearDown: `flutter test` shares one SQLite
/// factory across files and a stale handle from another file would otherwise
/// leak into this one.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/db.dart';
import 'package:myhanout/data/settings_service.dart';
import 'package:myhanout/screens/settings_screen.dart';
import 'package:myhanout/theme.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fake_settings.dart';

const _shopKey = 'flavor-gate-test';
const _businessName = 'Atelier Test';

void main() {
  late FakeSettingsService settings;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Clear first, not only in tearDown — a previous test file may have left
    // the shared SQLite factory pointing at this key's file.
    await Db.closeShop(_shopKey);
    final file = await Db.shopDbFile(_shopKey);
    if (await file.exists()) await file.delete();
    await Db.open(_shopKey);

    settings = FakeSettingsService()
      ..currentShop = _shopKey
      ..businessName = _businessName;
  });

  tearDown(() async {
    await Db.closeShop(_shopKey);
    final file = await Db.shopDbFile(_shopKey);
    if (await file.exists()) await file.delete();
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
    // Bounded pumps: the attribution FutureBuilder shows a spinner, which
    // pumpAndSettle would wait on forever under FakeAsync.
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('shopkeeper settings has no signer import and no editable '
      'business name, but still shows the stored name', (tester) async {
    await pumpSettings(tester);

    // Item 1: the whole Security card (and its import path) is admin-only.
    expect(find.text('Security'), findsNothing,
        reason: 'Security card must not render in the shopkeeper flavor');
    expect(find.text('Import signer key'), findsNothing,
        reason: 'no signing surface in the shopkeeper flavor');

    // Item 11: no editable business-name field and no Save button.
    expect(find.byType(TextField), findsNothing,
        reason: 'shopkeeper must not expose an editable business-name field');
    expect(find.byType(ElevatedButton), findsNothing,
        reason: 'shopkeeper must not expose the Save button');

    // The stored provisioning value is still displayed as read-only text.
    expect(find.text(_businessName), findsOneWidget,
        reason: 'stored business name must remain visible as text');

    // Storage is untouched by merely viewing the screen.
    expect(settings.businessName, _businessName);
  });
}
