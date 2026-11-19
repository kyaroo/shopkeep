import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'catalog_delta.dart';
import 'catalog_seed_loader.dart';
import '../models/catalog_entry.dart';

/// SQLite implementation of [CatalogRepository].
///
/// Schema v1 matches the agreed mapper schema; the remote API (later) mirrors
/// it, so a remote implementation is a drop-in replacement for this class.
/// A `pending_deletes` table records tombstones so a delete reaches the server
/// on the next manual sync (Option B), even though the row is gone locally.
class CatalogDb
    implements
        CatalogRepository,
        CatalogDeltaRepository,
        TransactionalCatalogRepository {
  CatalogDb._();
  static final CatalogDb instance = CatalogDb._();

  Database? _db;
  Future<void>? _initFuture;

  @override
  Future<void> init() async {
    if (_db != null) return;
    _initFuture ??= _doInit();
    return _initFuture!;
  }

  Future<void> _doInit() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'catalog.db');
    await CatalogSeedLoader.ensureSeeded(path);
    _db = await openDatabase(
      path,
      version: 4,
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
        await _createSignerLog(db);
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
        if (oldVersion < 4) {
          await _createSignerLog(db);
        }
      },
    );
  }

  /// Attribution: one row per applied delta — who pushed what, when, on which shop.
  static Future<void> _createSignerLog(Database db) => db.execute('''
        CREATE TABLE IF NOT EXISTS signer_log (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          version       INTEGER NOT NULL,
          signed_by     TEXT NOT NULL,
          signed_by_id  TEXT NOT NULL,
          applied_at    INTEGER NOT NULL,
          entry_count   INTEGER NOT NULL,
          applied_on_shop TEXT NOT NULL
        )
      ''');

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
  Future<List<CatalogEntry>> all({String? search, int? limit, int? offset}) async {
    final db = await _database;
    String where = '';
    List<Object?> args = [];
    if (search != null && search.trim().isNotEmpty) {
      where = 'WHERE name LIKE ? OR barcode LIKE ? OR category LIKE ? OR name_ar LIKE ?';
      args = ['%$search%', '%$search%', '%$search%', '%$search%'];
    }
    String sql = 'SELECT * FROM products $where ORDER BY updated_at DESC';
    if (limit != null) {
      sql += ' LIMIT ?';
      args.add(limit);
      if (offset != null) {
        sql += ' OFFSET ?';
        args.add(offset);
      }
    } else if (offset != null) {
      sql += ' LIMIT -1 OFFSET ?';
      args.add(offset);
    }
    final rows = await db.rawQuery(sql, args);
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

  /// Applies a whole delta (possibly many generations) in ONE transaction:
  /// every upsert and delete commits together, or the transaction rolls back.
  ///
  /// Mirrors [CatalogDelta.apply]'s merge rules: an upsert without a photo
  /// keeps the installed photo, and `created_at` is preserved for a row that
  /// already exists.
  @override
  Future<void> applyDeltaAtomic({
    required List<CatalogEntry> upserts,
    required List<String> deletes,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      for (final e in upserts) {
        final rows = await txn.query('products',
            where: 'barcode = ?', whereArgs: [e.barcode]);
        final existing =
            rows.isEmpty ? null : CatalogEntry.fromMap(rows.first);
        await txn.insert(
          'products',
          CatalogEntry(
            barcode: e.barcode,
            name: e.name,
            nameAr: e.nameAr,
            nameEn: e.nameEn,
            category: e.category,
            photo: e.photo ?? existing?.photo,
            createdAt: existing?.createdAt ?? e.createdAt,
            updatedAt: e.updatedAt,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      for (final barcode in deletes) {
        await txn.delete('products', where: 'barcode = ?', whereArgs: [barcode]);
        await txn.insert(
          'pending_deletes',
          {
            'barcode': barcode,
            'deleted_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Entries changed since [sinceMs] (exclusive) — the sync delta.
  @override
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
  @override
  Future<List<String>> pendingDeletes() async {
    final db = await _database;
    final rows = await db.query('pending_deletes');
    return rows.map((r) => r['barcode'] as String).toList();
  }

  /// Clear a tombstone after a successful sync.
  @override
  Future<void> clearPendingDelete(String barcode) async {
    final db = await _database;
    await db.delete('pending_deletes',
        where: 'barcode = ?', whereArgs: [barcode]);
  }

  @override
  Future<int> count({String? search}) async {
    final db = await _database;
    String where = '';
    List<Object?> args = [];
    if (search != null && search.trim().isNotEmpty) {
      where = 'WHERE name LIKE ? OR barcode LIKE ? OR category LIKE ? OR name_ar LIKE ?';
      args = ['%$search%', '%$search%', '%$search%', '%$search%'];
    }
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM products $where', args);
    return (result.first['c'] as int?) ?? 0;
  }

  // ---- Attribution log (who pushed what, when) ----

  Future<void> logSigner({
    required int version,
    required String signedBy,
    required String signedById,
    required int entryCount,
    required String appliedOnShop,
  }) async {
    final db = await _database;
    await db.insert('signer_log', {
      'version': version,
      'signed_by': signedBy,
      'signed_by_id': signedById,
      'applied_at': DateTime.now().millisecondsSinceEpoch,
      'entry_count': entryCount,
      'applied_on_shop': appliedOnShop,
    });
  }

  Future<List<Map<String, Object?>>> signerLog({int limit = 50}) async {
    final db = await _database;
    return db.query('signer_log',
        orderBy: 'applied_at DESC', limit: limit);
  }
}
