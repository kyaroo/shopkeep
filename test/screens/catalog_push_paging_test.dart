/// Paged shop list in CatalogPushScreen: q search (debounced), version-range
/// filter chips, limit/offset load-more and grouping by catalog_version.
/// All HTTP is faked; the push/delta path is untouched by these assertions.
///
/// One EasyLocalization widget per isolate: a second one leaves the translation
/// load stuck in the fake-async zone, so every phase pushes a fresh screen
/// through the SAME navigator tree.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/catalog_sync_client.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/screens/catalog_push_screen.dart';
import 'package:myhanout/theme.dart';

import '../helpers/fake_settings.dart';

class _Call {
  final String q;
  final int? min;
  final int? max;
  final int limit;
  final int offset;
  _Call(this.q, this.min, this.max, this.limit, this.offset);
}

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

/// 5 shops across versions 0/1/2. Caps each page at 2 so load-more is exercised
/// even though the screen asks for 20.
class _PagedClient extends CatalogSyncClient {
  final List<_Call> calls = [];
  static const shops = [
    ShopRow(shopKey: 'alpha', businessName: 'Alpha', catalogVersion: 0, createdAt: 0),
    ShopRow(shopKey: 'bravo', businessName: 'Bravo', catalogVersion: 1, createdAt: 0),
    ShopRow(shopKey: 'charlie', businessName: 'Charlie', catalogVersion: 1, createdAt: 0),
    ShopRow(shopKey: 'delta', businessName: 'Delta', catalogVersion: 2, createdAt: 0),
    ShopRow(shopKey: 'echo', businessName: 'Echo', catalogVersion: 2, createdAt: 0),
  ];

  _PagedClient() : super(baseUrl: '', token: '', deviceId: 'test');

  @override
  Future<ShopSearchResult> searchShops({
    String q = '',
    int? minVersion,
    int? maxVersion,
    int limit = 20,
    int offset = 0,
  }) async {
    calls.add(_Call(q, minVersion, maxVersion, limit, offset));
    final rows = shops.where((s) {
      final matchQ = q.isEmpty ||
          s.businessName.toLowerCase().contains(q.toLowerCase()) ||
          s.shopKey.contains(q.toLowerCase());
      final matchMin = minVersion == null || s.catalogVersion >= minVersion;
      final matchMax = maxVersion == null || s.catalogVersion <= maxVersion;
      return matchQ && matchMin && matchMax;
    }).toList();
    const pageSize = 2;
    final page = offset >= rows.length
        ? <ShopRow>[]
        : rows.sublist(offset,
            (offset + pageSize > rows.length) ? rows.length : offset + pageSize);
    return ShopSearchResult(
      items: page,
      total: rows.length,
      limit: pageSize,
      offset: offset,
    );
  }

  @override
  void close() {}
}

void main() {
  Future<void> settle(WidgetTester t, [int n = 20]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('paged shop list: search, filter, load-more, grouping',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final settings = FakeSettingsService()..catalogVersion = 1;

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
            navigatorKey: navKey,
            home: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    // Tall surface so the lazily-built ListView mounts every row and the
    // load-more button, which lives far down the scroll.
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await settle(tester);

    Future<_PagedClient> open() async {
      final client = _PagedClient();
      navKey.currentState!.push(MaterialPageRoute(
        builder: (_) => CatalogPushScreen(
          settings: settings,
          repository: _FakeRepo(),
          clientFactory: () async => client,
        ),
      ));
      await settle(tester);
      return client;
    }

    Future<void> close() async {
      navKey.currentState!.pop();
      await settle(tester, 8);
    }

    // PHASE 1: first page uses limit/offset and renders version group headers.
    var client = await open();
    expect(client.calls, isNotEmpty);
    expect(client.calls.first.q, '');
    expect(client.calls.first.limit, 20);
    expect(client.calls.first.offset, 0);
    expect(find.text('Catalog version 0'), findsOneWidget);
    expect(find.text('Catalog version 1'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Bravo'), findsOneWidget);
    expect(find.text('Charlie'), findsNothing,
        reason: 'only the first 2-row page should be loaded');
    expect(find.text('Load more'), findsOneWidget);
    await close();

    // PHASE 2: load-more appends with increasing offset until exhausted.
    client = await open();
    await tester.tap(find.text('Load more'));
    await settle(tester, 8);
    expect(client.calls.last.offset, 2);
    expect(find.text('Charlie'), findsOneWidget);
    // The ListView is lazy: offscreen rows are not mounted, so assert the
    // visible "Showing N of M" summary instead of the appended row text.
    expect(find.text('Showing 4 of 5 shops'), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await settle(tester, 8);
    expect(client.calls.last.offset, 4);
    expect(find.text('Showing 5 of 5 shops'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
    await close();

    // PHASE 3: debounced q search re-fetches from offset 0.
    client = await open();
    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    await tester.enterText(field, 'Delta');
    await tester.pump(const Duration(milliseconds: 100));
    final before = client.calls.length;
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester, 8);
    expect(client.calls.length, greaterThan(before));
    expect(client.calls.last.q, 'Delta');
    expect(client.calls.last.offset, 0);
    // The search field's EditableText also contains "Delta"; target the row.
    expect(find.widgetWithText(ListTile, 'Delta'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    await close();

    // PHASE 4: version-range chip passes min_version to the search.
    client = await open();
    await tester.tap(find.widgetWithText(FilterChip, 'v2 and later'));
    await settle(tester, 8);
    expect(client.calls.last.min, 2);
    expect(client.calls.last.max, isNull);
    expect(find.text('Catalog version 2'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
    await close();
  });
}
