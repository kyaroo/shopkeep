// Phase 2 — distribution difference + confirmation.
//
// The screen must show shop version M / admin version N / the gap, build ONE
// multi-generation delta M→N from the server diff, and report the shop version
// only after the user confirms. All HTTP is faked.
//
// ONE EasyLocalization/MaterialApp tree for the whole isolate (a second one
// leaves the translation load stuck in the fake-async zone), and a tall
// surface so the build button is on-screen.
//
// Run: flutter test test/screens/catalog_push_multigen_test.dart
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/catalog_sync_client.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/screens/catalog_push_screen.dart';
import 'package:myhanout/services/catalog_delta_service.dart';
import 'package:myhanout/theme.dart';

import '../helpers/fake_settings.dart';
import '../helpers/signing_trust.dart';

class _FakeRepo implements CatalogRepository {
  final List<CatalogEntry> _rows = [
    CatalogEntry(
      barcode: 'A',
      name: 'Product A',
      category: 'grocery',
      createdAt: 1,
      updatedAt: 1,
    ),
  ];

  @override
  Future<void> init() async {}

  @override
  Future<CatalogEntry?> get(String barcode) async =>
      _rows.where((e) => e.barcode == barcode).firstOrNull;

  @override
  Future<List<CatalogEntry>> all({String? search, int? limit, int? offset}) async =>
      _rows;

  @override
  Future<void> upsert(CatalogEntry entry) async {}

  @override
  Future<void> delete(String barcode) async {}

  @override
  Future<int> count({String? search}) async => 0;
}

class _FakeClient extends CatalogSyncClient {
  List<ShopRow> shops;
  List<CatalogDiffChange> changes;
  int toVersion;

  int reportCount = 0;
  String? reportedShop;
  int? reportedVersion;

  _FakeClient({
    required this.shops,
    required this.changes,
    required this.toVersion,
  }) : super(baseUrl: '', token: '', deviceId: 'test');

  @override
  Future<ShopSearchResult> searchShops({
    String q = '',
    int? minVersion,
    int? maxVersion,
    int limit = 20,
    int offset = 0,
  }) async =>
      ShopSearchResult(
        items: shops,
        total: shops.length,
        limit: limit,
        offset: offset,
      );

  @override
  Future<CatalogDiffPage> catalogDiff({
    required int fromVersion,
    int limit = 100,
    int offset = 0,
  }) async =>
      CatalogDiffPage(
        fromVersion: fromVersion,
        toVersion: toVersion,
        total: changes.length,
        limit: limit,
        offset: offset,
        nextOffset: null,
        changes: changes,
      );

  @override
  Future<void> setCatalogVersion(String shopKey, int version) async {
    reportCount++;
    reportedShop = shopKey;
    reportedVersion = version;
  }

  @override
  void close() {}
}

CatalogDiffChange _upsert(String barcode, int version) => CatalogDiffChange(
      version: version,
      barcode: barcode,
      op: 'upsert',
      row: CatalogEntry(
        barcode: barcode,
        name: 'Product $barcode',
        category: 'grocery',
        createdAt: 1,
        updatedAt: version,
      ),
    );

CatalogDiffChange _delete(String barcode, int version) => CatalogDiffChange(
      version: version,
      barcode: barcode,
      op: 'delete',
      row: null,
    );

void main() {
  late SigningTrust trust;
  late FakeSettingsService settings;
  late _FakeClient client;

  setUp(() async {
    trust = await SigningTrust.create();
    settings = FakeSettingsService()
      ..signersEnvelope = trust.directory.envelope
      ..activeSignerId = SigningTrust.founderAdminId
      ..catalogVersion = 7;
    await settings.saveSignerKey(
        SigningTrust.founderAdminId, trust.seed(SigningTrust.founderAdminId));
    client = _FakeClient(
      shops: [
        const ShopRow(
          shopKey: 'hanouti',
          businessName: 'Hanouti',
          catalogVersion: 3,
          createdAt: 0,
        ),
      ],
      changes: [
        _upsert('A', 4),
        _upsert('B', 5),
        _delete('C', 6),
        _upsert('A', 7),
      ],
      toVersion: 7,
    );
  });

  Future<void> settle(WidgetTester t, [int n = 20]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('difference math, confirmation gating and refusals',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('fr'), Locale('ar')],
        path: 'assets/lang',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) => MaterialApp(
            theme: AppPalette.theme(),
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: CatalogPushScreen(
              settings: settings,
              repository: _FakeRepo(),
              clientFactory: () async => client,
              rootPublicKey: trust.rootPublic,
              builder: ({
                required localVersion,
                required shopVersion,
                required targetVersion,
                required signerId,
                required privateSeed,
                required entries,
                required deletes,
              }) async =>
                  DeltaBuildResult(
                    json: '{"format":"myhanout-catalog-delta"}',
                    upserts: entries.length,
                    deletes: deletes.length,
                    photosTrimmed: 0,
                    photosDropped: 0,
                  ),
              deliverer: (shopKey, target, fileName, json) async {},
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    // --- M / N / difference for the selected shop.
    await tester.tap(find.widgetWithText(ListTile, 'Hanouti'));
    await settle(tester, 5);
    expect(find.text('Shop version 3 - admin version 7'), findsOneWidget);
    expect(find.text('Difference: 4 generation(s)'), findsOneWidget);

    // --- Confirmation box: M -> N, the gap, and the counts.
    await tester.tap(find.text('Build and share the delta'));
    await settle(tester, 10);
    expect(find.text('Shop "hanouti": version 3 -> 7 (4 generation(s)).'),
        findsOneWidget);
    expect(find.text('3 change(s): 1 addition(s), 1 update(s), 1 delete(s).'),
        findsOneWidget);
    expect(client.reportCount, 0, reason: 'nothing reported before confirming');

    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await settle(tester, 5);
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'confirming must close the dialog');
    await settle(tester, 40);
    expect(client.reportedShop, 'hanouti');
    expect(client.reportedVersion, 7,
        reason: 'the shop must be reported at the admin target N');
    expect(client.reportCount, 1);

    // --- Cancelling the confirmation reports nothing further.
    await tester.tap(find.text('Build and share the delta'));
    await settle(tester, 10);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester, 20);
    expect(client.reportCount, 1,
        reason: 'cancelling must not report a version');

    // --- A shop that never reported (M = 0) is refused.
    client.shops = [
      const ShopRow(
        shopKey: 'hanouti',
        businessName: 'Hanouti',
        catalogVersion: 0,
        createdAt: 0,
      ),
    ];
    await tester.tap(find.widgetWithText(FilterChip, 'v1'));
    await settle(tester, 8);
    await tester.tap(find.widgetWithText(FilterChip, 'All versions'));
    await settle(tester, 8);
    await tester.tap(find.widgetWithText(ListTile, 'Hanouti'));
    await settle(tester, 5);
    await tester.tap(find.text('Build and share the delta'));
    await settle(tester, 10);
    expect(find.textContaining('has no catalog version yet'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(client.reportCount, 1);
    // Let the snackbar clear so the next one is not queued behind it.
    await settle(tester, 50);

    // --- A shop ahead of the admin (M > N) is refused.
    client.shops = [
      const ShopRow(
        shopKey: 'hanouti',
        businessName: 'Hanouti',
        catalogVersion: 9,
        createdAt: 0,
      ),
    ];
    await tester.tap(find.widgetWithText(FilterChip, 'v1'));
    await settle(tester, 8);
    await tester.tap(find.widgetWithText(FilterChip, 'All versions'));
    await settle(tester, 8);
    await tester.tap(find.widgetWithText(ListTile, 'Hanouti'));
    await settle(tester, 5);
    expect(find.text('Shop version 9 - admin version 7'), findsOneWidget,
        reason: 'the refetched shop must be selected');
    await tester.tap(find.text('Build and share the delta'));
    await settle(tester, 5);
    expect(find.textContaining('Version mismatch'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(client.reportCount, 1);
  });
}
