/// B7 gate — the admin can produce a `.myhanoutlisting` from its own screen.
///
/// The exporter is injected because **sqflite cannot be awaited inside a
/// `testWidgets` FakeAsync zone** (verified: it hangs). The injected exporter
/// still builds a real Ed25519 bundle with the screen's resolved signer key, and
/// the file the share sheet receives is read back and run through the real
/// verifier — so the wiring is proven end to end. The real export path itself
/// is covered by `test/services/listing_export_test.dart`.
///
/// Run: flutter test test/screens/listing_push_test.dart
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/config.dart';
import 'package:myhanout/data/listing_bundle.dart';
import 'package:myhanout/data/settings_service.dart';
import 'package:myhanout/data/shop_provisioning_service.dart';
import 'package:myhanout/data/signing.dart';
import 'package:myhanout/models/listing_row.dart';
import 'package:myhanout/screens/listing_push_screen.dart';
import 'package:myhanout/services/listing_export_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/signing_trust.dart';

const _shopKey = 'hanouti';

const _rows = [
  ListingRow(barcode: '0011210006508', priceCents: 890, stockQty: 12),
  ListingRow(barcode: '6111053001673', priceCents: 150, stockQty: 0),
  ListingRow(barcode: '6111035001673', priceCents: 2200, stockQty: 3),
];

void main() {
  late SigningTrust trust;
  String? capturedJson;
  String? capturedName;
  // Built in setUp (a normal zone): `cryptography`'s async signing cannot be
  // awaited inside a `testWidgets` FakeAsync zone, for the same reason sqflite
  // cannot. The signing itself is covered by test/services/listing_*_test.dart.
  late String prebuiltJson;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    capturedJson = null;
    capturedName = null;
    trust = await SigningTrust.create();
    await Config.init();

    const settings = ConfigSettingsService();
    await settings.setActiveSignerId(SigningTrust.adminId);
    await settings.saveSignerKey(
        SigningTrust.adminId, trust.seed(SigningTrust.adminId));
    await ShopProvisioningService.createShop(
      name: 'Hanouti',
      key: _shopKey,
      registerOnServer: false,
      settings: settings,
    );
    await settings.setCurrentShopKey(_shopKey);

    prebuiltJson = await Signing.signArtifactFile(
      ListingBundle(
        signerId: SigningTrust.adminId,
        shopKey: _shopKey,
        catalogVersion: 7,
        generatedAt: 1,
        rows: _rows,
      ).toPayload(),
      trust.seed(SigningTrust.adminId),
    );
  });

  tearDown(() {
  });

  Future<void> settle(WidgetTester t, [int n = 15]) async {
    // Bounded pumps: the screen shows a CircularProgressIndicator, which
    // pumpAndSettle would wait on forever.
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('export produces a bundle the shopkeeper can verify',
      (tester) async {
    Future<ListingExportResult> exporter({
      required String shopKey,
      required String signerId,
      required List<int> privateSeed,
    }) async =>
        ListingExportResult(
          json: prebuiltJson,
          fileName: ListingExportBuilder.fileName(shopKey, 7),
          rows: _rows.length,
          catalogVersion: 7,
        );

    await tester.pumpWidget(
      Provider<SettingsService>.value(
        value: const ConfigSettingsService(),
        child: EasyLocalization(
          supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
          path: 'assets/lang',
          fallbackLocale: const Locale('fr'),
          startLocale: const Locale('fr'),
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              home: ListingPushScreen(
                exporter: exporter,
                deliverer: (shopKey, fileName, json) async {
                  capturedName = fileName;
                  capturedJson = json;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Exporter la liste de prix'), findsOneWidget);
    expect(find.text(_shopKey), findsWidgets);

    final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(btn.onPressed, isNotNull, reason: 'no shop selected');
    await tester.tap(find.text('Générer et partager'), warnIfMissed: true);
    await settle(tester, 40);

    expect(find.textContaining('Liste générée'), findsOneWidget);
    expect(capturedName, 'listing_hanouti_v7.myhanoutlisting');
    expect(capturedJson, isNotNull, reason: 'nothing was delivered');

    final v = await ListingBundle.verify(capturedJson!,
        directory: trust.directory);
    expect(v.ok, isTrue, reason: v.error);
    expect(v.signerName, SigningTrust.adminId);
    expect(v.bundle!.shopKey, _shopKey);
    expect(v.bundle!.rows, _rows);
  });
}
