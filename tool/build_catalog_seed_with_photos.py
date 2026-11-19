#!/usr/bin/env python3
"""Build `assets/catalog_seed.db` from the catalog server DB.

Ships the full catalog — names + photos @128px — inside the APK so a fresh
install is complete offline. The output schema matches `CatalogDb` v3, plus the
new nullable `retail_price_cents` column carried over from the server's
`catalog_source` table (PRAGMA user_version stays 3 — the column is additive),
so `CatalogSeedLoader.ensureSeeded` copies it without any migration.

The tool is strictly host-side: it reads a server DB dump and writes a SQLite
file + a small JSON manifest. It never builds an APK, never touches a device,
and never talks to the server over the network.

Usage:
    python3 tool/build_catalog_seed_with_photos.py <server_catalog.db> <out.db> \
        [--catalog-version N] [--manifest PATH]

`--catalog-version` defaults to the `seedCatalogVersion` constant found in
lib/data/catalog_seed_loader.dart, so the emitted manifest matches the version
the app will adopt on first seed. The manifest path defaults to
`<out.db>.manifest.json` (i.e. assets/catalog_seed.manifest.json).
"""
import argparse
import hashlib
import json
import re
import sqlite3
import sys
from pathlib import Path

# PRAGMA user_version of the generated seed. Kept at 3: `retail_price_cents` is
# a nullable additive column, not a breaking schema change.
SCHEMA_VERSION = 3

SCHEMA = """
CREATE TABLE products (
  barcode            TEXT PRIMARY KEY,
  name               TEXT NOT NULL,
  name_ar            TEXT,
  name_en            TEXT,
  category           TEXT,
  photo              BLOB,
  created_at         INTEGER NOT NULL,
  updated_at         INTEGER NOT NULL,
  retail_price_cents INTEGER
);
CREATE INDEX idx_products_name ON products(name);
CREATE INDEX idx_products_category ON products(category);
CREATE TABLE pending_deletes (
  barcode      TEXT PRIMARY KEY,
  deleted_at   INTEGER NOT NULL
);
"""

REPO_ROOT = Path(__file__).resolve().parent.parent
LOADER = REPO_ROOT / "lib" / "data" / "catalog_seed_loader.dart"


def has_column(conn: sqlite3.Connection, table: str, column: str) -> bool:
    """PRAGMA-based check so older server dumps without the new column still work."""
    return any(row[1] == column for row in conn.execute(f"PRAGMA table_info({table})"))


def read_seed_catalog_version(path: Path) -> int:
    """Read `seedCatalogVersion` from the Dart source (host-side, no build)."""
    match = re.search(r"seedCatalogVersion\s*=\s*(\d+)\s*;", path.read_text())
    if not match:
        raise ValueError(f"could not parse seedCatalogVersion from {path}")
    return int(match.group(1))


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Build assets/catalog_seed.db (and its manifest) from a server catalog dump."
    )
    ap.add_argument("server_db", help="path to the server's catalog SQLite DB")
    ap.add_argument("out_db", help="path to write the seed DB (e.g. assets/catalog_seed.db)")
    ap.add_argument("--catalog-version", type=int, default=None,
                    help="catalog generation baked into the seed; defaults to seedCatalogVersion")
    ap.add_argument("--manifest", default=None,
                    help="manifest output path; defaults to <out_db>.manifest.json")
    args = ap.parse_args()

    src, out = args.server_db, args.out_db
    out_path = Path(out)
    manifest_path = Path(args.manifest) if args.manifest else out_path.with_suffix(".manifest.json")
    catalog_version = args.catalog_version if args.catalog_version is not None \
        else read_seed_catalog_version(LOADER)

    if out_path.exists():
        out_path.unlink()

    source = sqlite3.connect(src)
    # Older dumps lack retail_price_cents; project NULL in that case so the
    # generated column is still present and populated as "absent".
    price_expr = "s.retail_price_cents" if has_column(source, "catalog_source", "retail_price_cents") \
        else "NULL AS retail_price_cents"
    rows = source.execute(
        f"""
        SELECT s.barcode, s.name_fr, s.name_ar, s.name_en, s.category,
               p.photo, s.updated_at, {price_expr}
        FROM catalog_source s
        LEFT JOIN catalog_photos p ON p.barcode = s.barcode
        ORDER BY s.barcode
        """
    ).fetchall()

    dst = sqlite3.connect(out_path)
    dst.executescript(SCHEMA)
    dst.executemany(
        "INSERT INTO products "
        "(barcode, name, name_ar, name_en, category, photo, created_at, updated_at, "
        "retail_price_cents) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [(b, n or '', na, ne, c, ph, ts or 0, ts or 0, rpc)
         for b, n, na, ne, c, ph, ts, rpc in rows],
    )
    dst.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")
    dst.commit()

    total = dst.execute("SELECT COUNT(*) FROM products").fetchone()[0]
    with_photo = dst.execute(
        "SELECT COUNT(*), COALESCE(SUM(LENGTH(photo)), 0) FROM products "
        "WHERE photo IS NOT NULL"
    ).fetchone()
    dst.close()
    source.close()

    size = out_path.stat().st_size
    sha = hashlib.sha256(out_path.read_bytes()).hexdigest()
    manifest = {
        "catalog_version": catalog_version,
        "sha256": sha,
        "row_count": total,
        "schema_version": SCHEMA_VERSION,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

    print(f"wrote {out_path}: {total} products, {with_photo[0]} with photos, "
          f"{with_photo[1] / 1024 / 1024:.1f} MB of photos, {size / 1024 / 1024:.1f} MB file")
    print(f"sha256 {sha}")
    print(f"wrote {manifest_path}: catalog_version={catalog_version} row_count={total} "
          f"schema_version={SCHEMA_VERSION}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
