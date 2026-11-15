# Next-session plan — myhanout catalog & photos

> **SUPERSEDED 2026-11-15** — S4/S5 are delivered and the catalog cycle is
> closed. Current state lives in `docs/backlog.md`. Kept for history only.


Prepared 2026-11-14 (evening). Supersedes the 2026-11-12 version.

## 1. Where we are

**POC (shopkeeper-centered) — S1/S2/S3 done and device-verified:**

| Step | Status | Evidence |
|---|---|---|
| S1 shopkeeper applies a `.myhanout` delta offline | ✅ | barcode 6111035001673, photo 3,835 B, md5 identical |
| S2 unknown barcode resolves from the LOCAL catalog (name + photo) | ✅ | add-form prefilled; product saved with its photo |
| S3 catalog photo renders in the Browse catalog | ✅ | `browseLocal` → `photo_base64`, `_Thumb` → `Image.memory`; pixel-verified |
| **S4 second delta on top + `catalog_version` advances** | ⏳ | needs `Config.catalog_version` + a base-version guard |
| **S5 listing safety + gap-only refresh** | ⏳ | code present (DB v6 + `applyCatalogPhoto`); needs a product with no photo |
| S6 browse-catalog UI | ✅ kept | deliberate testing surface on **both** flavors |

**Scale test:** 418-product delta → **418/418 applied, 0 missing, 0 size mismatches**, 1.58 MB.

**Image ingest (runs on this host):** pilot **86.5 % coverage**, avg **3.87 KB**.
Overnight job **running** since 18:02 UTC — log `/var/tmp/ingest_images.log`,
status `/var/tmp/ingest_images.status`; 9 h time box (~03:02 UTC), writes `STALLED`
after 3 no-progress passes. Prod table only (`catalog_photos`); fully resumable.

## 2. Locked decisions
- Catalog **universal** (info + photo @128px); listing **per shop** (price/stock).
- Shopkeeper: whole catalog local, zero network; browse kept for now.
- Updates: admin → shopkeeper `.myhanout` **delta** (HMAC = QR secret, bound to
  `shop_id` + `shop_key`), opened through an Android intent filter (**both flavors**).
- Version = `updated_at` (epoch ms); admin tracks pushes + `last_catalog_updated_at`.
- Inventory refresh: **display-only, fills gaps** (`photo IS NULL`); never price/stock/name.
- Images: full coverage @128px/q60; OFF primary, UPCitemdb trial gap-fill; ingest on the server.

## 3. Next (ordered)
1. Read the overnight status → coverage / avg KB / total MB; re-run if it time-boxed.
2. **S4/S5**: `Config.catalog_version` + base-version guard; build; push delta #2;
   verify the inventory photo fills **only** where missing and price/stock stay put.
3. **CAT1** full-scale ingest → **CAT2** ship the catalog in the APK.
4. **A** offline isolation (a1–a3) · **B** listing bundle + join (b1–b6) · **V** verification.

## 4. Parked (see `docs/backlog.md`)
- **G1** conflicts alarm · **G2** easy-recovery flag
- **C1–C4** POS photo capture/thumbnails · **D1–D4** recommended retail price
- **E1–E3** daily closure, receipt/print, auto-backup · **F1/F2** per-ABI/release builds

## 5. State / artifacts
- Device `emulator-5554` on the Windows box — **must run in the console session**
  (launcher: `scripts/launch_emu_interactive.ps1` in the `shopkeeper-development` skill).
- Shopkeeper app: catalog has **419 photos**; inventory holds the Aïn Atlas product
  (price 450, stock 0, `photo_source=catalog`).
- Admin app on device: older build (no photo column); its catalog has **no** photos.
- Repos: `perso/shopkeeper`, `perso/barcode-mapper`.
- Docs: `docs/backlog.md`, `barcode-mapper/server/IMAGE_INGEST.md`, this file.
- **Uncommitted app work:** catalog-delta service, `.myhanout` receiver + manifest,
  `products.photo` (v5), `photo_source` (v6), gap-only refresh, browse/inventory photo
  rendering, POC tests + tools (`make_catalog_delta.dart`, `export_catalog_photos.py`).

## 6. Numbers
| | |
|---|---|
| Image @128px/q60 | 3.87 KB avg (spread <2 KB … 8 KB, none over) |
| Delta, 1 product | 6,115 B |
| Delta, 418 products | 2.3 MB |
| Full catalog (86.5 % of 14,669) | ≈ 12,700 photos ≈ **49 MB** |
| Ingest rate | 2–6.6 s/product → full run 7–18 h (overnight, resumable) |

## 7. Watch-outs
- Never trust a `LIMIT` pilot taken in barcode order — use `SAMPLE=1` (17 % vs 86.5 %).
- 429 = throttling, not "no image"; retry with backoff.
- `adb shell run-as cat` corrupts binaries — use `adb exec-out`.
- A flavor rebuild does not reach the device until you `adb install -r` that flavor.
- `tool/*.dart` must stay Flutter-free or `dart run` fails to compile plugins.
