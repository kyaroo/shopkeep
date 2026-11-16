# myhanout — Backlog & done-log

Reconciled **2026-11-15** against real `git` / `flutter` / `curl` output.
This file is the single source of truth; `backlog-CAT9.md` and
`next-session-plan.md` are superseded (kept for history only).
Estimates: single developer, hours (S ≤2h · M 3–5h · L 8–20h).

## Locked architecture
| Store | Scope | Content |
|---|---|---|
| `catalog` | **universal** | barcode, name/ar/en, category, **photo @128px**, `retail_price_cents` |
| `listing` | **per shop** | barcode, `price_cents`, `stock_qty` |

- Shopkeeper carries the whole catalog locally; **browse UI deliberately KEPT**
  on both flavors (testing surface).
- Updates: **admin → shopkeeper** `.myhanout` delta, HMAC = QR secret. The
  catalog is universal → **no shop binding**; any device may apply any signed
  delta.
- Delivery is a **manual file** (WhatsApp / Android share). Shopkeeper stays
  **100 % offline** — no HTTP push.
- Inventory refresh: **display-only, fills gaps**; never price/stock/name.
- Unknown barcode: capture name + photo at add time, flagged for recovery.
- Version = **monotone counter 1, 2, 3…** (seed = 1). The server is the source
  of truth; the shopkeeper keeps a local copy.

## Mainline (verified)
- **shopkeeper** `/home/hermes/perso/shopkeeper`, `main` pushed to
  `github.com:kyaroo/shopkeep.git`, 0 ahead.
  - `flutter analyze` → **No issues found!**
  - `flutter test` → **126/126**
  - `flutter build apk --target-platform android-arm64 --flavor admin --debug` OK
  - Gates: `screens → lib/data/db.dart` = **0** imports; typed client↔UI
    contract; paged inventory (50/page); injected `SettingsService`,
    `CatalogRepository`, `CatalogSyncClientFactory`; `theme.dart` and
    `inventory_screen.dart` split.
- **catalog-server** `/home/hermes/perso/barcode-mapper`, `master` = `a90b563`,
  **no git remote** (local-only by design). `server/app.py` is the whole
  service. Prod container `barcode-mapper-catalog` recreated 2026-11-15.

## Done — catalog cycle
| Item | Result |
|---|---|
| CAT1–CAT5 | catalog ingest (OFF primary, UPCitemdb gap-fill): **13,125 photos, 49.5 MB, avg 3.9 KB**; seed 60 MB in the APK; install-time seed device-verified |
| CAT6 | server `catalog_version` column + `POST /v1/shops/{key}/catalog-version` |
| CAT7b | shopkeeper records `catalog_version` after apply |
| CAT8 | `.myhanout` intent filter on both flavors + receive |
| CAT9 | admin **« Distribution du catalogue »** screen: shop list, version guard, delta → share, push tracking |
| BUG A | `GET /v1/shops` 500 → fixed (`abb29c6`) |
| BUG B | prod volume predating CAT6 → container recreated; **round-trip still to verify** (A3) |
| BUG C | delta photo budget enforced client-side (50 KB) |
| B4 | QR v2: per-shop TTL (`ttl_seconds` in the signed token), clock-skew guard |
| CAT3b | `products.source` provenance flag (DB v7) — **backend only, no UI yet** |
| ARCH-1…5 | screens never open the DB; DI; typed contract; paged inventory; file splits |
| LINT | 74 → 0 analyzer findings; `lib/utils/app_log.dart` for structured logging |
| A1 | barcode-mapper Flutter app dropped from the tree (`8c1ace1`, `a90b563`) |
| **A4** | server hardening (`7d92524`): constant-time token compare, photo cap 64→50 KB, `server/tests/` 13 tests green |
| **A5 / G2** | local-add recovery (`f1468cf`): filter chip + per-row undo, i18n fr/en/ar, 7 tests; analyze 0, 126/126, APK built |
| Offline isolation | lookups/join/sync gated; release shopkeeper APK grep-clean |

## Open — app
| ID | Item | Est. | State |
|---|---|---|---|
| **B0** | Listing bundle + join rework specification | ✅ 2h (S) | **reviewed + committed** — blocking B-1 (new-row `name`) fixed, F-1…F-5 corrected; §1.2 no-HMAC left **open** |
| **B1/B3/B2/B6** | Listing bundle export/import + upsert + join rework | 18 h (L) | after B0 is committed |

## Open — server
| ID | Item | Est. | State |
|---|---|---|---|
| **A3** | Prod round-trip verification of `catalog_version` (BUG B closure) | 1 h (S) | **blocked on the prod bearer token**; run after the prod redeploy |

## Parked (not now — decision 2026-11-15)
- **C2** photo capture in the *shopkeeper* product form (already in the admin
  catalog UI via `CaptureDialog`).
- **C** POS features: E1 clôture de caisse (16 h) · D1–D4 prix conseillé (10 h) ·
  E2 ticket + imprimante (20 h) · E3 backup auto (12 h) · G1 conflits (8 h).
- **F1/F2** per-ABI / release build matrix.

## Resolved questions
- Version scheme: **monotone counter**, not epoch ms.
- Delivery: **manual `.myhanout`**, not HTTP — offline lock.
- One shop per push; screen named « Distribution du catalogue » (no network).
- `PushTracker` in memory in v1 (prod → SQLite later).
- Images: server-side OFF ingest; 49.5 MB, not 50–58.
- Browse UI kept on both flavors.

## Watch-outs
- Never `const Text('…'.tr())`; `intl` shadows `TextDirection` →
  `import 'dart:ui' as ui` + `ui.TextDirection.rtl`.
- `businessName` is never translated.
- The delta is **universal** — never bind it to a shop.
- Shopkeeper must have zero network code outside `kIsAdmin`.
- `assets/catalog_seed.db` is 60 MB — above the 50 MB recommendation.
- `SyncConfig.defaultClient()` is still called directly in
  `admin_setup_screen` (shop deletion) — last locator of its kind.
