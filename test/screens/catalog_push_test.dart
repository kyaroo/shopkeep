/// Catalog push refuses a salesman active signer at push time (role re-check).
///
/// Everything the screen touches is injected: a [FakeSettingsService] carrying
/// the THROWAWAY trust directory (never `assets/signers.json` / real seeds), an
/// in-memory [CatalogRepository], and a client factory returning a fake client
/// whose `listShops` needs no HTTP. The only crypto is the screen's own
/// ROOT-verified directory lookup via the injected throwaway root key.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/catalog_sync_client.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/screens/catalog_push_screen.dart';
import 'package:myhanout/theme.dart';

import '../helpers/fake_settings.dart';
import '../helpers/signing_trust.dart';

class _FakeRepo implements CatalogRepository {
  @override
  Future<void> init() async {}

  @override
  Future<CatalogEntry?> get(String barcode) async => null;

  @override
  Future<List<CatalogEntry>> all({String? search, int? limit, int? offset}) =>
      Future.value(const <CatalogEntry>[]);

  @override
  Future<void> upsert(CatalogEntry entry) async {}

  @override
  Future<void> delete(String barcode) async {}

  @override
  Future<int> count({String? search}) async => 0;
}

class _FakeClient extends CatalogSyncClient {
  _FakeClient() : super(baseUrl: '', token: '', deviceId: 'test-device');

  @override
  Future<ShopSearchResult> searchShops({
    String q = '',
    int? minVersion,
    int? maxVersion,
    int limit = 20,
    int offset = 0,
  }) async {
    const all = [
      ShopRow(
        shopKey: 'hanouti',
        businessName: 'Hanouti',
        catalogVersion: 1,
        createdAt: 0,
      ),
    ];
    final rows = q.isEmpty ? all : all.where((s) => s.businessName.toLowerCase().contains(q.toLowerCase())).toList();
    return ShopSearchResult(
      items: offset >= rows.length ? const [] : rows.sublist(offset),
      total: rows.length,
      limit: limit,
      offset: offset,
    );
  }

  @override
  void close() {}
}

void main() {
  late SigningTrust trust;
  late FakeSettingsService settings;

  setUp(() async {
    trust = await SigningTrust.create();
    settings = FakeSettingsService()
      ..signersEnvelope = trust.directory.envelope
      ..activeSignerId = SigningTrust.salesmanId
      ..catalogVersion = 1;
    await settings.saveSignerKey(
        SigningTrust.salesmanId, trust.seed(SigningTrust.salesmanId));
  });

  Future<void> settle(WidgetTester t, [int n = 20]) async {
    // Bounded pumps: the screen shows a CircularProgressIndicator while
    // loading, so pumpAndSettle would never return.
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('catalog push refuses a salesman active signer', (tester) async {
    // Tall surface: the selection card pushes the build button below the
    // default 600 px viewport.
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
        path: 'assets/lang',
        fallbackLocale: const Locale('fr'),
        startLocale: const Locale('fr'),
        child: Builder(
          builder: (context) => MaterialApp(
            theme: AppPalette.theme(),
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: CatalogPushScreen(
              settings: settings,
              repository: _FakeRepo(),
              clientFactory: () async => _FakeClient(),
              rootPublicKey: trust.rootPublic,
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    // The fake shop list loaded — no real HTTP, no real DB.
    expect(find.text('Hanouti'), findsOneWidget,
        reason: 'fake shop list did not load');

    // Select the shop so the build button becomes enabled.
    await tester.tap(find.text('Hanouti'));
    await settle(tester, 5);

    final buildBtn = find.byType(FilledButton);
    expect(buildBtn, findsOneWidget);
    expect(tester.widget<FilledButton>(buildBtn).onPressed, isNotNull,
        reason: 'build button disabled after shop selection');

    await tester.tap(buildBtn);
    await settle(tester, 40);

    // The role re-check refuses before any payload is built or delivered:
    // a refusal snackbar, and no delivery-confirmation dialog.
    expect(find.textContaining('Only founder or admin'), findsOneWidget,
        reason: 'catalog push did not refuse the salesman signer');
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'a delivery dialog must not appear when the push is refused');
  });
}
