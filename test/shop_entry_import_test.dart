/// B6 gate — the shopkeeper can reach the listing import from the entry screen,
/// and the VIEW-intent routing key is the file extension.
///
/// Run: flutter test test/shop_entry_import_test.dart
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/app_router.dart';
import 'package:myhanout/app_state.dart';
import 'package:myhanout/data/listing_import_file.dart';
import 'package:myhanout/data/myhanout_file.dart';
import 'package:myhanout/data/settings_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  test('VIEW intents are routed by extension, not by MIME type alone', () {
    expect(
        ListingImportFile.isListingUri(
            'content://x/listing_hanouti_v7.myhanoutlisting'),
        isTrue);
    expect(ListingImportFile.isListingUri('content://x/catalog_v8.myhanout'),
        isFalse);
    // Case-insensitive: file managers differ on the extension casing.
    expect(ListingImportFile.isListingUri('file://x/LISTING.MYHANOUTLISTING'),
        isTrue);
  });
}
