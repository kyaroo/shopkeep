#!/usr/bin/env python3
"""Export catalog_photos (+ names from catalog_source) as JSON for the
`.myhanout` delta builder.

Usage:
    python3 tool/export_catalog_photos.py <db> <out.json> [limit]
"""
import base64
import json
import sqlite3
import sys


def main() -> int:
    db, out = sys.argv[1], sys.argv[2]
    limit = int(sys.argv[3]) if len(sys.argv) > 3 else 0

    conn = sqlite3.connect(db)
    rows = conn.execute(
        """
        SELECT p.barcode, s.name_fr, s.name_ar, s.name_en, s.category, p.photo
        FROM catalog_photos p
        JOIN catalog_source s ON s.barcode = p.barcode
        ORDER BY p.barcode
        """
    ).fetchall()
    if limit > 0:
        rows = rows[:limit]

    payload = [
        {
            "barcode": barcode,
            "name": name_fr or "",
            "name_ar": name_ar,
            "name_en": name_en,
            "category": category,
            "photo_base64": base64.b64encode(photo).decode() if photo else None,
        }
        for barcode, name_fr, name_ar, name_en, category, photo in rows
    ]
    with open(out, "w") as fh:
        json.dump(payload, fh)
    print(f"exported {len(payload)} products -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
