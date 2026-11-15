/// POC — CatalogDeltaBuilder: generate a delta and verify it is valid JSON.
///
/// Run: flutter test test/services/catalog_delta_builder_test.dart
library catalog_delta_builder_test;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/services/catalog_delta_service.dart';

void main() {
  test('builds a signed delta with base/target versions', () {
    final delta = CatalogDeltaBuilder.build(
      baseVersion: 1000,
      targetVersion: 1001,
      generatedAt: 1001,
      entries: [
        CatalogEntry(
          barcode: '0011210006508',
          name: 'Tabasco Habaneros hot',
          nameEn: 'Tabasco Habanero Sauce',
          category: 'grocery',
          photo: null,
          createdAt: 1000,
          updatedAt: 1001,
        ),
      ],
      deletes: [],
    );

    // Verify it is valid JSON
    expect(() => jsonDecode(delta), returnsNormally);

    // Verify the structure
    final map = jsonDecode(delta) as Map<String, dynamic>;
    expect(map['format'], 'myhanout-catalog-delta');
    expect(map['base_version'], 1000);
    expect(map['target_version'], 1001);
    expect(map['generated_at'], 1001);
    expect(map['upserts'], isA<List>());
    expect(map['deletes'], isA<List>());
    expect(map['signature'], isA<String>());
  });

  test('applies updatedAt to upserts', () {
    final entries = [
      CatalogEntry(
        barcode: '0011210006508',
        name: 'Tabasco',
        category: 'grocery',
        photo: null,
        createdAt: 1000,
        updatedAt: 1000,
      ),
    ];
    final delta = CatalogDeltaBuilder.build(
      baseVersion: 1000,
      targetVersion: 1001,
      generatedAt: 1001,
      entries: entries,
      deletes: [],
    );
    final map = jsonDecode(delta) as Map<String, dynamic>;
    final upsert = map['upserts'] as List;
    expect(upsert.length, 1);
    // The upserts should reflect the target version as updated_at
    expect(upsert.first['updated_at'], 1001);
  });
}
