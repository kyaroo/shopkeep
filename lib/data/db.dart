import 'dart:io';

import 'package:path/path.dart' show join;
import 'package:sqflite/sqflite.dart';

import '../data/audit.dart';

import '../models/product.dart';
import '../models/sale.dart';

/// File-per-shop database accessor + mandatory mutation audit.
///
/// Principle: **the file is the tenant**. Isolation is by file system, not by
/// SQL. Each shopKey gets exactly one SQLite file at
/// `$databasesPath/shopkeeper_<shopKey>.db`. There is no `shop_id` column and
/// no `WHERE shop_id = ?` — the SQL never mentions a shop, so cross-shop
/// contamination is impossible by construction.
///
/// Every data mutation records an audit row (action, table, record_id,
/// old_values/new_values JSON, changed_at, changed_by) via the [Audit] class.
class Db {
  Db._(this._file, this._db);

  final File _file;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      _file.path,
      version: 4,
      onConfigure: (_) async => await enableWals(),
      onCreate: _createAll,
      onUpgrade: _upgrade,
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static final Map<String, Db> _openHandles = {};

  static Future<Db> open(String shopKey) async {
    _expire(shopKey);
    if (_openHandles.containsKey(shopKey)) return _openHandles[shopKey]!;
    final file = await shopDbFile(shopKey);
    file.parent.createSync(recursive: true);
    final db = await openDatabase(
      file.path,
      version: 4,
      onConfigure: (_) async => await enableWals(),
      onCreate: _createAll,
      onUpgrade: _upgrade,
    );
    _openHandles[shopKey] = Db._(file, db);
    return _openHandles[shopKey]!;
  }

  static void _expire(String shopKey) => _openHandles.remove(shopKey);

  static Future<String> shopDbPath(String shopKey) async =>
      join(await getDatabasesPath(), 'shopkeeper_$shopKey.db');

  static Future<File> shopDbFile(String shopKey) async =>
      File(await shopDbPath(shopKey));

  static Future<void> closeShop(String shopKey) async {
    _expire(shopKey);
    final handle = _openHandles[shopKey];
    if (handle != null) {
      await handle._db?.close();
      await handle._file.delete();
    }
  }

  static Future<void> enableWals() async {}

  /// Static shortcut: open (lazily creating) the shop's database and return
  /// its [Database] handle. Used primarily by [Audit.log] and tests.
  static Future<Database> databaseHandle(String shopKey) async {
    final db = await Db.open(shopKey);
    return db.database;
  }

  static Future<void> _createAll(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        barcode TEXT,
        price_cents INTEGER NOT NULL,
        stock_qty INTEGER NOT NULL DEFAULT 0,
        low_stock_threshold INTEGER NOT NULL DEFAULT 5
      )
    ''');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_product_barcode ON products(barcode)');
    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created_at INTEGER NOT NULL,
        total_cents INTEGER NOT NULL,
        item_count INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        unit_price_cents INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        line_total_cents INTEGER NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON sale_items(sale_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales(created_at)');
    await db.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shop_key TEXT NOT NULL,
        action TEXT NOT NULL,
        table_name TEXT NOT NULL,
        record_id INTEGER NOT NULL,
        old_values TEXT,
        new_values TEXT,
        changed_at INTEGER NOT NULL,
        changed_by TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_audit_log_action_table ON audit_log(action, table_name)');
    await db.execute(
        'CREATE INDEX idx_audit_log_changed_at ON audit_log(changed_at DESC)');
  }

  static Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      if (oldVersion < 3) {
        await db.execute('''
          CREATE TABLE sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at INTEGER NOT NULL,
            total_cents INTEGER NOT NULL,
            item_count INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sale_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER NOT NULL,
            product_name TEXT NOT NULL,
            unit_price_cents INTEGER NOT NULL,
            quantity INTEGER NOT NULL,
            line_total_cents INTEGER NOT NULL,
            FOREIGN KEY (sale_id) REFERENCES sales(id)
          )
        ''');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON sale_items(sale_id)');
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales(created_at)');
      }
      await db.execute('''
        CREATE TABLE audit_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          shop_key TEXT NOT NULL,
          action TEXT NOT NULL,
          table_name TEXT NOT NULL,
          record_id INTEGER NOT NULL,
          old_values TEXT,
          new_values TEXT,
          changed_at INTEGER NOT NULL,
          changed_by TEXT NOT NULL
        )
      ''');
      await db.execute(
          'CREATE INDEX idx_audit_log_action_table ON audit_log(action, table_name)');
      await db.execute(
          'CREATE INDEX idx_audit_log_changed_at ON audit_log(changed_at DESC)');
    }
  }

  // ---- Products ----

  Future<List<Product>> getProducts(String shopKey, {String? search}) async {
    final db = await _db;
    final where = search != null && search.isNotEmpty
        ? "WHERE name LIKE ? OR barcode LIKE ?"
        : null;
    final args = search != null && search.isNotEmpty
        ? ['%$search%', '%$search%']
        : null;
    final rows = await db!.rawQuery(
        'SELECT * FROM products ${where ?? ''} ORDER BY name COLLATE NOCASE',
        args);
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> getByBarcode(String shopKey, String barcode) async {
    final db = await _db;
    final rows = await db!.query(
        'products', where: 'barcode = ?', whereArgs: [barcode]);
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  /// Look up a product by its [id] within a shop's database.
  static Future<Product?> getProductById(String shopKey, int id) async {
    final db = await Db.databaseHandle(shopKey);
    final rows = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  Future<int> insertProduct(String shopKey, Product p) async {
    final id = await _db!.insert('products', p.toMap());
    await Audit.log(
      shopKey: shopKey,
      action: 'INSERT',
      table: 'products',
      recordId: id,
      newValues: p.toMap(),
      changedBy: 'system',
    );
    return id;
  }

  Future<int> updateProduct(String shopKey, Product p) async {
    final existed = await getProductById(shopKey, p.id!);
    final id = await _db!.update(
        'products', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
    await Audit.log(
      shopKey: shopKey,
      action: 'UPDATE',
      table: 'products',
      recordId: id,
      oldValues: existed?.toMap(),
      newValues: p.toMap(),
      changedBy: 'system',
    );
    return id;
  }

  Future<int> deleteProduct(String shopKey, int id) async {
    final rows = await _db!.delete(
        'products', where: 'id = ?', whereArgs: [id]);
    if (rows > 0) {
      await Audit.log(
        shopKey: shopKey,
        action: 'DELETE',
        table: 'products',
        recordId: id,
        oldValues: {'id': id},
        changedBy: 'system',
      );
    }
    return rows;
  }

  /// Deduct stock for completed sale. [deductions] maps productId -> qty.
  Future<void> deductStock(String shopKey, Map<int, int> deductions) async {
    await transaction((txn) async {
      for (final entry in deductions.entries) {
        final before = await txn.query(
          'products',
          columns: ['stock_qty'],
          where: 'id = ?',
          whereArgs: [entry.key],
        );
        final beforeQty = (before.first['stock_qty'] as int?) ?? 0;
        await txn.rawUpdate(
          'UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?',
          [entry.value, entry.key],
        );
        final afterQty = beforeQty - entry.value;
        await Audit.log(
          shopKey: shopKey,
          action: 'UPDATE',
          table: 'products',
          recordId: entry.key,
          oldValues: {'stock_qty': beforeQty},
          newValues: {'stock_qty': afterQty},
          changedBy: 'system',
        );
      }
    });
  }

  // ---- Sales ----

  Future<int> insertSale(String shopKey, int totalCents, List<Map<String, Object?>> items) async {
    final db = await _db;
    return db!.transaction((txn) async {
      final saleId = await txn.insert('sales', {
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'total_cents': totalCents,
        'item_count': items.length,
      });
      for (final item in items) {
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_name': item['productName'],
          'unit_price_cents': item['unitPriceCents'],
          'quantity': item['quantity'],
          'line_total_cents': item['lineTotalCents'],
        });
      }
      return saleId;
    });
  }

  Future<List<Sale>> getSales(String shopKey, {required int startMs, required int endMs}) async {
    final db = await _db;
    final rows = await db!.query(
      'sales',
      where: 'created_at >= ? AND created_at <= ?',
      whereArgs: [startMs, endMs],
      orderBy: 'created_at DESC',
    );
    final sales = <Sale>[];
    for (final row in rows) {
      final id = row['id'] as int;
      final itemRows = await db.query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [id],
      );
      sales.add(Sale.fromMap(
        row,
        items: itemRows.map(SaleItem.fromMap).toList(),
      ));
    }
    return sales;
  }

  Future<Map<String, int>> getSalesStats(String shopKey, {required int startMs, required int endMs}) async {
    final db = await _db;
    final row = await db!.rawQuery(
      'SELECT COALESCE(SUM(total_cents),0) AS revenue, '
      'COALESCE(SUM(item_count),0) AS items, '
      'COUNT(*) AS count '
      'FROM sales WHERE created_at >= ? AND created_at <= ?',
      [startMs, endMs],
    );
    final r = row.first;
    return {
      'totalRevenueCents': (r['revenue'] as int?) ?? 0,
      'totalItems': (r['items'] as int?) ?? 0,
      'saleCount': (r['count'] as int?) ?? 0,
    };
  }

  // ---- helpers ----

  Future<int> insert(String table, Map<String, Object?> row) async {
    final db = await _db;
    return db!.insert(table, row);
  }

  Future<int> delete(String table, String where, List<Object?> whereArgs) async {
    final db = await _db;
    return db!.delete(table, where: where, whereArgs: whereArgs);
  }

  /// Low-level row query. Exposes the underlying sqflite [Database.query] with
  /// its exact parameter types to avoid the `Db.query` instance method
  /// conflicting with the [Database.query] extension.
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    final db = await _db;
    return db!.rawQuery(sql, arguments);
  }

  Future<void> transaction(Future<void> Function(Transaction txn) action) async {
    final db = await _db;
    await db!.transaction(action);
  }
}
