# myhanout — Backlog & done-log

Reconciled **2026-11-15** against real `git` / `flutter` / `curl` output.
This file is the single source of truth; `backlog-CAT9.md` and
`next-session-plan.md` are superseded (kept for history only).
Estimates: single developer, hours (S ≤2h · M 3–5h · L 8–20h).

> **Pick-up guide for the next session:** `docs/session-plan-next.md`
> (what to read first, the ordered next steps with their gates, and the
> watch-outs carried forward).

## Locked architecture
| Store | Scope | Content |
|---|---|---|
| `catalog` | **universal** | barcode, name/ar/en, category, **photo @128px**, `retail_price_cents` |
| `listing` | **per shop** | barcode, `price_cents`, `stock_qty` |

- Shopkeeper carries the whole catalog locally; **browse UI deliberately KEPT**
  on both flavors (testing surface).
- Updates: **admin → shopkeeper** `.myhanout` catalog delta and `.myhanoutlisting`
  listing bundle, both **Ed25519-signed** by a founder/admin key and verified
  against the signers directory. The catalog is universal → **no shop binding**;
  any device may apply any validly signed delta.
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
  - `flutter test` → **182/182** (phase 2 close-out)
  - Release APKs 2026-11-17 (15:52/15:57): shopkeeper sha256 `7d6106b6…`, admin
    `bb10f725…`, both signed SHA-256 `67c4aaeb…a690` (`apksigner`),
    retired-secret grep 0 hits everywhere
  - `flutter build apk --target-platform android-arm64 --flavor admin --debug` OK
  - Gates: `screens → lib/data/db.dart` = **0** imports; typed client↔UI
    contract; paged inventory (50/page); injected `SettingsService`,
    `CatalogRepository`, `CatalogSyncClientFactory`; `theme.dart` and
    `inventory_screen.dart` split.
- **catalog-server** `/home/hermes/perso/barcode-mapper`, `master` = `a90b563`,
  **no git remote** (local-only by design). `server/app.py` is the whole
  service. Prod container `barcode-mapper-catalog` recreated 2026-11-15.

## Done — phase 2 close-out (2026-11-17)
- **B7** admin listing export (`ListingPushScreen`) — the delivery loop is wired.
- **Device round-trip (VIEW intent)**: `applied 2 row(s)` with both rows landed and the
  unknown barcode flagged `source=listing`; tampered bundle → `rejected: bad-signature`
  with the listing unchanged.
- **Fixed: VIEW intents were silently ignored on a fresh install** (`ShopEntryApp`
  never consumed them) and the intent is now one-shot.
- **Fixed: `readUri` logged cause** instead of collapsing four failures into
  `"unreadable file"`.

## Done — catalog cycle
| Item | Result |
|---|---|
| CAT1–CAT5 | catalog ingest (OFF primary, UPCitemdb gap-fill): **13,125 photos, 49.5 MB, avg 3.9 KB**; seed 60 MB in the APK; install-time seed device-verified |
| CAT6 | server `catalog_version` column + `POST /v1/shops/{key}/catalog-version` |
| CAT7b | shopkeeper records `catalog_version` after apply |
| CAT8 | `.myhanout` intent filter on both flavors + receive |
| CAT9 | admin **« Distribution du catalogue »** screen: shop list, version guard, delta → share, push tracking |
| BUG A | `GET /v1/shops` 500 → fixed (`abb29c6`) |
| BUG B | prod volume predating CAT6 → container recreated; **round-trip verified 2026-11-17 (A3)** |
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
| **B0** | Listing bundle + join rework specification | ✅ 2h (S) | reviewed + committed; blocking B-1 (new-row `name`) fixed, F-1…F-5 corrected. §1.2 resolved by **D10**: the bundle is Ed25519-signed (reopened D2) |
| **B1** | Listing bundle: model, verify, export | ✅ 3h (M) | `myhanout-listing-v1`, founder/admin only, export → verify round-trip |
| **B3** | Listing merge policy | ✅ 2h (S) | price/stock by barcode only, atomic, never deletes, audited, new-row `name` from the catalog |
| **B2** | Listing import service | ✅ 3h (M) | verify **then** bind and merge; a rejected file writes nothing |
| **B6** | Join rework: « Importer la boutique » | ✅ 3h (M) | file picker + `.myhanoutlisting` VIEW intent, routed by extension |
| **Attr** | Attribution UI | ✅ 1h (S) | Settings timeline merging `signer_log` + `audit_log`, newest first |
| **B7** | **Admin listing export UI** — the delivery loop is half-wired | ✅ 2 h (M) | done 2026-11-17 — `ListingPushScreen` (shop picker → signer → signed bundle → share); the admin can now produce a `.myhanoutlisting` |
| **REL-1** | Rebuild both release APKs, then re-run the retired-secret grep | ✅ 1 h (S) | **done 2026-11-17** — `app-shopkeeper-release.apk` sha256 `7d6106b6…` (15:52), `app-admin-release.apk` `bb10f725…` (15:57); grep 0 hits everywhere; both `apksigner`-verified SHA-256 `67c4aaeb…a690` |
| **BUILD-1** | The admin release build intermittently fails (exit 1, ~10 min in) | 30 min (S) | 2 failures / 2 successes on identical code. Not diagnosed — needs the full Gradle log on the next failure. Blocks reliable release builds until understood |
| **OPS-1** | Back up the signer private seeds off the build host | ✅ 15 min (S) | **done 2026-11-17** — seeds (351 B) and keystore (4.4 KB) copied to the Windows Desktop beside the password; all three hash-verifiable |
| **TEST-1** | `inventory_refresh_poc_test` leaks rows in shop `s5-shop` | ✅ 30 min (S) | **done 2026-11-17** — added a `tearDown` mirroring `setUp`; verified the DB file is gone after the run |
| **C2** | Device-verify `content://` end to end | 1 h (S) | **transport proven** — the app read the exact bytes from `content://media/external/downloads/…` on the emulator. **Routing fixed** (`64ac06f`): a `content://` URI carries no extension, so it now routes on the signed payload's `format`. The combined read-and-route run still needs an APK on the device (289 MB Tailscale transfer stalled) |

## Open — server
| ID | Item | Est. | State |
|---|---|---|---|
| **A3** | Prod round-trip verification of `catalog_version` (BUG B closure) | ✅ 1 h (S) | **done 2026-11-17** — `hamidyougo` round-tripped 2 → 3 (POST 200, GET confirmed). Token read from the container's `CATALOG_TOKEN` into an env var, never printed. Note: `hanouti` does not exist on the server; the real shops are `h` and `hamidyougo` |

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
