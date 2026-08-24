import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper/main.dart';

void main() {
  // sqflite needs an FFI factory on the Linux test host (real app uses native SQLite).
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('App boots, shows both tabs, opens Checkout by default',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ShopKeeperApp());
    // CartProvider initial loadProducts() is async; pump enough frames.
    // (The search TextField cursor animates forever, so avoid pumpAndSettle.)
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Checkout'), findsWidgets);
    expect(find.text('Inventory'), findsWidgets);
    // Checkout is the default tab -> empty-cart hint visible.
    expect(find.textContaining('Cart is empty'), findsOneWidget);
  });

  testWidgets('Tapping Inventory tab shows the add-product FAB',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ShopKeeperApp());
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    // The FAB only exists on the Inventory screen.
    expect(find.byTooltip('Add product'), findsNothing);

    await tester.tap(find.text('Inventory').first);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byTooltip('Add product'), findsOneWidget);
  });
}
