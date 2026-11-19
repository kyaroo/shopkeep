/// ShopInfoScreen: fetches on open, shows provisioner fields read-only, and
/// PATCHes only the edited contact field. The client is injected, so no HTTP,
/// no SharedPreferences and no real server token are involved.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myhanout/screens/shop_info_screen.dart';
import 'package:myhanout/services/shop_info_client.dart';

class _FakeClient extends ShopInfoClient {
  ShopInfoPatch? lastPatch;
  String? lastKey;

  _FakeClient() : super(baseUrl: '', token: '');

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
      businessName: 'Hanouti',
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

void main() {
  testWidgets('fetch on open, read-only provisioner, PATCH edited contact',
      (tester) async {
    final fake = _FakeClient();
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
            home: ShopInfoScreen(
              shopKey: 'hanouti',
              clientFactory: () async => fake,
            ),
          ),
        ),
      ),
    );
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    // Provisioner data is on screen but there is no edit affordance for it.
    expect(find.text('salesman-7'), findsOneWidget);
    expect(find.text('Youssef'), findsOneWidget);
    expect(find.text('salesman'), findsOneWidget);
    expect(find.text('Provisioning data is read-only.'), findsOneWidget);

    // key + four contact fields.
    expect(find.byType(TextField), findsNWidgets(5));

    // Edit only the address, then save.
    await tester.enterText(find.byType(TextField).at(1), '2 New Street');
    await tester.tap(find.text('Save changes'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(fake.lastKey, 'hanouti');
    expect(fake.lastPatch!.toJson(), {'address': '2 New Street'},
        reason: 'only the edited contact field may be sent to the server');
    expect(find.text('Shop info saved.'), findsOneWidget);
  });
}
