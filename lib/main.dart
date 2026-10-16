import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'providers/cart_provider.dart';
import 'screens/checkout_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/sales_history_screen.dart';
import 'theme.dart';

const supportedLocales = [
  Locale('en'),
  Locale('fr'),
  Locale('ar'),
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  runApp(const ShopKeeperApp());
}

class ShopKeeperApp extends StatelessWidget {
  const ShopKeeperApp({super.key});

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
        create: (_) => CartProvider(),
        child: const LocalizedApp(),
      ),
    );
  }
}

class LocalizedApp extends StatelessWidget {
  const LocalizedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShopKeeper',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('appName'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.language),
            tooltip: 'language'.tr(),
            onPressed: _showLanguagePicker,
          ),
        ],
      ),
      body: _tab == 0
          ? const CheckoutBody()
          : _tab == 1
              ? const InventoryBody()
              : const SalesHistoryScreen(),
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
