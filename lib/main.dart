import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/cart_provider.dart';
import 'screens/checkout_screen.dart';
import 'screens/inventory_screen.dart';

void main() => runApp(const ShopKeeperApp());

class ShopKeeperApp extends StatelessWidget {
  const ShopKeeperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CartProvider(),
      child: MaterialApp(
        title: 'ShopKeeper',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.teal,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: const HomePage(),
        debugShowCheckedModeBanner: false,
      ),
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
  final _pages = const [CheckoutScreen(), InventoryScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.point_of_sale), label: 'Checkout'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2), label: 'Inventory'),
        ],
      ),
    );
  }
}
