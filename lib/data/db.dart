import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/product.dart';
import '../models/sale.dart';

class Db {
  static final Db _instance = Db._internal();
  factory Db() => _instance;
  Db._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'shopkeeper.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE products ADD COLUMN low_stock_threshold INTEGER NOT NULL DEFAULT 5');
        }
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
      },
    );
  }

  // ---- Products ----

  Future<List<Product>> getProducts({String? search}) async {
    final db = await database;
    final where = search != null && search.isNotEmpty
        ? "WHERE name LIKE ? OR barcode LIKE ?"
        : null;
    final args = search != null && search.isNotEmpty
        ? ['%$search%', '%$search%']
        : null;
    final rows = await db.rawQuery(
        'SELECT * FROM products ${where ?? ''} ORDER BY name COLLATE NOCASE',
        args);
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> getByBarcode(String barcode) async {
    final db = await database;
    final rows =
        await db.query('products', where: 'barcode = ?', whereArgs: [barcode]);
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  Future<int> insertProduct(Product p) async {
    final db = await database;
    return db.insert('products', p.toMap());
  }

  Future<int> updateProduct(Product p) async {
    final db = await database;
    return db.update('products', p.toMap(),
        where: 'id = ?', whereArgs: [p.id]);
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  /// Deduct stock for completed sale. [deductions] maps productId -> qty.
  Future<void> deductStock(Map<int, int> deductions) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final entry in deductions.entries) {
        await txn.rawUpdate(
          'UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?',
          [entry.value, entry.key],
        );
      }
    });
  }

  // ---- Sales ----

  /// Records a completed sale with its line items in a single transaction.
  /// [items] is a list of maps: productName, unitPriceCents, quantity, lineTotalCents.
  Future<int> insertSale(int totalCents, List<Map<String, Object?>> items) async {
    final db = await database;
    return db.transaction((txn) async {
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

  /// Returns sales within [startMs, endMs] (inclusive), newest first.
  Future<List<Sale>> getSales({required int startMs, required int endMs}) async {
    final db = await database;
    final rows = await db.query(
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

  /// Returns aggregate stats for sales within [startMs, endMs].
  /// Keys: totalRevenueCents, totalItems, saleCount.
  Future<Map<String, int>> getSalesStats({required int startMs, required int endMs}) async {
    final db = await database;
    final row = await db.rawQuery(
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

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
