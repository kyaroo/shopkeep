/// Widget test for the AdminHome shell: three tabs (Shops / Catalog /
/// Settings), the Catalog action row, the per-shop menu, role gating and the
/// Settings tab.
///
/// ONE EasyLocalization/MaterialApp tree for the whole isolate: a second one
/// leaves the translation load stuck in the fake-async zone, so every phase
/// runs through this single injected tree.
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/admin_home_app.dart';
import 'package:myhanout/app_state.dart';
import 'package:myhanout/data/catalog_delta.dart';
import 'package:myhanout/data/catalog_sync_client.dart';
import 'package:myhanout/data/settings_service.dart';
import 'package:myhanout/data/signers_directory.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/providers/catalog_provider.dart';
import 'package:myhanout/screens/admin_home_screen.dart';
import 'package:myhanout/screens/capture_dialog.dart';
import 'package:myhanout/screens/settings_screen.dart';
import 'package:myhanout/screens/sync_settings_dialog.dart';
import 'package:myhanout/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_settings.dart';
import '../helpers/signing_trust.dart';

/// Fake sync client for the Catalog actions (no network).
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
  Future<int> catalogVersionStatus() async => 200;

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
    SharedPreferences.setMockInitialValues({});
    trust = await SigningTrust.create();
    settings = FakeSettingsService()
      ..signersEnvelope = trust.directory.envelope;
    settings.shops.add('hanouti');
  });

  testWidgets('AdminHome IA: three tabs, catalog actions, per-shop menu, '
      'role gating, settings actions', (tester) async {
    // A phone-sized surface: the sync card + list must fit without overflow.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navKey = GlobalKey<NavigatorState>();
    final appState = AppState();
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
              // Production provides this above AdminHomeApp (AppRouter); the
              // per-shop « Open shop » action reads it.
              ChangeNotifierProvider<AppState>.value(value: appState),
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

    // --- Landing tab is Shops; the Security tab is gone.
    expect(find.text('Shops'), findsOneWidget);
    expect(find.text('Catalog'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Security'), findsNothing,
        reason: 'the Security tab was merged into Settings');
    expect(find.text('Add shop'), findsOneWidget,
        reason: 'the Shops tab is the single shop manager');

    // --- Catalog tab: « Sync parameters » header + pill, then ONE row of
    // three icon actions (no ListTiles) and the paged list.
    await tester.tap(find.text('Catalog'));
    await settle(tester);
    expect(find.text('Sync parameters'), findsOneWidget);
    expect(find.byTooltip('Update catalog'), findsOneWidget);
    expect(find.byTooltip('Publish changes'), findsOneWidget);
    expect(find.byTooltip('Sync settings'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_download), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsOneWidget);
    expect(find.text('Token missing'), findsOneWidget,
        reason: 'no token in prefs → the pill reports it');
    expect(find.text('Café Test'), findsOneWidget);
    expect(find.text('Catalog Management'), findsOneWidget);
    expect(find.byTooltip('Distribute catalog'), findsOneWidget);
    expect(find.byTooltip('Add product'), findsOneWidget);
    // NOTE: the catalog-export button is behind `if (kIsAdmin)`, a compile-time
    // const that is FALSE under `flutter test`; `tool/verify_catalog_export_gate.sh`
    // pins it at source instead of here.
    expect(find.text('Manage catalog'), findsNothing,
        reason: 'the separate management screen is gone');
    expect(find.text('Export listing'), findsNothing,
        reason: 'listing export moved to the per-shop menu');

    // « Sync settings » opens the config dialog (and comes back).
    await tester.tap(find.byTooltip('Sync settings'));
    await settle(tester, 10);
    expect(find.byType(SyncSettingsDialog), findsOneWidget);
    navKey.currentState!.pop();
    await settle(tester, 10);
    expect(find.text('Token missing'), findsOneWidget);

    // --- Shops tab: per-shop menu with Shop info / Export listing /
    // Export history / Delete (and no "Use this shop").
    await tester.tap(find.text('Shops'));
    await settle(tester);
    expect(find.byTooltip('Distribute catalog'), findsNothing);
    expect(find.byTooltip('Add product'), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await settle(tester, 10);
    expect(find.text('Open shop'), findsOneWidget);
    expect(find.text('Shop info'), findsOneWidget);
    expect(find.text('Export listing'), findsOneWidget);
    expect(find.text('Export history'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Use this shop'), findsNothing,
        reason: 'it popped the root route and blacked the screen');

    // « Open shop » records the shop as current and flips the session-only POS
    // mode; the router (not under test here) swaps the shell for the POS.
    await tester.tap(find.text('Open shop'));
    await settle(tester, 10);
    expect(appState.shopKey, 'hanouti');
    expect(appState.posMode, isTrue,
        reason: 'posMode is the opt-in detour; it is not persisted');

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

    // --- Settings tab is the settings body only; the sync actions live on
    // the Catalog tab.
    await tester.tap(find.text('Settings'));
    await settle(tester);
    expect(find.byTooltip('Update catalog'), findsNothing);
    expect(find.byTooltip('Publish changes'), findsNothing);
    expect(find.byTooltip('Sync settings'), findsNothing);
    expect(find.byTooltip('Export catalog'), findsNothing,
        reason: 'the catalog export moved to the Catalog tab');
    expect(find.text('Export catalog'), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget,
        reason: 'the settings body is embedded in the tab');

    // --- « Update catalog » (Catalog tab): confirmation shows local -> latest
    // + counts, then one atomic apply advances the local generation.
    await tester.tap(find.text('Catalog'));
    await settle(tester);
    settings.catalogVersion = 1;
    await tester.tap(find.byTooltip('Update catalog'));
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
