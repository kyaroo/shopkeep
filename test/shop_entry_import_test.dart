/// B6 gate — the shopkeeper can reach the listing import from the entry screen,
/// and the VIEW-intent routing key is the file extension.
///
/// Run: flutter test test/shop_entry_import_test.dart
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/app_router.dart';
import 'package:myhanout/app_state.dart';
import 'package:myhanout/data/listing_import_file.dart';
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
