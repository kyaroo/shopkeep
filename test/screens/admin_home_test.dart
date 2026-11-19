/// Widget test for the AdminHome shell: signer indicator, Catalog tab button
/// set, per-shop menu, Catalog management gating and the Settings tab actions.
///
/// ONE EasyLocalization/MaterialApp tree for the whole isolate: a second one
/// leaves the translation load stuck in the fake-async zone, so every phase
/// runs through this single injected tree.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/admin_home_app.dart';
import 'package:myhanout/data/catalog_delta.dart';
import 'package:myhanout/data/catalog_sync_client.dart';
import 'package:myhanout/data/settings_service.dart';
import 'package:myhanout/data/signers_directory.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/providers/catalog_provider.dart';
import 'package:myhanout/screens/admin_home_screen.dart';
import 'package:myhanout/screens/capture_dialog.dart';
import 'package:myhanout/screens/settings_screen.dart';
import 'package:myhanout/theme.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_settings.dart';
import '../helpers/signing_trust.dart';

/// Fake diff client for the « Update catalog » action (no network).
class _FakePullClient extends CatalogSyncClient {
  final List<CatalogDiffChange> changes;
  final int toVersion;
  int diffCalls = 0;

  _FakePullClient(this.changes, this.toVersion)
      : super(baseUrl: '', token: '', deviceId: 'test');

  @override
  Future<CatalogDiffPage> catalogDiff({
    required int fromVersion,
    int limit = 100,
    int offset = 0,
  }) async {
    diffCalls++;
    return CatalogDiffPage(
      fromVersion: fromVersion,
      toVersion: toVersion,
      total: changes.length,
      limit: limit,
      offset: offset,
      nextOffset: null,
      changes: changes,
    );
  }

  @override
  void close() {}
}

/// In-memory transactional catalog for the pull action.
class _FakePullRepo implements TransactionalCatalogRepository {
  int applyCalls = 0;
  List<CatalogEntry> appliedUpserts = const [];
  List<String> appliedDeletes = const [];

  @override
  Future<void> applyDeltaAtomic({
    required List<CatalogEntry> upserts,
    required List<String> deletes,
  }) async {
    applyCalls++;
    appliedUpserts = List<CatalogEntry>.of(upserts);
    appliedDeletes = List<String>.of(deletes);
  }

  @override
  Future<void> init() async {}

  @override
  Future<CatalogEntry?> get(String barcode) async => null;

  @override
  Future<List<CatalogEntry>> all({String? search, int? limit, int? offset}) async => const [];

  @override
  Future<void> upsert(CatalogEntry entry) async {}

  @override
  Future<void> delete(String barcode) async {}

  @override
  Future<int> count({String? search}) async => 0;
}

/// In-memory catalog so the embedded BrowsePage loads a row on open with no
/// SQLite and no network.
class _FakeCatalogRepo implements CatalogRepository {
  final List<CatalogEntry> _rows = [
    CatalogEntry(
      barcode: '1234567890',
      name: 'Café Test',
      category: 'Drinks',
      createdAt: 0,
      updatedAt: 0,
    ),
  ];

  @override
  Future<void> init() async {}

  @override
  Future<CatalogEntry?> get(String barcode) async =>
      _rows.where((e) => e.barcode == barcode).firstOrNull;

  @override
  Future<List<CatalogEntry>> all({String? search, int? limit, int? offset}) async {
    final q = (search ?? '').trim().toLowerCase();
    final rows = q.isEmpty
        ? _rows
        : _rows.where((e) => e.name.toLowerCase().contains(q)).toList();
    final start = offset ?? 0;
    if (start >= rows.length) return <CatalogEntry>[];
    final rawEnd = limit == null ? rows.length : start + limit;
    final end = rawEnd > rows.length ? rows.length : rawEnd;
    return rows.sublist(start, end);
  }

  @override
  Future<void> upsert(CatalogEntry entry) async {}

  @override
  Future<void> delete(String barcode) async {}

  @override
  Future<int> count({String? search}) async => _rows.length;
}

Future<void> settle(WidgetTester t, [int n = 25]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late SigningTrust trust;
  late FakeSettingsService settings;

  setUp(() async {
    trust = await SigningTrust.create();
    settings = FakeSettingsService()
      ..signersEnvelope = trust.directory.envelope;
    settings.shops.add('hanouti');
  });

  testWidgets('AdminHome IA: catalog buttons, per-shop menu, role gating, '
      'settings actions', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final pullClient = _FakePullClient(
      [
        CatalogDiffChange(
          version: 2,
          barcode: 'A',
          op: 'upsert',
          row: CatalogEntry(
            barcode: 'A',
            name: 'Product A',
            category: 'grocery',
            createdAt: 1,
            updatedAt: 2,
          ),
        ),
        const CatalogDiffChange(version: 3, barcode: 'B', op: 'delete', row: null),
      ],
      3,
    );
    final pullRepo = _FakePullRepo();
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('fr'), Locale('ar')],
        path: 'assets/lang',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) => MultiProvider(
            providers: [
              Provider<SettingsService>.value(value: settings),
              ChangeNotifierProvider(
                create: (_) => CatalogProvider(repo: _FakeCatalogRepo()),
              ),
              Provider<SignersInfo>.value(
                value: SignersInfo(SignersDirectoryLoader.load(
                  settings: settings,
                  rootPublicKey: trust.rootPublic,
                )),
              ),
            ],
            child: MaterialApp(
              theme: AppPalette.theme(),
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              navigatorKey: navKey,
              home: AdminHome(
                rootPublicKey: trust.rootPublic,
                clientFactory: () async => pullClient,
                repository: pullRepo,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    // --- Catalog tab: the paged list is the tab; one global distribute action.
    expect(find.text('Café Test'), findsOneWidget);
    expect(find.text('Distribute catalog'), findsOneWidget);
    expect(find.text('Add product'), findsOneWidget);
    expect(find.text('Manage catalog'), findsNothing,
        reason: 'the separate management screen is gone');
    expect(find.text('Export listing'), findsNothing,
        reason: 'listing export moved to the per-shop menu');

    // --- Shops tab: per-shop menu with Shop info / Export listing / Delete.
    await tester.tap(find.text('Shops'));
    await settle(tester);
    expect(find.text('Distribute catalog'), findsNothing);
    expect(find.text('Add product'), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await settle(tester, 10);
    expect(find.text('Shop info'), findsOneWidget);
    expect(find.text('Export listing'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    navKey.currentState!.pop();
    await settle(tester, 8);

    // --- No signer: chip + non-blocking banner.
    expect(find.text('No signer'), findsOneWidget);
    expect(find.text('No signer key — import one to enable distribution'),
        findsOneWidget);

    // --- Import route returns with a founder/admin signer active.
    await tester.tap(find.text('Import'));
    await settle(tester);
    settings.activeSignerId = SigningTrust.founderAdminId;
    await settings.saveSignerKey(
        SigningTrust.founderAdminId, trust.seed(SigningTrust.founderAdminId));
    navKey.currentState!.pop();
    await settle(tester);

    expect(find.text('founder-admin · founder'), findsOneWidget);
    expect(find.text('No signer key — import one to enable distribution'),
        findsNothing);

    // --- Founder/admin: the Catalog rows are deletable and editable.
    await tester.tap(find.text('Catalog'));
    await settle(tester);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget,
        reason: 'founder/admin must see the delete affordance');
    await tester.tap(find.text('Café Test'));
    await settle(tester, 10);
    expect(find.byType(CaptureDialog), findsOneWidget,
        reason: 'founder/admin taps a row to edit');
    navKey.currentState!.pop();
    await settle(tester, 10);

    // --- Salesman: the same list is strictly read-only.
    settings.activeSignerId = SigningTrust.salesmanId;
    await settings.saveSignerKey(
        SigningTrust.salesmanId, trust.seed(SigningTrust.salesmanId));
    await tester.tap(find.text('Shops'));
    await settle(tester);
    await tester.tap(find.text('Catalog'));
    await settle(tester);

    expect(find.byIcon(Icons.delete_outline), findsNothing,
        reason: 'a salesman must not see delete');
    await tester.tap(find.text('Café Test'));
    await settle(tester, 10);
    expect(find.byType(CaptureDialog), findsNothing,
        reason: 'a salesman cannot edit the catalog');

    // --- Settings tab surfaces the three catalog actions.
    await tester.tap(find.text('Settings'));
    await settle(tester);
    expect(find.text('Update catalog'), findsOneWidget);
    expect(find.text('Publish changes'), findsOneWidget);
    expect(find.text('Sync settings'), findsOneWidget);
    expect(find.text('Open settings'), findsNothing,
        reason: 'the Settings tab IS the settings page now');
    expect(find.byType(SettingsScreen), findsOneWidget,
        reason: 'the settings body is embedded in the tab');

    // --- « Update catalog »: confirmation shows local -> latest + counts,
    // then one atomic apply advances the local generation.
    settings.catalogVersion = 1;
    await tester.tap(find.text('Update catalog'));
    await settle(tester, 10);
    expect(find.text('Update catalog?'), findsOneWidget);
    expect(find.textContaining('Local version 1 -> latest 3'), findsOneWidget);
    expect(find.textContaining('2 change(s): 1 update(s), 1 delete(s)'),
        findsOneWidget);
    expect(pullRepo.applyCalls, 0, reason: 'preview must not write');

    await tester.tap(find.widgetWithText(FilledButton, 'Update catalog'));
    await settle(tester, 20);
    expect(pullRepo.applyCalls, 1);
    expect(pullRepo.appliedUpserts.single.barcode, 'A');
    expect(pullRepo.appliedDeletes, ['B']);
    expect(settings.catalogVersion, 3);
  });
}
