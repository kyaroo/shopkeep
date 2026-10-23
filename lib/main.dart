import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'providers/cart_provider.dart';
import 'data/config.dart';
import 'screens/admin_setup_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/sales_history_screen.dart';
import 'screens/settings_screen.dart';
import 'theme.dart';

const supportedLocales = [
  Locale('en'),
  Locale('fr'),
  Locale('ar'),
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await Config.init();

  // Resolve the starting screen.
  // 1. No shops yet → admin setup (add first shop).
  // 2. Else current shop exists → open it.
  // 3. Else → first-run onboarding.
  final shopList = await Config.getShopList();
  if (shopList.isEmpty) {
    runApp(AdminSetupApp());
    return;
  }
  // If a shop was left active, open it.
  final active = await Config.getCurrentShopKey();
  if (active.isNotEmpty) {
    final businessName = await Config.getBusinessName();
    runApp(MyhanoutApp(shopKey: active, businessName: businessName));
    return;
  }
  // Otherwise → first-run onboarding.
  runApp(AdminSetupApp());
}

class MyhanoutApp extends StatelessWidget {
  final String shopKey;
  final String businessName;
  const MyhanoutApp({super.key, required this.shopKey, this.businessName = 'Maison du Marché'});

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      supportedLocales: supportedLocales,
      path: 'assets/lang',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('fr'),
      useOnlyLangCode: true,
      saveLocale: true,
      child: ChangeNotifierProvider(
        create: (_) => CartProvider(shopKey, businessName: businessName),
        child: const LocalizedApp(),
      ),
    );
  }
}

/// Admin entry: full app with admin tools (named "myhanoutadmin").
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
      child: const _AdminLocalizedApp(),
    );
  }
}

class _AdminLocalizedApp extends StatelessWidget {
  const _AdminLocalizedApp({super.key});

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
      MaterialPageRoute(builder: (_) => SettingsScreen(shopKey: 'default')),
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
    final businessName = cart.businessName;

    return Scaffold(
      appBar: AppBar(
        title: Text('myhanout'),
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
      body: Column(
        children: [
          // Shopkeeper name above the app.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Text(
              businessName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Flexible(
            child: _tab == 0
                ? const CheckoutBody()
                : _tab == 1
                    ? const InventoryBody()
                    : const SalesHistoryScreen(),
          ),
        ],
      ),
      floatingActionButton: _tab == 0
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
