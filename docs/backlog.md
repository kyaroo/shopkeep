# myhanout — Backlog (parked) & done-log

Reconciled 2026-11-15. Estimates: single developer, hours (S ≤2h · M 3–5h · L 8–20h).

## Architecture (locked)
| Store | Scope | Content |
|---|---|---|
| `catalog` | **universal** | barcode, name/ar/en, category, **photo @128px**, `retail_price_cents` |
| `listing` | **per shop** | barcode, `price_cents`, `stock_qty` |

- Shopkeeper carries the whole catalog locally; **browse UI deliberately KEPT** (testing surface).
- Updates: **admin → shopkeeper** `.myhanout` delta (HMAC = QR secret; the catalog is universal → **no shop binding**, any device may apply any signed delta).
- Inventory refresh: **display-only, fills gaps**; never price/stock/name.
- Unknown barcode: capture name + photo at add time, flagged for easy recovery.

## Done this cycle (was parked / in-flight)
| Item | Result |
|---|---|
| C1 `products.photo` (DB v5) | ✅ |
| C3 inventory + form thumbnails | ✅ |
| C4 display helpers | ✅ |
| **C5 / CAT1 image sourcing** | ✅ **13,125 photos, 49.5 MB, avg 3.9 KB** (89.5 %; the other 1,544 verified imageless) |
| CAT5 `.myhanout` format + HMAC | ✅ |
| CAT8 manifest intent filter (both flavors) + receive | ✅ |
| S1/S2/S3 + 418-product scale test | ✅ 418/418, 0 missing, 0 size mismatches |
| **S4 + S5** | ✅ base-version guard (stale delta rejected whole, version advances) + display-only refresh proof (74/74 tests) |
| **Catalog universal** | ✅ `.myhanout` deltas carry **no shop binding** — any device may apply any signed delta (decision 2026-11-15) |
| **CAT2 install-time seed** | ✅ asset **60 MB** (14,669 / 13,125 photos); fresh install verified on device; debug 261 MB · release-arm64 **84.5 MB** |
| **A1–A3 + V2** | ✅ offline isolation: lookups/join/sync gated; release shopkeeper APK grep-clean |

## Open — app
| ID | Item | Est. | Deps |
|---|---|---|---|
| S4 | `Config.catalog_version` + base-version guard (reject stale deltas) | ✅ 2h (S) | — |
| S5 | Prove the refresh fills only missing photos; price/stock untouched | ✅ 1h (S) | S4 |
| CAT2 | Ship the catalog in the APK (install-time seed, **49.5 MB**) | ✅ **8h (L)** | C5 ✅ |
| CAT3b | Flag locally added products for easy recovery | 3h (M) | — |
| CAT6 | Admin: build a delta from a base version + track pushes | 4h (M) | S4 |
| CAT7b | Record `catalog_version` on the shopkeeper after apply | 1h (S) | S4 |
| CAT9 | Admin push-update UI | 4h (M) | CAT6 |
| C2 | Camera/gallery capture in the product form | 4h (M) | — |
| FIX-TESTS | 2 pre-existing failures (`catalog_home_smoke_test`, `widget_test`) | 1h (S) | — |
| COMMIT | Commit the delta/photo/bundle work (currently uncommitted) | 30m | — |

## Open — offline isolation + join
| ID | Item | Est. |
|---|---|---|
| A1 | Gate OFF/UPCitemdb lookups to admin (`CartProvider.lookupProduct`) | ✅ 1h |
| A2 | Drop the join server call (`getShop`) — manual join accepts locally | ✅ 1h |
| A3 | No sync client in the shopkeeper build (`loadSyncConfig` gated) | ✅ 0.5h |
| V2 | Static proof: release shopkeeper APK has **0** hits for openfoodfacts / upcitemdb / mymemory / catalog.myhanout.ma (control strings present) | ✅ 0.5h |
| B5 | ~~Per-shop `shop_id`~~ — **dropped** (catalog updates are universal; no shop binding) | — |
| B4 | QR v2: per-shop lifetime (`ttl_seconds` travels in the token); payload names one `shop_key` | 4h |
| B1,B3,B2,B6 | Listing bundle export/import + upsert + join rework | 18h |
| V1,V2 | Airplane-mode run + APK grep proof | 2h |

## Parked (later features)
| ID | Item | Est. |
|---|---|---|
| G1 | Conflicts alarm on the admin app (review local vs catalog) | 8h (L) |
| G2 | Easy-recovery list/undo for local additions | 4h (M) |
| D1–D4 | Recommended retail price (catalog + server + listing + UI hint) | 10h |
| E1 | Fin de journée: payment method + cash count + closure + share | 16h (L) |
| E2 | Ticket de caisse: UI + WhatsApp share + Bluetooth ESC/POS | 20h (L) |
| E3 | Automatic backup + restore UI | 12h (L) |
| F1/F2 | Per-ABI / release builds | 2h |
| F3 | Catalog-bundle asset packaging — asset **60 MB**; debug APK 261 MB (3 ABI) · release-arm64 **84.7 MB** | ✅ |

## Resolved questions
- ~~Where do the images come from?~~ **Server-side OFF ingest** (13,125; UPCitemdb unreliable).
- ~~Full-coverage size?~~ **49.5 MB**, not 50–58.
- ~~Browse UI in the shopkeeper?~~ **Kept** on both flavors for testing.

## Still open
- D: is the recommended price editable per product in the admin catalog?
- E1: payment methods; per-device closure?
- E2: printer model(s); ticket layout.
- E3: backup destination + retention.
