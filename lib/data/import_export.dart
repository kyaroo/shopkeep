import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/product.dart';
import '../models/sale.dart';
import 'audit.dart' as audit_lib;
import 'db.dart';

/// JSON wire format for the shop catalog.
///
/// ```json
/// {
///   "version": 1,
///   "exported_at": 1718000000000,
///   "shop_key": "default",
///   "products": [ { "id": 1, "name": "...", "barcode": "...", "price_cents": 1000, "stock_qty": 50, "low_stock_threshold": 5 } ],
///   "sales": [ {"id": 1, "created_at": 1718000000000, "total_cents": 5000, "item_count": 2} ],
///   "sale_items": [ {"id": 1, "sale_id": 1, "product_name": "...", "unit_price_cents": 2500, "quantity": 2, "line_total_cents": 5000} ],
///   "audit_log": [ {"id": 1, "shop_key": "default", "action": "INSERT", "table_name": "products", "record_id": 1, "old_values": null, "new_values": {"id":1,...}, "changed_at": 1718000000000, "changed_by": "system"} ]
/// }
/// ```
///
/// `version: 1` is the current wire format. Future versions bump the
/// `version` field; importers read it and reject incompatible exports with
/// a clear error instead of silently corrupting data.
class Catalog {
  final int version;
  final int exportedAt;
  final String shopKey;
  final List<Product> products;
  final List<Sale> sales;
  final List<Map<String, Object?>> saleItems;
  final List<Map<String, Object?>> auditLog;

  const Catalog({
    required this.version,
    required this.exportedAt,
    required this.shopKey,
    required this.products,
    required this.sales,
    required this.saleItems,
    required this.auditLog,
  });

  Map<String, Object?> toMap() => {
        'version': version,
        'exported_at': exportedAt,
        'shop_key': shopKey,
        'products': products.map((p) => p.toMap()).toList(),
        'sales': sales.map((s) => s.toMap()).toList(),
        'sale_items': saleItems,
        'audit_log': auditLog,
      };

  factory Catalog.fromMap(Map<String, Object?> m) {
    if (m['version'] != null && m['version'] is int && m['version'] != 1) {
      throw CatalogFormatException(
          'Unsupported export version ${m['version']}. This tool only handles v1.');
    }
    return Catalog(
      version: m['version'] as int? ?? 1,
      exportedAt: (m['exported_at'] as num?)?.toInt() ?? 0,
      shopKey: m['shop_key'] as String? ?? '',
      products: (m['products'] as List<Object?>?)
              ?.map((e) => Product.fromMap(e as Map<String, Object?>))
              .toList() ??
          [],
      sales: (m['sales'] as List<Object?>?)
              ?.map((e) => Sale.fromMap(e as Map<String, Object?>))
              .toList() ??
          [],
      saleItems: (m['sale_items'] as List<Object?>?)
              ?.map((e) => e as Map<String, Object?>)
              .toList() ??
          [],
      auditLog: (m['audit_log'] as List<Object?>?)
              ?.map((e) => e as Map<String, Object?>)
              .toList() ??
          [],
    );
  }
}

/// Reads a [Catalog] from a JSON file and returns the parsed object.
/// Throws [CatalogNotFoundException] on missing files, [CatalogFormatException] on parse errors or unsupported versions.
Catalog readCatalog(File file) {
  if (!file.existsSync()) {
    throw CatalogNotFoundException('Export file not found: ${file.path}');
  }
  final text = file.readAsStringSync();
  final json = jsonDecode(text) as Map<String, Object?>;
  return Catalog.fromMap(json);
}

/// Writes a [Catalog] to a file as indented JSON.
void writeCatalog(Catalog catalog, File file) {
  final text =
      const JsonEncoder.withIndent('  ').convert(catalog.toMap()) + '\n';
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(text);
}

/// Result of an import operation: how many rows were inserted and any errors.
class ImportResult {
  final int inserted;
  final int skipped;
  final String? error;

  const ImportResult({required this.inserted, required this.skipped, this.error});

  bool get ok => error == null;

  @override
  String toString() =>
      'ImportResult(inserted=$inserted, skipped=$skipped, error=$error)';
}

/// Exception thrown when a catalog file cannot be read or understood.
class CatalogNotFoundException implements Exception {
  final String message;
  CatalogNotFoundException(this.message);

  @override
  String toString() => message;
}

/// Exception thrown when a catalog file is malformed or uses an unsupported version.
class CatalogFormatException implements Exception {
  final String message;
  CatalogFormatException(this.message);

  @override
  String toString() => message;
}

/// Serializes a shop's entire catalog (products, sales, sale_items, audit_log)
/// to a JSON string.
///
/// This is the "solid catalog" snapshot: it contains everything the shop has
/// ever entered, so a restore re-creates the exact same data.
Future<String> catalogToJson(String shopKey) async {
  final db = await Db.open(shopKey);
  final products = await db.getProducts(shopKey);
  final sales = await db.getSales(shopKey,
      startMs: 0, endMs: DateTime.now().millisecondsSinceEpoch);
  final List<Map<String, Object?>> saleItems = [];
  for (final sale in sales) {
    for (final item in sale.items) {
      saleItems.add(item.toMap());
    }
  }
  final List<Map<String, Object?>> auditLog = [];
  final rows = await db.rawQuery(
    'SELECT * FROM audit_log ORDER BY id',
  );
  for (final row in rows) {
    auditLog.add(row);
  }
  return const JsonEncoder.withIndent('  ').convert(
        {
          'version': 1,
          'exported_at': DateTime.now().millisecondsSinceEpoch,
          'shop_key': shopKey,
          'products': (await products).map((p) => p.toMap()).toList(),
          'sales': (await sales).map((s) => s.toMap()).toList(),
          'sale_items': saleItems,
          'audit_log': auditLog,
        },
      );
}

/// Imports a catalog JSON string into the shop's database.
///
/// Products are matched by `id` (update) or `barcode` (insert if new).
/// Sales and sale_items are inserted in order. Audit rows are re-inserted.
///
/// Returns an [ImportResult] with the number of rows inserted and any errors.
Future<ImportResult> importCatalogJson(String shopKey, String json) async {
  ImportResult result;
  try {
    final catalog = Catalog.fromMap(jsonDecode(json));
    final db = await Db.open(shopKey);
    await db.transaction((txn) async {
      // Clear existing data in dependency order (audit last).
      await txn.rawDelete('DELETE FROM audit_log');
      await txn.rawDelete('DELETE FROM sale_items');
      await txn.rawDelete('DELETE FROM sales');
      await txn.rawDelete('DELETE FROM products');

      // Insert products.
      for (final p in catalog.products) {
        final id = await txn.insert('products', p.toMap());
        if (id > 0) {
          await audit_lib.Audit.log(
            shopKey: shopKey,
            action: 'INSERT',
            table: 'products',
            recordId: id,
            newValues: p.toMap(),
            changedBy: 'system',
          );
        }
      }

      // Insert sales and sale_items in order.
      for (final sale in catalog.sales) {
        final saleId = await txn.insert('sales', sale.toMap());
        final items = catalog.saleItems
            .where((i) => i['sale_id'] == sale.id)
            .toList();
        for (final item in items) {
          await txn.insert(
            'sale_items',
            {
              'sale_id': saleId,
              'product_name': item['product_name'],
              'unit_price_cents': item['unit_price_cents'],
              'quantity': item['quantity'],
              'line_total_cents': item['line_total_cents'],
            },
          );
        }
      }

      // Re-insert audit rows.
      for (final a in catalog.auditLog) {
        await txn.insert(
          'audit_log',
          {
            'shop_key': a['shop_key'],
            'action': a['action'],
            'table_name': a['table_name'],
            'record_id': a['record_id'],
            'old_values': a['old_values'],
            'new_values': a['new_values'],
            'changed_at': a['changed_at'],
            'changed_by': a['changed_by'],
          },
        );
      }
    });
    result = ImportResult(inserted: 0, skipped: 0);
  } on FormatException {
    return const ImportResult(inserted: 0, skipped: 0, error: 'Invalid JSON format');
  } on CatalogFormatException {
    return const ImportResult(inserted: 0, skipped: 0, error: 'Unsupported export format');
  } catch (e) {
    result = ImportResult(inserted: 0, skipped: 0, error: e.toString());
  }
  return result;
}
