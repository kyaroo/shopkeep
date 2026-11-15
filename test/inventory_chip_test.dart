// G2 — the inventory 'Ajoutés localement' chip + the local recovery row
// affordance (widget).
//
// Uses an in-memory [CartProvider] fake rather than sqflite: real database
// I/O never completes inside testWidgets' fake-async zone (the project's
// DB-backed tests are plain `test()` bodies for the same reason). The filter
// under test is the screen's, not the database's.
//
// Run: flutter test test/inventory_chip_test.dart

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/models/product.dart';
import 'package:myhanout/providers/cart_provider.dart';
import 'package:myhanout/screens/inventory_screen.dart';
import 'package:myhanout/theme.dart';
import 'package:provider/provider.dart';

/// Minimal [CartProvider] stand-in: the rows are in memory, mutations notify,
/// and search mirrors the real provider's name/barcode narrowing.
class FakeCartProvider extends ChangeNotifier implements CartProvider {
  FakeCartProvider(List<Product> products)
      : _all = List<Product>.of(products),
        _products = List<Product>.of(products);

  final List<Product> _all;
  List<Product> _products;

  @override
  final String shopKey = 'fake-shop';

  @override
  List<Product> get products => _products;

  @override
  bool get productsLoading => false;

  @override
  bool get loadingMoreProducts => false;

  @override
  int get totalProducts => _products.length;

  @override
  bool get hasMoreProducts => false;

  @override
  String get businessName => 'Test Shop';

  @override
  Future<void> loadProducts({String? search, bool all = false}) async {
    final q = (search ?? '').trim().toLowerCase();
    _products = q.isEmpty
        ? List<Product>.of(_all)
        : _all
            .where((p) =>
                p.name.toLowerCase().contains(q) ||
                (p.barcode?.contains(q) ?? false))
            .toList();
    notifyListeners();
  }

  @override
  Future<void> loadMoreProducts() async {}

  @override
  Future<void> deleteProduct(int id) async {
    _all.removeWhere((p) => p.id == id);
    _products.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> settle(WidgetTester tester, [int steps = 8]) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // The low-stock chip label is also the StockBadge label on a low-stock row,
  // so chip taps must be scoped to the chip itself.
  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
      of: find.byType(FilterChip),
      matching: find.text(label),
    ));
  }

  testWidgets('should filter to local additions and recover one', (tester) async {
    final cart = FakeCartProvider([
      Product(id: 1, name: 'Catalogue', priceCents: 1000, stockQty: 10),
      Product(id: 2, name: 'Local bas', priceCents: 500, stockQty: 1, source: 'local'),
      Product(id: 3, name: 'Local plein', priceCents: 700, stockQty: 9, source: 'local'),
    ]);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('fr'), Locale('ar')],
        path: 'assets/lang',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('fr'),
        useOnlyLangCode: true,
        child: ChangeNotifierProvider<CartProvider>.value(
          value: cart,
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              theme: AppPalette.theme(),
              home: const Scaffold(body: InventoryBody()),
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    // --- All rows by default; the chip and the recovery affordance exist ---
    expect(find.text('Catalogue'), findsOneWidget);
    expect(find.text('Local bas'), findsOneWidget);
    expect(find.text('Local plein'), findsOneWidget);
    expect(find.text('Ajoutés localement'), findsOneWidget);
    // Only the two local rows carry the undo affordance.
    expect(find.byTooltip("Annuler l'ajout local"), findsNWidgets(2));
    expect(find.byIcon(Icons.undo), findsNWidgets(2));

    // --- The local chip keeps only local additions ---
    await tapChip(tester, 'Ajoutés localement');
    await settle(tester);
    expect(find.text('Catalogue'), findsNothing);
    expect(find.text('Local bas'), findsOneWidget);
    expect(find.text('Local plein'), findsOneWidget);

    // --- Search still narrows on top of the chip ---
    await tester.enterText(find.byType(TextField), 'plein');
    await settle(tester);
    expect(find.text('Local bas'), findsNothing);
    expect(find.text('Local plein'), findsOneWidget);

    // --- Low stock still works after switching views ---
    await tester.enterText(find.byType(TextField), '');
    await settle(tester);
    await tapChip(tester, 'Stock bas');
    await settle(tester);
    expect(find.text('Local bas'), findsOneWidget);
    expect(find.text('Local plein'), findsNothing);
    expect(find.text('Catalogue'), findsNothing);

    // --- Back to all, then recover a local addition via its row action ---
    await tapChip(tester, 'Tout');
    await settle(tester);
    expect(find.text('Local bas'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.undo).first);
    await settle(tester);
    expect(find.text("Annuler l'ajout local"), findsOneWidget);

    await tester.tap(find.text('Supprimer'));
    await settle(tester);
    expect(find.text('Local bas'), findsNothing);
    expect(find.text('Local plein'), findsOneWidget);
    expect(find.text('Ajout local annulé'), findsOneWidget);
  });
}
