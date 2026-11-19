import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/catalog_db.dart';
import 'data/settings_service.dart';
import 'data/signers_directory.dart';
import 'data/signing.dart';
import 'models/catalog_entry.dart';
import 'providers/catalog_provider.dart';
import 'data/sync_service.dart';
import 'screens/admin_home_screen.dart';
import 'theme.dart';

const _locales = [Locale('en'), Locale('fr'), Locale('ar')];

/// Root-verified directory, loaded once for the admin's "Signers" panel.
/// Production uses the baked root; tests inject their own [SignersDirectory].
class SignersInfo {
  final Future<SignersDirectory> directory;
  const SignersInfo(this.directory);
}

/// The admin flavor's non-blocking shell. No shop and no signer required.
///
/// Provides ONLY what the founder tools need — settings, catalog repository,
/// catalog provider (sync config loaded) and signers info. No [CartProvider],
/// no POS / checkout / inventory screens are constructed with an empty key.
class AdminHomeApp extends StatelessWidget {
  final SettingsService settings;

  const AdminHomeApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      supportedLocales: _locales,
      path: 'assets/lang',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('fr'),
      useOnlyLangCode: true,
      saveLocale: true,
      child: MultiProvider(
        providers: [
          Provider<SettingsService>.value(value: settings),
          Provider<CatalogRepository>.value(value: CatalogDb.instance),
          // Kept for the sync dialog / catalog provider.
          ChangeNotifierProvider(create: (_) => SyncService()),
          ChangeNotifierProvider(
            create: (_) => CatalogProvider()..loadSyncConfig(),
          ),
          Provider<SignersInfo>.value(
            value: SignersInfo(SignersDirectoryLoader.load(settings: settings)),
          ),
        ],
        child: const _AdminLocalizedApp(),
      ),
    );
  }
}

class _AdminLocalizedApp extends StatelessWidget {
  const _AdminLocalizedApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'myhanoutadmin',
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: AppPalette.theme(
        fontFamily: context.locale.languageCode == 'ar' ? 'Tajawal' : 'Inter',
      ),
      home: const AdminHome(),
      debugShowCheckedModeBanner: false,
    );
  }
}
