/// S3 — the Browse catalog renders a LOCAL catalog photo (Image.memory),
/// not just network image_url thumbnails.
///
/// Run: flutter test test/poc/browse_photo_poc_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:myhanout/models/catalog_prefill.dart';
import 'package:myhanout/providers/catalog_provider.dart';
import 'package:myhanout/screens/browse_page.dart';

class MockCatalogProvider extends Mock implements CatalogProvider {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(0);
  });

  testWidgets('Browse catalog renders a local photo as a MemoryImage',
      (tester) async {
    final provider = MockCatalogProvider();
    final photo = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    when(() => provider.browseLocal(
          q: any(named: 'q'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        )).thenAnswer(
      (_) async => CatalogBrowseResult(
        total: 1,
        limit: 50,
        offset: 0,
        products: [
          CatalogPrefill(
            barcode: '6111035001673',
            name: 'Aïn Atlas 50cl',
            category: 'beverage',
            origin: 'local',
            photo: photo,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<CatalogProvider>.value(
          value: provider,
          child: BrowsePage(localOnly: true, onSelect: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final finder = find.byType(Image);
    expect(finder, findsOneWidget);
    final img = tester.widget<Image>(finder).image;
    expect(img, isA<MemoryImage>());
    expect((img as MemoryImage).bytes, equals(photo));
    // ignore: avoid_print
    print('S3 OK: BrowsePage paints the local catalog photo (MemoryImage)');
  });
}
