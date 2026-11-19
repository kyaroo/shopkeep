/// Negative listing-push widget test: a salesman active signer must be refused
/// at push time even when a valid seed and a selected shop are present.
///
/// Kept in its own test file because a second `EasyLocalization` widget in the
/// same isolate leaves its translation load stuck in the `testWidgets`
/// fake-async zone. Everything is injected (fake settings with the THROWAWAY
/// directory, no SharedPreferences, no sqflite, no HTTP) and the throwaway root
/// verifies the directory, so no real signers.json / seeds are involved.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/settings_service.dart';
import 'package:myhanout/models/listing_row.dart';
import 'package:myhanout/screens/listing_push_screen.dart';
import 'package:myhanout/services/listing_export_service.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_settings.dart';
import '../helpers/signing_trust.dart';

const _shopKey = 'hanouti';
const _rows = [
  ListingRow(barcode: '0011210006508', priceCents: 890, stockQty: 12),
];

void main() {
  late SigningTrust trust;
  late FakeSettingsService settings;

  setUp(() async {
    trust = await SigningTrust.create();
    settings = FakeSettingsService()
      ..signersEnvelope = trust.directory.envelope
      ..activeSignerId = SigningTrust.salesmanId
      ..currentShop = _shopKey;
    settings.shops.add(_shopKey);
    await settings.saveSignerKey(
        SigningTrust.salesmanId, trust.seed(SigningTrust.salesmanId));
  });

  Future<void> settle(WidgetTester t, [int n = 15]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('salesman active signer is refused at push time', (tester) async {
    bool exporterCalled = false;
    bool delivererCalled = false;

    await tester.pumpWidget(
      Provider<SettingsService>.value(
        value: settings,
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
                rootPublicKey: trust.rootPublic,
                exporter: ({
                  required shopKey,
                  required signerId,
                  required privateSeed,
                }) async {
                  exporterCalled = true;
                  return ListingExportResult(
                    json: '{}',
                    fileName: 'listing_${shopKey}_v7.myhanoutlisting',
                    rows: _rows.length,
                    catalogVersion: 7,
                  );
                },
                deliverer: (shopKey, fileName, json) async {
                  delivererCalled = true;
                },
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    final elevBtn = find.byType(ElevatedButton);
    expect(elevBtn, findsOneWidget);
    final btn = tester.widget<ElevatedButton>(elevBtn);
    expect(btn.onPressed, isNotNull, reason: 'no shop selected');
    await tester.tap(elevBtn, warnIfMissed: true);
    await settle(tester, 40);

    expect(exporterCalled, isFalse,
        reason: 'exporter must not run for a salesman signer');
    expect(delivererCalled, isFalse,
        reason: 'deliverer must not run for a salesman signer');
    expect(find.textContaining('founder or admin'), findsOneWidget,
        reason: 'the push-time refusal snackbar was not shown');
  });
}
