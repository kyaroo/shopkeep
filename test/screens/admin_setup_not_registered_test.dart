/// Phase 4 — the admin shop-creation path surfaces a clear
/// "Not registered on server" state when sync is unconfigured or the
/// registration call fails. The local shop stays usable either way.
///
/// ONE EasyLocalization/MaterialApp tree for the whole isolate: a second one
/// leaves the translation load stuck in the fake-async zone, so each scenario
/// pushes a fresh AdminSetupScreen route through the same navigator.
///
/// Run: flutter test test/screens/admin_setup_not_registered_test.dart
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/data/catalog_sync_client.dart';
import 'package:myhanout/data/settings_service.dart';
import 'package:myhanout/screens/admin_setup_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_settings.dart';

class _OkClient extends CatalogSyncClient {
  _OkClient() : super(baseUrl: '', token: '', deviceId: 'test');

  @override
  Future<void> registerShop(String shopKey, String businessName) async {}

  @override
  void close() {}
}

class _FailingClient extends CatalogSyncClient {
  _FailingClient() : super(baseUrl: '', token: '', deviceId: 'test');

  @override
  Future<void> registerShop(String shopKey, String businessName) async {
    throw SyncException('server unreachable');
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
  late FakeSettingsService settings;

  setUp(() {
    settings = FakeSettingsService();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shop creation surfaces the registration state', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
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
              navigatorKey: navKey,
              home: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    Future<void> runScenario(
      String name,
      CatalogSyncClientFactory? factory,
      Map<String, Object> prefs,
    ) async {
      SharedPreferences.setMockInitialValues(prefs);
      settings.shops.clear();
      navKey.currentState!.push(MaterialPageRoute(
        builder: (_) => AdminSetupScreen(clientFactory: factory),
      ));
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, name);
      await settle(tester, 5);
      await tester.tap(find.text('Create shop'));
      await settle(tester, 15);
      // Close the provisioning QR dialog to reveal the state card.
      if (find.text('Close').evaluate().isNotEmpty) {
        await tester.tap(find.text('Close'));
        await settle(tester, 10);
      }
    }

    // 1. Unconfigured sync.
    await runScenario('Hanouti', null, const {});
    expect(settings.shops, contains('hanouti'),
        reason: 'the local shop must still be created');
    expect(find.text('Not registered on server'), findsOneWidget);
    expect(find.textContaining('was created — not registered'), findsOneWidget);
    expect(find.text('Registered on server'), findsNothing);
    navKey.currentState!.pop();
    await settle(tester, 8);

    // 2. Configured sync, registration call fails.
    await runScenario('Hanouti', () async => _FailingClient(), const {
      'sync_url': 'https://catalog.example.test',
      'sync_token': 'token-123',
    });
    expect(settings.shops, contains('hanouti'));
    expect(find.text('Not registered on server'), findsOneWidget);
    navKey.currentState!.pop();
    await settle(tester, 8);

    // 3. Configured sync, registration succeeds.
    await runScenario('Hanouti', () async => _OkClient(), const {
      'sync_url': 'https://catalog.example.test',
      'sync_token': 'token-123',
    });
    expect(find.text('Registered on server'), findsOneWidget);
    expect(find.text('Not registered on server'), findsNothing);
  });
}
