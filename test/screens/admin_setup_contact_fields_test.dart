/// The Shops tab create form forwards the four optional contact fields to the
/// server registration, and an empty contact field is non-blocking (the shop is
/// still created locally and registered).
///
/// Run: flutter test test/screens/admin_setup_contact_fields_test.dart
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/catalog_sync_client.dart';
import 'package:myhanout/data/settings_service.dart';
import 'package:myhanout/screens/admin_setup_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_settings.dart';

class _RecordingClient extends CatalogSyncClient {
  String? key;
  String? name;
  String? address;
  String? city;
  String? ownerName;
  String? phone;

  _RecordingClient()
      : super(baseUrl: '', token: '', deviceId: 'test');

  @override
  Future<void> registerShop(
    String shopKey,
    String businessName, {
    String? address,
    String? city,
    String? ownerName,
    String? phone,
  }) async {
    key = shopKey;
    name = businessName;
    this.address = address;
    this.city = city;
    this.ownerName = ownerName;
    this.phone = phone;
  }

  @override
  void close() {}
}

Future<void> settle(WidgetTester t, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeSettingsService settings;
  late _RecordingClient client;

  setUp(() {
    settings = FakeSettingsService();
    client = _RecordingClient();
    SharedPreferences.setMockInitialValues(const {
      'sync_url': 'https://catalog.example.test',
      'sync_token': 'token-123',
    });
  });

  testWidgets('create form forwards contact fields; empty ones are fine',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      Provider<SettingsService>.value(
        value: settings,
        child: EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('fr'), Locale('ar')],
          path: 'assets/lang',
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              navigatorKey: navKey,
              home: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    Future<void> pushForm() async {
      navKey.currentState!.push(MaterialPageRoute(
        builder: (_) => AdminSetupScreen(clientFactory: () async => client),
      ));
      await settle(tester);
    }

    Future<void> submitAndCloseQr() async {
      await tester.tap(find.text('Create shop'));
      await settle(tester, 15);
      // Close the provisioning QR dialog to reveal the state card.
      if (find.text('Close').evaluate().isNotEmpty) {
        await tester.tap(find.text('Close'));
        await settle(tester, 10);
      }
    }

    // 1. Every field filled.
    await pushForm();
    await tester.enterText(find.byType(TextField).at(0), 'Hanouti');
    await tester.enterText(find.byType(TextField).at(2), '12 Rue Omar');
    await tester.enterText(find.byType(TextField).at(3), 'Casablanca');
    await tester.enterText(find.byType(TextField).at(4), 'Amina');
    await tester.enterText(find.byType(TextField).at(5), '0600000000');
    await settle(tester, 5);
    await submitAndCloseQr();

    expect(client.key, 'hanouti');
    expect(client.name, 'Hanouti');
    expect(client.address, '12 Rue Omar');
    expect(client.city, 'Casablanca');
    expect(client.ownerName, 'Amina');
    expect(client.phone, '0600000000');
    expect(find.text('Registered on server'), findsOneWidget);
    navKey.currentState!.pop();
    await settle(tester, 8);

    // 2. Business name only: the four contact fields are optional and must not
    // block creation. The key still auto-generates from the name.
    settings.shops.clear();
    await pushForm();
    await tester.enterText(find.byType(TextField).at(0), 'Boutique Larbi');
    await settle(tester, 5);
    await submitAndCloseQr();

    expect(settings.shops, contains('boutique_larbi'),
        reason: 'an empty contact field must not block creation');
    expect(client.key, 'boutique_larbi');
    expect(client.address, '');
    expect(client.city, '');
    expect(client.ownerName, '');
    expect(client.phone, '');
    expect(find.text('Registered on server'), findsOneWidget);
  });
}
