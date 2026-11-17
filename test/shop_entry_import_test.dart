/// B6 gate — the shopkeeper can reach the listing import from the entry screen,
/// and the VIEW-intent routing key is the file extension.
///
/// Run: flutter test test/shop_entry_import_test.dart
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/app_router.dart';
import 'package:myhanout/app_state.dart';
import 'package:myhanout/data/catalog_delta.dart';
import 'package:myhanout/data/listing_bundle.dart';
import 'package:myhanout/data/myhanout_file.dart';
import 'package:myhanout/data/signing.dart';
import 'package:myhanout/data/settings_service.dart';
import 'package:myhanout/models/listing_row.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/signing_trust.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('the entry screen offers import, scan and join', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState()..shopKey = '';
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SettingsService>.value(
              value: const ConfigSettingsService()),
        ],
        // An empty shop key routes to the shop entry screen.
        child: AppRouter(
          appState: appState,
          settings: const ConfigSettingsService(),
        ),
      ),
    );
    await settle(tester);

    // The entry screen boots in French.
    expect(find.text('Importer la boutique'), findsOneWidget);
    expect(find.text('Scanner le QR'), findsOneWidget);
    expect(find.text('Rejoindre la boutique'), findsOneWidget);
    // The hint names the file type, so the shopkeeper knows what to look for.
    expect(find.textContaining('.myhanoutlisting'), findsOneWidget);
  });

  test('the launch intent is consumed exactly once', () async {
    // Regression: both the entry screen and the app screen mount during a
    // successful import, so a non-cleared intent would be applied twice.
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('myhanout/view'),
            (call) async {
      calls.add(call.method);
      if (call.method == 'getInitialUri') {
        return 'file:///x/catalog_hanouti_v2.myhanout';
      }
      if (call.method == 'readUri') return 'not-a-bundle';
      return null;
        });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('myhanout/view'), null));

    final result = await MyhanoutFile.handleLaunchIntent();

    // Consumed before processing, so a second screen never re-applies it.
    expect(calls.first, 'getInitialUri');
    expect(calls[1], 'clearInitialUri');
    expect(calls.contains('readUri'), isTrue);
    expect(result, isNotNull);
    expect(result, startsWith('rejected:'));
  });

  test('routing uses the signed format, not the URI spelling', () async {
    // Regression: a `content://` URI carries no extension, so matching on
    // `.myhanoutlisting` sent real listing bundles down the catalog path.
    final trust = await SigningTrust.create();
    final listing = await Signing.signArtifactFile(
      ListingBundle(
        signerId: SigningTrust.adminId,
        shopKey: 'hanouti',
        catalogVersion: 7,
        generatedAt: 1,
        rows: const [ListingRow(barcode: '0011210006508', priceCents: 890, stockQty: 12)],
      ).toPayload(),
      trust.seed(SigningTrust.adminId),
    );
    final delta = await Signing.signArtifactFile(
      CatalogDelta(
        signerId: SigningTrust.adminId,
        baseVersion: 1,
        targetVersion: 2,
        generatedAt: 2,
        upserts: const [],
      ).toPayload(),
      trust.seed(SigningTrust.adminId),
    );

    expect(MyhanoutFile.sniffFormat(listing), ListingBundle.format);
    expect(MyhanoutFile.sniffFormat(delta), CatalogDelta.format);
    for (final junk in ['', '{', 'null', 'not-a-bundle', '{"format": 123}']) {
      expect(MyhanoutFile.sniffFormat(junk), isNull, reason: junk);
    }
  });
}
