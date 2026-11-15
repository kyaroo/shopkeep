#!/usr/bin/env python3
"""Build `assets/catalog_seed.db` from the catalog server DB.

Ships the full catalog — names + photos @128px — inside the APK so a fresh
install is complete offline. The output schema matches `CatalogDb` v3 exactly
(products + indexes + pending_deletes, PRAGMA user_version = 3), so
`CatalogSeedLoader.ensureSeeded` copies it without any migration.

Usage:
    python3 tool/build_catalog_seed_with_photos.py <server_catalog.db> <out.db>
"""
import sqlite3
import sys
from pathlib import Path

SCHEMA = """
CREATE TABLE products (
  barcode     TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  name_ar     TEXT,
  name_en     TEXT,
  category    TEXT,
  photo       BLOB,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE INDEX idx_products_name ON products(name);
CREATE INDEX idx_products_category ON products(category);
CREATE TABLE pending_deletes (
  barcode      TEXT PRIMARY KEY,
  deleted_at   INTEGER NOT NULL
);
"""


def main() -> int:
    src, out = sys.argv[1], sys.argv[2]
    if Path(out).exists():
        Path(out).unlink()

    source = sqlite3.connect(src)
    rows = source.execute(
        """
        SELECT s.barcode, s.name_fr, s.name_ar, s.name_en, s.category,
               p.photo, s.updated_at
        FROM catalog_source s
        LEFT JOIN catalog_photos p ON p.barcode = s.barcode
        ORDER BY s.barcode
        """
    ).fetchall()

    dst = sqlite3.connect(out)
    dst.executescript(SCHEMA)
    dst.executemany(
        "INSERT INTO products "
        "(barcode, name, name_ar, name_en, category, photo, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [(b, n or '', na, ne, c, ph, ts or 0, ts or 0)
         for b, n, na, ne, c, ph, ts in rows],
    )
    dst.execute("PRAGMA user_version = 3")
    dst.commit()

    total = dst.execute("SELECT COUNT(*) FROM products").fetchone()[0]
    with_photo = dst.execute(
        "SELECT COUNT(*), COALESCE(SUM(LENGTH(photo)), 0) FROM products "
        "WHERE photo IS NOT NULL"
    ).fetchone()
    dst.close()
    source.close()

    size = Path(out).stat().st_size
    print(f"wrote {out}: {total} products, {with_photo[0]} with photos, "
          f"{with_photo[1] / 1024 / 1024:.1f} MB of photos, {size / 1024 / 1024:.1f} MB file")
    return 0


if __name__ == "__main__":
    sys.exit(main())
