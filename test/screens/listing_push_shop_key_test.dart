/// The optional `shopKey` pre-selects the target and skips the picker.
///
/// Run: flutter test test/screens/listing_push_shop_key_test.dart
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/settings_service.dart';
import 'package:myhanout/screens/listing_push_screen.dart';
import 'package:myhanout/services/listing_export_service.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_settings.dart';
import '../helpers/signing_trust.dart';

void main() {
  late SigningTrust trust;
  late FakeSettingsService settings;

  setUp(() async {
    trust = await SigningTrust.create();
    settings = FakeSettingsService()
      ..signersEnvelope = trust.directory.envelope
      ..activeSignerId = SigningTrust.founderAdminId
      ..currentShop = 'other';
    settings.shops.addAll(['hanouti', 'other']);
    await settings.saveSignerKey(
        SigningTrust.founderAdminId, trust.seed(SigningTrust.founderAdminId));
  });

  Future<void> settle(WidgetTester t, [int n = 20]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('shopKey pre-selects the shop and skips the picker',
      (tester) async {
    String? exported;

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
              home: ListingPushScreen(
                shopKey: 'hanouti',
                rootPublicKey: trust.rootPublic,
                exporter: ({
                  required shopKey,
                  required signerId,
                  required privateSeed,
                }) async {
                  exported = shopKey;
                  return ListingExportResult(
                    json: '{}',
                    fileName: 'listing_$shopKey.json',
                    rows: 1,
                    catalogVersion: 1,
                  );
                },
                deliverer: (shopKey, fileName, json) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.byType(DropdownButton<String>), findsNothing,
        reason: 'the picker must be skipped when shopKey is provided');
    expect(find.text('Target shop: hanouti'), findsOneWidget);

    await tester.tap(find.text('Build and share'));
    await settle(tester, 40);

    expect(exported, 'hanouti');
  });
}
