import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/catalog_entry.dart';

/// SQLite implementation of [CatalogRepository].
///
/// Schema v1 matches the agreed mapper schema; the remote API (later) mirrors
/// it, so a remote implementation is a drop-in replacement for this class.
/// A `pending_deletes` table records tombstones so a delete reaches the server
/// on the next manual sync (Option B), even though the row is gone locally.
class CatalogDb implements CatalogRepository {
  CatalogDb._();
  static final CatalogDb instance = CatalogDb._();

  Database? _db;

  @override
  Future<void> init() async {
    if (_db != null) return;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'catalog.db'),
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products (
            barcode     TEXT PRIMARY KEY,
            name        TEXT NOT NULL,
            name_ar     TEXT,
            name_en     TEXT,
            category    TEXT,
            photo       BLOB,
            created_at  INTEGER NOT NULL,
            updated_at  INTEGER NOT NULL
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_products_name ON products(name)');
        await db.execute(
            'CREATE INDEX idx_products_category ON products(category)');
        await db.execute('''
          CREATE TABLE pending_deletes (
            barcode      TEXT PRIMARY KEY,
            deleted_at   INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS pending_deletes (
              barcode      TEXT PRIMARY KEY,
              deleted_at   INTEGER NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE products ADD COLUMN name_ar TEXT');
          await db.execute('ALTER TABLE products ADD COLUMN name_en TEXT');
        }
      },
    );
  }

  Future<Database> get _database async {
    await init();
    return _db!;
  }

  @override
  Future<CatalogEntry?> get(String barcode) async {
    final db = await _database;
    final rows =
        await db.query('products', where: 'barcode = ?', whereArgs: [barcode]);
    if (rows.isEmpty) return null;
    return CatalogEntry.fromMap(rows.first);
  }

  @override
  Future<List<CatalogEntry>> all({String? search}) async {
    final db = await _database;
    final rows = (search != null && search.trim().isNotEmpty)
        ? await db.query(
            'products',
            where: 'name LIKE ? OR barcode LIKE ? OR category LIKE ? '
                'OR name_ar LIKE ?',
            whereArgs: [
              '%$search%',
              '%$search%',
              '%$search%',
              '%$search%',
            ],
            orderBy: 'updated_at DESC',
          )
        : await db.query('products', orderBy: 'updated_at DESC');
    return rows.map(CatalogEntry.fromMap).toList();
  }

  @override
  Future<void> upsert(CatalogEntry entry) async {
    final db = await _database;
    await db.insert(
      'products',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String barcode) async {
    final db = await _database;
    await db.delete('products', where: 'barcode = ?', whereArgs: [barcode]);
    // Record a tombstone so the delete reaches the server on next manual sync.
    await db.insert(
      'pending_deletes',
      {
        'barcode': barcode,
        'deleted_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Entries changed since [sinceMs] (exclusive) — the sync delta.
  Future<List<CatalogEntry>> changedSince(int sinceMs) async {
    final db = await _database;
    final rows = await db.query(
      'products',
      where: 'updated_at > ?',
      whereArgs: [sinceMs],
      orderBy: 'updated_at ASC',
    );
    return rows.map(CatalogEntry.fromMap).toList();
  }

  /// Pending tombstones not yet synced.
  Future<List<String>> pendingDeletes() async {
    final db = await _database;
    final rows = await db.query('pending_deletes');
    return rows.map((r) => r['barcode'] as String).toList();
  }

  /// Clear a tombstone after a successful sync.
  Future<void> clearPendingDelete(String barcode) async {
    final db = await _database;
    await db.delete('pending_deletes',
        where: 'barcode = ?', whereArgs: [barcode]);
  }

  @override
  Future<int> count() async {
    final db = await _database;
    final result =
        await db.rawQuery('SELECT COUNT(*) AS c FROM products');
    return (result.first['c'] as int?) ?? 0;
  }
}
