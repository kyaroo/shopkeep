# Multi-shop architecture — concrete spec

Scope: turn ShopKeeper v1 (single shop, shared SQLite file) into a
file-per-shop system with an audit trail. The app remains a single-account
design: one APK, one shop per install, no login, no account server.

## 1. Principle: the file is the tenant

- **No `shop_id` column, no `WHERE shop_id = ?`, no cross-shop queries.**
  Isolation is by file system: each shop gets exactly one SQLite file
  `myhanout_<shopKey>.db` under the platform databases directory
  (`path_provider`), so the OS/app sandbox already isolates tenants.
- The only tenant identity is a per-install `shopKey` (6–8 charset slug or
  UUID prefix, stored in `shared_preferences`), set once at first launch
  (config screen) and used to derive the DB path. A second shop = second
  install / second `shopKey` = second `.db` file.
- Business identity (display name, currency, owner label) is **app config**
  (shared_preferences), not a table — there is no centralized shop registry.

## 2. New schema (per shop DB, v4)

Same `products`, `sales`, `sale_items` as before, plus `audit_log`.

```sql
CREATE TABLE products (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  name            TEXT NOT NULL,
  barcode         TEXT,                       -- nullable; UNIQUE index
  price_cents     INTEGER NOT NULL,
  stock_qty       INTEGER NOT NULL DEFAULT 0,
  low_stock_threshold INTEGER NOT NULL DEFAULT 5
);
CREATE UNIQUE INDEX idx_product_barcode ON products(barcode);

CREATE TABLE sales (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at   INTEGER NOT NULL,               -- epoch ms
  total_cents  INTEGER NOT NULL,
  item_count   INTEGER NOT NULL
);
CREATE INDEX idx_sales_created_at ON sales(created_at);

CREATE TABLE sale_items (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  sale_id         INTEGER NOT NULL,
  product_name    TEXT NOT NULL,
  unit_price_cents INTEGER NOT NULL,
  quantity        INTEGER NOT NULL,
  line_total_cents INTEGER NOT NULL,
  FOREIGN KEY (sale_id) REFERENCES sales(id)
);
CREATE INDEX idx_sale_items_sale_id ON sale_items(sale_id);

-- Every data mutation. JSON blobs are TEXT; one row per affected record.
CREATE TABLE audit_log (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  shop_key        TEXT NOT NULL,               -- denormalized for export/diag
  action          TEXT NOT NULL,               -- INSERT | UPDATE | DELETE
  table_name      TEXT NOT NULL,
  record_id       INTEGER NOT NULL,            -- PK of the changed row
  old_values      TEXT,                        -- JSON, null for INSERT
  new_values      TEXT,                        -- JSON, null for DELETE
  changed_at      INTEGER NOT NULL,            -- epoch ms, UTC
  changed_by      TEXT NOT NULL                -- device/install id (see 4)
);
CREATE INDEX idx_audit_log_action_table ON audit_log(action, table_name);
CREATE INDEX idx_audit_log_changed_at ON audit_log(changed_at DESC);
```

The `shops` registry is intentionally **not** a table: tenants live on the
file system. If a cross-shop overview (e.g. "list all shops on this phone")
is ever needed, a tiny `settings.json` registry in the same directory
replaces a shared database — no SQL, no join, no migration.

## 3. Db.open() — per-shop accessor

The `Db` class becomes a small factory/registry keyed by shop key. Every
query inside a `Db` instance is scoped to that shop's file — the SQL never
mentions a shop.

```dart
class Db {
  // Cache: one Db handle per open shop.
  static final _cache = <String, Db>{};

  factory Db.open(String shopKey) {
    _cache.putIfAbsent(shopKey, () => _open(shopDbFile(shopKey)));
    return _cache[shopKey]!;
  }

  static Database _open(File file) {
    // Ensure the (app-scoped) directory exists before opening.
    file.parent.createSync(recursive: true);
    return openDatabase(
      file.path,
      version: 4,
      onConfigure: (_) async => _enableWals(),
      onCreate: (db, v) => _createAll(db),
      onUpgrade: (db, old, newV) => _upgrade(db, old, newV),
    );
  }

  static String shopDbPath(String shopKey) => join(
        path_provider.getDatabasesPath(),
        'shopkeeper_$shopKey.db',
      );

  static File shopDbFile(String shopKey) => File(shopDbPath(shopKey));

  // Existing product/sale/sales-history methods stay exactly as they are,
  // only the accessor changes:
  static Future<List<Product>> getProducts(String shopKey, {String? search}) =>
      Db.open(shopKey).getProducts(search: search);
  // ... insertProduct, updateProduct, deleteProduct, deductStock,
  //     insertSale, getSales, getSalesStats all take shopKey too.

  static Future<void> close(String shopKey) async {
    final db = _cache.remove(shopKey);
    if (db != null) await db.close();
  }
}
```

Rules for the change:
- `Db().getProducts(...)` (shared-file style) is **removed**.
- All business methods take an explicit `shopKey`; the instance cache keeps
  handles open and reusable.
- `close()` is still available for app-delete-site scenarios.

## 4. Audit.log() — mandatory mutation audit

Audit is a tiny, dependency-free service. Every data mutation in `Db`
records a row through it. JSON maps are the audit payload (no new column
types, no ORM).

```dart
class Audit {
  static Future<int> log({
    required String shopKey,
    required String action,          // 'INSERT' | 'UPDATE' | 'DELETE'
    required String table,
    required int recordId,
    Map<String, Object?>? oldValues,
    Map<String, Object?>? newValues,
    String changedBy = '',           // install/device id; 'system' for bulk
  }) async {
    // Serialize defensively: any encoding failure is logged (print) and
    // swallowed — audit must never block the business flow.
    final oldJson = oldValues == null
        ? null
        : const JsonEncoder.withIndent('  ').convert(oldValues);
    final newJson = newValues == null
        ? null
        : const JsonEncoder.withIndent('  ').convert(newValues);
    await Db.open(shopKey).insert(
      'INSERT INTO audit_log '
      '(shop_key, action, table_name, record_id, old_values, new_values, changed_at, changed_by) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        shopKey, action, table, recordId, oldJson, newJson,
        DateTime.now().millisecondsSinceEpoch, changedBy,
      ],
    );
    return 0;
  }
}
```

Usage in `Db` (show the before/after of the row the tool just wrote):

```dart
Future<int> insertProduct(Product p, String shopKey) async {
  final id = await Db.open(shopKey).insert('products', p.toMap());
  await Audit.log(shopKey: shopKey, action: 'INSERT', table: 'products',
      recordId: id, newValues: p.toMap(), changedBy: deviceId);
  return id;
}

Future<int> updateProduct(Product p, String shopKey) async {
  final existed = await getProductById(p.id!, shopKey: shopKey);
  final id = await Db.open(shopKey).update('products', p.toMap(),
      where: 'id = ?', whereArgs: [p.id]);
  await Audit.log(shopKey: shopKey, action: 'UPDATE', table: 'products',
      recordId: id, oldValues: existed!.toMap(), newValues: p.toMap(),
      changedBy: deviceId);
  return id;
}

Future<void> deductStock(Map<int, int> deductions, String shopKey) async {
  await Db.open(shopKey).transaction((txn) async {
    for (final entry in deductions.entries) {
      final before = await txn.query('products',
          columns: ['stock_qty'], where: 'id = ?', whereArgs: [entry.key]);
      final beforeQty = (before.first['stock_qty'] as int?) ?? 0;
      await txn.rawUpdate(
        'UPDATE products SET stock_qty = stock_qty - ? WHERE id = ?',
        [entry.value, entry.key],
      );
      final afterQty = beforeQty - entry.value;
      // Record the row-level before/after; one audit row per affected product.
      await Audit.log(shopKey: shopKey, action: 'UPDATE', table: 'products',
          recordId: entry.key, oldValues: {'stock_qty': beforeQty},
          newValues: {'stock_qty': afterQty}, changedBy: deviceId);
    }
  });
}
```

Notes:
- `old_values`/`new_values` are `null` for INSERT and DELETE respectively.
- Bulk operations (e.g. `deductStock`, CSV import) log one row per affected
  record with `changed_by = 'system'` (or a batch id) rather than a single
  summary row — row-level is the only granularity that survives recomputation.
- The `shop_key` column is denormalized so audit exports can be filtered by
  tenant without touching SQLite; with file-per-shop it is informational
  only.

## 5. Provider / shell changes (minimal)

- `CartProvider` takes a `shopKey` on construction (or via an initializer)
  and holds `final String businessName` read from app config (`shared_
  preferences`) instead of the hardcoded 'Maison du Marché'.
- HomePage shows the business name from config above the app; title stays
  'myhanout'.
- `Db` calls become `Db.open(shopKey)` (see 3). No other provider logic
  changes.
- `Db.close(shopKey)` on app pause (`AppLifecycleListener` / `dispose`) so
  handles don't leak across shop switches or process terminations.

## 6. Migration (one-time)

1. Extract `shopKey` from the existing shared file name or generate a new
   one (e.g. `uuid().substring(0, 8)`); keep a one-off mapping
   `oldFile → shopKey` in shared_preferences.
2. Open each legacy table with `ATTACH` and copy rows into a fresh
   `shopkeeper_<key>.db` (same DDL + audit_log).
3. Verify row counts, barcode uniqueness, and sales totals; then delete the
   legacy `shopkeeper.db` (tracked in `.gitignore`, not committed).
4. Bump `pubspec.yaml` version and DB `version: 4`; `onUpgrade` handles the
   old v3 file forwards.

## 7. Out of scope, kept

- Single-account design (no login, no account server) — unchanged.
- Market Trust theme, EasyLocalization (en/fr/ar), Tajawal/Inter fonts,
  `parseDirhamsToCents` money model, barcode sources, scan page, tests.
- Mobile Scanner, share_plus, http/Open Food Facts / UPCitemDB.

## 8. Verification

- `flutter analyze` clean; new unit tests for `Db.open(shopKey)` path
  derivation, `Audit.log` payload round-trip, and the v3→v4 migration.
- Two `shopKey`s in one app run → two distinct `.db` files, zero cross-
  contamination (each `Db.open(key)` only ever sees its own rows).
- `dart run build_runner`/analysis unaffected (new file, no new deps).
