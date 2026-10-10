import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:shopkeeper/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> settle(WidgetTester tester, [int steps = 10]) async {
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  // All three widget flows run against ONE widget tree in sequence. A single
  // testWidgets avoids the EasyLocalization in-memory singleton leaking locale
  // state across separate testWidgets invocations (icon vanishes / assets
  // unload in later tests). Each phase verifies its own behavior.
  testWidgets('Boot, switch to Arabic (RTL), then navigate to Inventory',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ShopKeeperApp());
    await settle(tester);

    // --- Phase 1: boots in English by default ---
    expect(find.text('Checkout'), findsWidgets);
    expect(find.text('Inventory'), findsWidgets);
    expect(find.textContaining('Cart is empty'), findsOneWidget);

    // --- Phase 2: switch to Arabic, confirm RTL + translation ---
    // Open the language picker via the language icon (tooltip is localized).
    await tester.tap(find.byIcon(Icons.language));
    await settle(tester);
    await tester.tap(find.text('العربية'));
    await settle(tester);
    // Translated nav label visible (Checkout in Arabic).
    expect(find.text('الدفع'), findsWidgets);
    // Directionality is RTL for Arabic locale.
    final dir = tester.widget<Directionality>(
        find.byType(Directionality).first);
    expect(dir.textDirection.toString(), contains('rtl'));

    // --- Phase 3: switch back to English, navigate to Inventory ---
    await tester.tap(find.byIcon(Icons.language));
    await settle(tester);
    await tester.tap(find.text('English'));
    await settle(tester);
    // English labels restored.
    expect(find.text('Inventory'), findsWidgets);

    // On the Checkout tab the add-product FAB is not present.
    expect(find.byTooltip('Add product'), findsNothing);
    // Tap the Inventory navigation destination (identified by its label text).
    final dest = find.ancestor(
      of: find.text('Inventory').first,
      matching: find.byType(NavigationDestination),
    );
    await tester.tap(dest);
    await settle(tester);
    // Add-product FAB now visible on the Inventory tab.
    expect(find.byTooltip('Add product'), findsOneWidget);
  });
}
