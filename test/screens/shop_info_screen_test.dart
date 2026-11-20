/// ShopInfoScreen: fetches on open, shows provisioner fields read-only, PATCHes
/// only the edited field — and gates the business name on the token role.
///
/// Role source is `GET /v1/sync/status` through an injected sync client, so no
/// HTTP, no SharedPreferences and no real server token are involved.
///
/// ONE EasyLocalization/MaterialApp tree for the whole isolate: the three role
/// scenarios push a fresh ShopInfoScreen route through the same navigator (the
/// existing admin_home_test documents why a second tree wedges the translation
/// load).
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myhanout/data/catalog_sync_client.dart';
import 'package:myhanout/screens/shop_info_screen.dart';
import 'package:myhanout/services/shop_info_client.dart';

class _FakeInfoClient extends ShopInfoClient {
  ShopInfoPatch? lastPatch;
  String? lastKey;

  _FakeInfoClient() : super(baseUrl: '', token: '');

  @override
  Future<ShopInfo> fetch(String shopKey) async => ShopInfo(
        shopKey: shopKey,
        businessName: 'Hanouti',
        address: '1 Old Street',
        city: 'Casablanca',
        ownerName: 'Amina',
        phone: '0600000000',
        provisionerSignerId: 'salesman-7',
        provisionerName: 'Youssef',
        provisionerRole: 'salesman',
        catalogVersion: 2,
      );

  @override
  Future<ShopInfo> patch(String shopKey, ShopInfoPatch patch) async {
    lastKey = shopKey;
    lastPatch = patch;
    return ShopInfo(
      shopKey: shopKey,
      businessName: patch.businessName ?? 'Hanouti',
      address: patch.address ?? '1 Old Street',
      city: patch.city ?? 'Casablanca',
      ownerName: patch.ownerName ?? 'Amina',
      phone: patch.phone ?? '0600000000',
      provisionerSignerId: 'salesman-7',
      provisionerName: 'Youssef',
      provisionerRole: 'salesman',
      catalogVersion: 2,
    );
  }

  @override
  void close() {}
}

/// Supplies the role the business-name field is gated on. A null [role] makes
/// `syncRole()` throw, i.e. "unknown".
class _FakeSyncClient extends CatalogSyncClient {
  final String? role;

  _FakeSyncClient(this.role) : super(baseUrl: '', token: '', deviceId: 'test');

  @override
  Future<String> syncRole() async {
    final r = role;
    if (r == null) throw SyncException('offline');
    return r;
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
  testWidgets('business name is read-only for a salesman, editable for owner',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final navKey = GlobalKey<NavigatorState>();
    final info = _FakeInfoClient();
    await tester.pumpWidget(
      EasyLocalization(
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
    );
    await settle(tester);

    Future<void> open(String? role) async {
      navKey.currentState!.push(MaterialPageRoute(
        builder: (_) => ShopInfoScreen(
          shopKey: 'hanouti',
          clientFactory: () async => info,
          syncClientFactory: () async => _FakeSyncClient(role),
        ),
      ));
      await settle(tester);
    }

    // --- Salesman: the business name is NOT editable, the contact fields are.
    await open('salesman');
    expect(find.text('salesman-7'), findsOneWidget);
    expect(find.text('Provisioning data is read-only.'), findsOneWidget);
    // key + four contact fields; the name is a read-only row, not a TextField.
    expect(find.byType(TextField), findsNWidgets(5));
    expect(find.text('Hanouti'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), '2 New Street');
    await tester.tap(find.text('Save changes'));
    await settle(tester, 10);

    expect(info.lastKey, 'hanouti');
    expect(info.lastPatch!.toJson(), {'address': '2 New Street'},
        reason: 'a salesman patch must never carry business_name');
    expect(find.text('Shop info saved.'), findsOneWidget);
    navKey.currentState!.pop();
    await settle(tester, 8);

    // --- Owner: the name is editable and only travels when it changed.
    await open('owner');
    expect(find.byType(TextField), findsNWidgets(6),
        reason: 'owner gets the business-name field');
    expect(find.widgetWithText(TextField, 'Hanouti'), findsOneWidget);

    // Untouched name → not sent.
    await tester.enterText(find.byType(TextField).at(3), 'Rabat');
    await tester.tap(find.text('Save changes'));
    await settle(tester, 10);
    expect(info.lastPatch!.toJson(), {'city': 'Rabat'},
        reason: 'an unchanged business name must not be sent');
    navKey.currentState!.pop();
    await settle(tester, 8);

    // Changed name → sent.
    await open('owner');
    await tester.enterText(find.byType(TextField).at(1), 'Hanouti Plus');
    await tester.tap(find.text('Save changes'));
    await settle(tester, 10);
    expect(info.lastPatch!.toJson(), {'business_name': 'Hanouti Plus'});
    expect(find.text('Shop info saved.'), findsOneWidget);
    navKey.currentState!.pop();
    await settle(tester, 8);

    // --- Unknown role (probe failed): read-only, fail closed.
    await open(null);
    expect(find.byType(TextField), findsNWidgets(5),
        reason: 'an unknown role must not unlock the name field');
    expect(find.text('Hanouti'), findsOneWidget);
  });
}
