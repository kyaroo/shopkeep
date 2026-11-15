/// Unit tests for [CatalogProvider] — the catalog state holder.
///
/// The external boundary [CatalogRepository] is faked with [MockCatalogRepository]
/// (mocktail). No SQLite, no network — the provider's own logic (loading, saving,
/// deleting, counting) is tested end-to-end.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myhanout/providers/catalog_provider.dart';
import 'package:myhanout/models/catalog_entry.dart';

import '../helpers/mock_providers.dart';

void main() {
  setUpAll(() {
    // Register a fallback so `any<CatalogEntry>()` works in mocktail.
    registerFallbackValue(CatalogEntry(barcode: 'dummy', name: 'dummy', createdAt: 0, updatedAt: 0));
  });

  group('CatalogProvider', () {
    late MockCatalogRepository repo;
    late CatalogProvider provider;

    setUp(() {
      repo = MockCatalogRepository();
      provider = CatalogProvider(repo: repo);
    });

    test('load: fetches entries via repository and updates state', () async {
      final entries = <CatalogEntry>[
        CatalogEntry(barcode: 'A', name: 'A', createdAt: 1, updatedAt: 1),
        CatalogEntry(barcode: 'B', name: 'B', createdAt: 1, updatedAt: 1),
      ];

      when(() => repo.all(search: '')).thenAnswer((_) async => entries);

      await provider.load();

      expect(provider.entries, equals(entries));
      expect(provider.loading, isFalse);
    });

    test('load with search: passes search to repository', () async {
      when(() => repo.all(search: 'query')).thenAnswer((_) async => const []);

      await provider.load(search: 'query');

      verify(() => repo.all(search: 'query')).called(1);
    });

    test('get: delegates to repository', () async {
      final entry = CatalogEntry(barcode: 'A', name: 'A', createdAt: 1, updatedAt: 1);

      when(() => repo.get('A')).thenAnswer((_) async => entry);

      final result = await provider.get('A');

      expect(result, equals(entry));
    });

    test('save: inserts/updates and reloads entries', () async {
      when(() => repo.get('A')).thenAnswer((_) async => null);
      when(() => repo.all(search: '')).thenAnswer((_) async => const []);
      when(() => repo.upsert(any())).thenAnswer((_) async {});

      await provider.save(barcode: 'A', name: 'A');

      verify(() => repo.upsert(any())).called(1);
      expect(provider.entries, isEmpty);
    });

    test('delete: removes entry and reloads', () async {
      when(() => repo.all(search: '')).thenAnswer((_) async => const []);
      when(() => repo.delete('A')).thenAnswer((_) async {});

      await provider.delete('A');

      verify(() => repo.delete('A')).called(1);
      verify(() => repo.all(search: '')).called(1);
    });

    test('count: delegates to repository', () async {
      when(() => repo.count()).thenAnswer((_) async => 42);

      final count = await provider.count();

      expect(count, 42);
    });
  });
}
