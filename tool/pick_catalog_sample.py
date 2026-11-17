#!/usr/bin/env python3
"""Picks N random catalog products that actually have a photo.

Writes two files:
  <out.json>          the export `tool/make_catalog_delta.dart` consumes
                      (barcode, name, name_ar, name_en, category, photo_base64)
  <out_rows.json>     the listing rows `tool/make_listing_bundle.dart` consumes
                      (barcode, price_cents, stock_qty)

Random with `ORDER BY RANDOM()` on purpose: an alphabetical pick would sample
the zero-padded junk at the front of the barcode space.

Usage:
  python3 tool/pick_catalog_sample.py [db] [n] [out-dir]
"""
import base64
import json
import sqlite3
import sys
from pathlib import Path

db = sys.argv[1] if len(sys.argv) > 1 else "assets/catalog_seed.db"
n = int(sys.argv[2]) if len(sys.argv) > 2 else 20
out_dir = Path(sys.argv[3] if len(sys.argv) > 3 else "scratch")

con = sqlite3.connect(db)
rows = con.execute(
    "SELECT barcode, name, name_ar, name_en, category, photo, created_at, updated_at "
    "FROM products WHERE photo IS NOT NULL ORDER BY RANDOM() LIMIT ?",
    (n,),
).fetchall()
con.close()

if not rows:
    sys.exit("no products with a photo found")

out_dir.mkdir(parents=True, exist_ok=True)

catalog_rows = []
listing_rows = []
for i, (barcode, name, name_ar, name_en, category, photo, created_at, updated_at) in enumerate(rows):
    catalog_rows.append({
        "barcode": barcode,
        "name": name,
        "name_ar": name_ar,
        "name_en": name_en,
        "category": category,
        "photo_base64": base64.b64encode(photo).decode(),
        "created_at": created_at,
        "updated_at": updated_at,
    })
    # Deterministic, plausible listing values derived from the pick order.
    listing_rows.append({
        "barcode": barcode,
        "price_cents": 95 + ((i * 137) % 1900),
        "stock_qty": (i * 7) % 15,
    })

(out_dir / "catalog_sample.json").write_text(
    json.dumps(catalog_rows, ensure_ascii=False), encoding="utf-8")
(out_dir / "listing_rows.json").write_text(
    json.dumps(listing_rows, ensure_ascii=False), encoding="utf-8")

photo_kb = sum(len(r["photo_base64"]) for r in catalog_rows) // 1024
print(f"picked {len(catalog_rows)} products with photos "
      f"({photo_kb} KB of base64) -> {out_dir}")
for r in listing_rows:
    print(f"  {r['barcode']}  {r['price_cents']} c  stock {r['stock_qty']}")
