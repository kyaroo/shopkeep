import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/catalog_db.dart';
import '../data/db.dart';
import '../data/listing_bundle.dart';
import '../models/catalog_entry.dart';
import '../models/listing_row.dart';

/// Outcome of [ListingMergeService.merge].
class ListingMergeResult {
  final int inserted;
  final int updated;
  final int unchanged;

  /// New rows whose `name` had to come from the local catalog because a listing
  /// bundle carries no name (the B-1 fix for `products.name NOT NULL`).
  final int namedFromCatalog;

  /// New rows that are in **no** catalog — flagged `source = 'listing'` so the
  /// recovery chip can find them.
  final int notInCatalog;

  const ListingMergeResult({
    required this.inserted,
    required this.updated,
    required this.unchanged,
    required this.namedFromCatalog,
    required this.notInCatalog,
  });

  int get touched => inserted + updated;
}

/// Applies a **verified** listing bundle to a shop's database.
///
/// Locked decisions this encodes:
/// - **D3** — only `price_cents` / `stock_qty` are written, and only by
///   `barcode`. Name, category and photo are never touched, so a bundle cannot
///   overwrite catalog data.
/// - **D4** — import never deletes. A bundle is a snapshot; removing a product
///   is an explicit admin action.
/// - **D5** — one transaction for the whole bundle; any error rolls it all back.
/// - **B-1** — a brand-new row needs a `name` (`products.name` is NOT NULL), so
///   it is taken from the local catalog. A barcode that is in no catalog gets
///   the barcode as its display name and is flagged for recovery.
///
/// Every change writes an `audit_log` row with [changedBy] (the signer's name),
/// so attribution is a by-product rather than extra work.
class ListingMergeService {
  static Future<ListingMergeResult> merge(
    ListingBundle bundle, {
    required String changedBy,
    CatalogRepository? catalog,
  }) async {
    await Db.open(bundle.shopKey);
    final handle = await Db.databaseHandle(bundle.shopKey);
    final repo = catalog ?? CatalogDb.instance;
    await repo.init();

    var inserted = 0;
    var updated = 0;
    var unchanged = 0;
    var namedFromCatalog = 0;
    var notInCatalog = 0;

    await handle.transaction((txn) async {
      for (final row in bundle.rows) {
        final rowsFound = await txn.query('products',
            where: 'barcode = ?', whereArgs: [row.barcode], limit: 1);
        final current = rowsFound.isEmpty ? null : rowsFound.first;

        if (current == null) {
          final entry = await repo.get(row.barcode);
          final now = DateTime.now().millisecondsSinceEpoch;
          final id = await txn.insert('products', {
            'name': entry?.name ?? row.barcode,
            'barcode': row.barcode,
            'price_cents': row.priceCents,
            'stock_qty': row.stockQty,
            'source': entry == null ? 'listing' : 'catalog',
          });
          await _audit(txn, bundle.shopKey, 'insert', 'products', id, null,
              _newValues(row), now, changedBy);
          inserted++;
          if (entry != null) {
            namedFromCatalog++;
          } else {
            notInCatalog++;
          }
          continue;
        }

        final id = current['id'] as int;
        final oldPrice = current['price_cents'] as int;
        final oldStock = current['stock_qty'] as int;
        if (oldPrice == row.priceCents && oldStock == row.stockQty) {
          unchanged++;
          continue;
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        await txn.update(
          'products',
          {'price_cents': row.priceCents, 'stock_qty': row.stockQty},
          where: 'id = ?',
          whereArgs: [id],
        );
        await _audit(txn, bundle.shopKey, 'update', 'products', id,
            _oldValues(oldPrice, oldStock), _newValues(row), now, changedBy);
        updated++;
      }
    });

    return ListingMergeResult(
      inserted: inserted,
      updated: updated,
      unchanged: unchanged,
      namedFromCatalog: namedFromCatalog,
      notInCatalog: notInCatalog,
    );
  }

  static String _newValues(ListingRow row) =>
      jsonEncode({'price_cents': row.priceCents, 'stock_qty': row.stockQty});

  static String _oldValues(int price, int stock) =>
      jsonEncode({'price_cents': price, 'stock_qty': stock});

  static Future<void> _audit(
    Transaction txn,
    String shopKey,
    String action,
    String table,
    int recordId,
    String? oldValues,
    String newValues,
    int now,
    String changedBy,
  ) async {
    await txn.insert('audit_log', {
      'shop_key': shopKey,
      'action': action,
      'table_name': table,
      'record_id': recordId,
      'old_values': oldValues,
      'new_values': newValues,
      'changed_at': now,
      'changed_by': changedBy,
    });
  }
}
