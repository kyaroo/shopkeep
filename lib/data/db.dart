import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/product.dart';

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
      version: 2,
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
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE products ADD COLUMN low_stock_threshold INTEGER NOT NULL DEFAULT 5');
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

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
