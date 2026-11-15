import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'data/catalog_db.dart';
import 'data/settings_service.dart';
import 'models/catalog_entry.dart';
import 'screens/admin_setup_screen.dart';
import 'theme.dart';

const supportedLocales = [
  Locale('en'),
  Locale('fr'),
  Locale('ar'),
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  runApp(const AdminSetupApp());
}

class AdminSetupApp extends StatelessWidget {
  const AdminSetupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      supportedLocales: supportedLocales,
      path: 'assets/lang',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('fr'),
      useOnlyLangCode: true,
      saveLocale: true,
      child: MultiProvider(
        providers: [
          Provider<SettingsService>.value(value: const ConfigSettingsService()),
          Provider<CatalogRepository>.value(value: CatalogDb.instance),
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
      home: const AdminSetupScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
