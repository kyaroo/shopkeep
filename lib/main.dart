import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'app_router.dart';
import 'providers/cart_provider.dart';
import 'providers/catalog_provider.dart';
import 'providers/sales_provider.dart';
import 'build_config.dart';
import 'data/config.dart';
import 'data/myhanout_file.dart';
import 'data/settings_service.dart';
import 'screens/admin_setup_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/sales_history_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shop_entry_screen.dart';
import 'theme.dart';
import 'app_state.dart';

const supportedLocales = [
  Locale('en'),
  Locale('fr'),
  Locale('ar'),
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await Config.init();

  // Bootstrap the settings seam once. `Config` is still the static store (it
  // must be readable before any widget exists); everything above this point
  // receives [settings] by injection instead.
  final settings = const ConfigSettingsService();

  // Source of truth for the active shop + business name. Previously these two
  // `ValueNotifier`s lived at package scope (`app_state.dart`), which made them a
  // hidden global dependency of every screen and provider. They are now owned
  // by [AppState] and exposed via `MultiProvider` at the root.
  final appState = AppState();

  if (!kIsAdmin) {
    final active = await settings.getCurrentShopKey();
    if (active.isNotEmpty && active != 'default') {
      final businessName = await settings.getBusinessName();
      appState.shopKey = active;
      appState.businessName = businessName;
    } else {
      appState.shopKey = '';
      appState.businessName = 'Maison du Marché';
    }
    runApp(AppRouter(appState: appState, settings: settings));
    return;
  }

  final shopList = await settings.getShopList();
  if (shopList.isEmpty) {
    runApp(AdminSetupApp(settings: settings));
    return;
  }
  // If a shop was left active, open it.
  final active = await settings.getCurrentShopKey();
  if (active.isNotEmpty) {
    final businessName = await settings.getBusinessName();
    appState.shopKey = active;
    appState.businessName = businessName;
    runApp(AppRouter(appState: appState, settings: settings));
    return;
  }
  // Otherwise → first-run onboarding.
  runApp(AdminSetupApp(settings: settings));
}
class MyhanoutApp extends StatelessWidget {
    final String shopKey;
    final String businessName;
    final SettingsService settings;
  const MyhanoutApp({super.key, required this.shopKey, this.businessName = 'Maison du Marché', required this.settings});

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
          Provider<SettingsService>.value(value: settings),
          ChangeNotifierProvider(
            create: (_) => CartProvider(shopKey, businessName: businessName),
          ),
          ChangeNotifierProvider(
            // The shopkeeper flavor never builds a sync client: no server
            // URL/token, no catalog sync surface.
            create: (_) => kIsAdmin
                ? (CatalogProvider()..loadSyncConfig())
                : CatalogProvider(),
          ),
        ],
        child: const LocalizedApp(),
      ),
    );
  }
}

/// Admin / first-run entry: full app with admin tools (named "myhanoutadmin").
class ShopEntryApp extends StatelessWidget {
  final SettingsService settings;
  const ShopEntryApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      supportedLocales: supportedLocales,
      path: 'assets/lang',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('fr'),
      useOnlyLangCode: true,
      saveLocale: true,
      child: Provider<SettingsService>.value(
        value: settings,
        child: const _ShopEntryLocalizedApp(),
      ),
    );
  }
}

class _ShopEntryLocalizedApp extends StatelessWidget {
  const _ShopEntryLocalizedApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'myhanout',
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: AppPalette.theme(
        fontFamily: context.locale.languageCode == 'ar' ? 'Tajawal' : 'Inter',
      ),
      home: const ShopEntryScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Admin setup screen: the full app (all tools) in one flavor.
class AdminSetupApp extends StatelessWidget {
  final SettingsService settings;
  const AdminSetupApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      supportedLocales: supportedLocales,
      path: 'assets/lang',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('fr'),
      useOnlyLangCode: true,
      saveLocale: true,
      child: Provider<SettingsService>.value(
        value: settings,
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

class LocalizedApp extends StatelessWidget {
  const LocalizedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'myhanout',
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: AppPalette.theme(
        fontFamily: context.locale.languageCode == 'ar' ? 'Tajawal' : 'Inter',
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyPendingFile());
  }

  /// Applies a `.myhanout` catalog delta the app was opened with (WhatsApp,
  /// Downloads, a file manager). Silent when there is nothing to apply.
  Future<void> _applyPendingFile() async {
    final result =
        await MyhanoutFile.handleLaunchIntent(settings: context.read<SettingsService>());
    if (result == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result), duration: const Duration(seconds: 4)),
    );
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('language'.tr(),
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ...supportedLocales.map((l) {
              final label = {
                'en': 'English',
                'fr': 'Français',
                'ar': 'العربية',
              }[l.languageCode]!;
              final isCurrent = context.locale.languageCode == l.languageCode;
              return ListTile(
                title: Text(label),
                trailing: isCurrent ? const Icon(Icons.check) : null,
                onTap: () {
                  context.setLocale(l);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(shopKey: context.watch<AppState>().shopKey)),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('appName'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            tooltip: 'language'.tr(),
            onPressed: _showLanguagePicker,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'settings'.tr(),
            onPressed: _showSettings,
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          const CheckoutBody(),
          const InventoryBody(),
          Consumer<AppState>(
            builder: (_context, appState, __) => ChangeNotifierProvider(
              create: (_) => SalesProvider(appState.shopKey),
              child: const SalesHistoryScreen(),
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _tab == 0
            ? FloatingActionButton(
                onPressed: () => scanToAdd(context),
                tooltip: 'scanToAdd'.tr(),
                child: const Icon(Icons.qr_code_scanner),
              )
            : _tab == 1
                ? FloatingActionButton(
                    onPressed: () => showProductForm(context),
                    tooltip: 'addProduct'.tr(),
                    child: const Icon(Icons.add),
                  )
                : null,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
              icon: const Icon(Icons.point_of_sale), label: 'checkout'.tr()),
          NavigationDestination(
              icon: const Icon(Icons.inventory_2), label: 'inventory'.tr()),
          NavigationDestination(
              icon: const Icon(Icons.receipt_long), label: 'salesHistory'.tr()),
        ],
      ),
    );
  }
}
