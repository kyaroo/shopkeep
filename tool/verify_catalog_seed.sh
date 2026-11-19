#!/usr/bin/env bash
# Verify the bundled catalog seed matches its manifest and the app's baked-in
# version constant before a release kit is assembled.
#
# A seed manifest is a small JSON object:
#   { "catalog_version": 3, "sha256": "<hex>", "row_count": <int>,
#     "schema_version": <int> }
#
# The gate fails unless ALL of the following hold:
#   * lib/data/catalog_seed_loader.dart's `seedCatalogVersion` == manifest's
#     catalog_version (else an installed seed adopts the wrong base version and
#     every founder-signed delta is rejected by the base-version guard);
#   * the SHA-256 of assets/catalog_seed.db == manifest's sha256 (integrity);
#   * the products row count and PRAGMA user_version match the manifest;
#   * the DB actually carries the nullable `retail_price_cents` column.
#
# Run: bash tool/verify_catalog_seed.sh [manifest.json]
# Default manifest: assets/catalog_seed.manifest.json (emitted by the builder).
set -euo pipefail
cd "$(dirname "$0")/.."

MANIFEST="${1:-assets/catalog_seed.manifest.json}"
DB="assets/catalog_seed.db"
LOADER="lib/data/catalog_seed_loader.dart"

if [ ! -f "$MANIFEST" ]; then
  echo "FAIL: seed manifest not found: $MANIFEST" >&2
  echo "  generate one with tool/build_catalog_seed_with_photos.py" >&2
  exit 1
fi
if [ ! -f "$DB" ]; then
  echo "FAIL: seed DB not found: $DB" >&2
  exit 1
fi
if [ ! -f "$LOADER" ]; then
  echo "FAIL: loader source not found: $LOADER" >&2
  exit 1
fi

python3 - "$MANIFEST" "$DB" "$LOADER" <<'PY'
import hashlib
import json
import re
import sqlite3
import sys

manifest_path, db_path, loader_path = sys.argv[1], sys.argv[2], sys.argv[3]
failures = []

with open(manifest_path, encoding="utf-8") as fh:
    manifest = json.load(fh)

for key in ("catalog_version", "sha256", "row_count", "schema_version"):
    if key not in manifest:
        failures.append(f"manifest is missing required field: {key}")

# Read the compile-time constant straight from the Dart source (no Flutter build).
loader_text = open(loader_path, encoding="utf-8").read()
match = re.search(r"seedCatalogVersion\s*=\s*(\d+)\s*;", loader_text)
const_version = int(match.group(1)) if match else None
if const_version is None:
    failures.append(f"could not parse seedCatalogVersion from {loader_path}")

# Facts read directly from the shipped DB.
actual_sha = hashlib.sha256(open(db_path, "rb").read()).hexdigest()
conn = sqlite3.connect(db_path)
actual_rows = conn.execute("SELECT COUNT(*) FROM products").fetchone()[0]
actual_schema = conn.execute("PRAGMA user_version").fetchone()[0]
columns = {row[1] for row in conn.execute("PRAGMA table_info(products)")}
conn.close()

def check(name, ok, detail):
    print(f"{'ok' if ok else 'FAIL'}: {name} — {detail}")
    if not ok:
        failures.append(f"{name}: {detail}")

if const_version is not None:
    check("const == manifest catalog_version",
          manifest.get("catalog_version") == const_version,
          f"loader={const_version} manifest={manifest.get('catalog_version')}")
check("DB sha256 == manifest sha256",
      str(manifest.get("sha256", "")).lower() == actual_sha,
      f"db={actual_sha} manifest={manifest.get('sha256')}")
check("row_count == manifest row_count",
      manifest.get("row_count") == actual_rows,
      f"db={actual_rows} manifest={manifest.get('row_count')}")
check("schema_version == manifest schema_version",
      manifest.get("schema_version") == actual_schema,
      f"db={actual_schema} manifest={manifest.get('schema_version')}")
check("products has retail_price_cents",
      "retail_price_cents" in columns,
      "column present" if "retail_price_cents" in columns else "missing; regenerate the seed")

if failures:
    print("\ncatalog seed verification FAILED", file=sys.stderr)
    for item in failures:
        print(f"  - {item}", file=sys.stderr)
    sys.exit(1)
print("\ncatalog seed verification OK")
PY
