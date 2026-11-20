/// The Sync-parameters pill must distinguish the TOKEN problem from the
/// NETWORK problem. It probes the AUTHENTICATED `GET /v1/catalog/version`, so
/// the fake client decides the status code and the mock prefs decide whether a
/// URL / token exist.
///
/// ONE EasyLocalization/MaterialApp tree for the whole isolate (the existing
/// admin_home_test documents why a second one wedges the translation load), so
/// every state is reached from the same tree: the fake client's status and the
/// mock prefs are mutated, then the pill is re-probed by round-tripping the
/// « Sync settings » dialog (which bumps the shell's refresh counter).
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/admin_home_app.dart';
import 'package:myhanout/data/catalog_sync_client.dart';
import 'package:myhanout/data/settings_service.dart';
import 'package:myhanout/data/signers_directory.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/providers/catalog_provider.dart';
import 'package:myhanout/screens/admin_home_screen.dart';
import 'package:myhanout/screens/sync_settings_dialog.dart';
import 'package:myhanout/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_settings.dart';
import '../helpers/signing_trust.dart';

class _ProbeClient extends CatalogSyncClient {
  /// Status the authenticated probe answers; null = throw (network error).
  int? status;

  int probeCalls = 0;

  _ProbeClient({this.status}) : super(baseUrl: '', token: '', deviceId: 'test');

  @override
  Future<int> catalogVersionStatus() async {
    probeCalls++;
    final s = status;
    if (s == null) throw Exception('network unreachable');
    return s;
  }

  @override
  void close() {}
}

class _NoCatalogRepo implements CatalogRepository {
  @override
  Future<void> init() async {}

  @override
  Future<CatalogEntry?> get(String barcode) async => null;

  @override
  Future<List<CatalogEntry>> all({String? search, int? limit, int? offset}) async =>
      const [];

  @override
  Future<void> upsert(CatalogEntry entry) async {}

  @override
  Future<void> delete(String barcode) async {}

  @override
  Future<int> count({String? search}) async => 0;
}

Future<void> settle(WidgetTester t, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FakeSettingsService settings;
  late SigningTrust trust;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    trust = await SigningTrust.create();
    settings = FakeSettingsService()..signersEnvelope = trust.directory.envelope;
  });

  testWidgets('pill states: unconfigured / missing / ok / rejected / down',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final client = _ProbeClient(status: 200);
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
                create: (_) => CatalogProvider(repo: _NoCatalogRepo()),
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
                clientFactory: () async => client,
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Catalog'));
    await settle(tester);

    // Re-probe by round-tripping the Sync settings dialog (bumps refresh).
    Future<void> reprobe() async {
      await tester.tap(find.byTooltip('Sync settings'));
      await settle(tester, 10);
      expect(find.byType(SyncSettingsDialog), findsOneWidget);
      navKey.currentState!.pop();
      await settle(tester, 10);
    }

    // 1. No token in prefs → the token is the problem, no request is made.
    expect(find.text('Token missing'), findsOneWidget);
    expect(client.probeCalls, 0);

    // 2. URL explicitly empty → not configured at all.
    SharedPreferences.setMockInitialValues(
        const {'sync_url': '', 'sync_token': 'token-123'});
    await reprobe();
    expect(find.text('Not configured'), findsOneWidget);
    expect(client.probeCalls, 0);

    // 3. Configured + HTTP 200 → token accepted and server up.
    SharedPreferences.setMockInitialValues(const {
      'sync_url': 'https://catalog.example.test',
      'sync_token': 'token-123',
    });
    await reprobe();
    expect(find.text('Token · Server OK'), findsOneWidget);
    expect(client.probeCalls, 1);

    // 4. 401 / 403 → the token itself is rejected (a different fix than "down").
    client.status = 401;
    await reprobe();
    expect(find.text('Token rejected'), findsOneWidget);
    client.status = 403;
    await reprobe();
    expect(find.text('Token rejected'), findsOneWidget);

    // 5. Any other status → server unreachable.
    client.status = 500;
    await reprobe();
    expect(find.text('Server unreachable'), findsOneWidget);

    // 6. Network error → same, and never stuck on "Checking…".
    client.status = null;
    await reprobe();
    expect(find.text('Server unreachable'), findsOneWidget);
    expect(find.text('Checking…'), findsNothing);
  });
}
