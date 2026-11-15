import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:provider/provider.dart';

import 'package:myhanout/screens/catalog_home_page.dart';
import 'package:myhanout/providers/catalog_provider.dart';
import 'package:myhanout/data/sync_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('Catalog home screen pumps without crashing', (tester) async {
    // CatalogHomePage reads SyncService (sync now / sync settings) as well as
    // CatalogProvider — both must be provided.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SyncService()),
          ChangeNotifierProvider(create: (_) => CatalogProvider()..init()),
        ],
        child: const MaterialApp(home: CatalogHomePage()),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(CatalogHomePage), findsOneWidget);
  });
}
