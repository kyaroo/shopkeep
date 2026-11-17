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
  - `flutter test` → **187/187** (device GUI hardening close-out)
  - Release APKs 2026-11-17 (15:52/15:57): shopkeeper sha256 `7d6106b6…`, admin
    `bb10f725…`, both signed SHA-256 `67c4aaeb…a690` (`apksigner`),
    retired-secret grep 0 hits everywhere **— these predate the device fixes
    below; see REL-2**
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

## Done — device GUI hardening (2026-11-17)
Exercised on the emulator on a **release** x64 build. Four real defects found
by clicking the app, none of which the suite could have caught.

| ID | Defect | Root cause | Fix |
|---|---|---|---|
| **FIX-1** | **Every sale hung forever** — « Valider la vente » did nothing | `deductStock` wrote its audit rows through the top-level handle *inside* `db.transaction((txn) …)`; sqflite queues that write behind its own transaction → permanent deadlock. Only symptom: `Warning database has been locked for 0:00:10` | `Audit.log` takes the executor; `deductStock` and `import_export` pass `txn`. Guard test reproduces the hang (reverting the fix times it out at 180 s) |
| **FIX-2** | No way to type a barcode | `ScanPage` had no manual entry; the emulator camera is `emulated`, so the cart could not be filled by hand | `ManualBarcodeEntry` overlay; pops the raw string exactly like a camera detection, so `scanToAdd`/lookup are untouched |
| **FIX-3** | **Name truncated** on photo-less rows | `leading` was a fixed 44×44 photo but an intrinsically-sized `StockBadge` (87 px in fr) → the name's column collapsed 311 → 53 px | `InventoryThumb`, fixed 44×44 in both cases |
| **FIX-4** | Stock line wrapped in fr/en | Badge moved to the subtitle measured 85 px against a 199 px line | Badge icon-only in that row (28 px chip, label in `Semantics` + tooltip); barcode off the line; short stock labels |

Supporting work: release-side outcome log (`logInfo` → logcat) because a
release build cannot be inspected with `run-as`; `tool/make_catalog_delta.dart`
arg-check bug (the tool could never run); `tool/pick_catalog_sample.py`.

**Device state:** shop `hanouti`, catalog → 2, 22 products (20 with real
photos), applied over `content://` from signed artifacts.

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
| **BUILD-1** | The admin release build intermittently fails (exit 1, ~10 min in) | 30 min (S) | **not reproduced** — 3/3 admin-only builds succeeded on 2026-11-17. Both earlier failures happened when admin ran *immediately after* shopkeeper in the same invocation, which is the remaining hypothesis. Workaround until proven: build the two flavors in separate invocations |
| **OPS-1** | Back up the signer private seeds off the build host | ✅ 15 min (S) | **done 2026-11-17** — seeds (351 B) and keystore (4.4 KB) copied to the Windows Desktop beside the password; all three hash-verifiable |
| **TEST-1** | `inventory_refresh_poc_test` leaks rows in shop `s5-shop` | ✅ 30 min (S) | **done 2026-11-17** — added a `tearDown` mirroring `setUp`; verified the DB file is gone after the run |
| **C2** | Device-verify `content://` end to end | ✅ 1 h (S) | **done 2026-11-17** — on a **release** x64 build over `content://media/external/downloads/…`: `listing applied: 2 new, 0 changed, 0 identical (shop hanouti)`, and the tampered bundle → `listing rejected: bad-signature`. Needed a release-side outcome log because a release build cannot be inspected with `run-as` |
| **REL-2** | Rebuild both release APKs after the device fixes, then re-run the retired-secret grep | 1 h (S) | **open** — the signed artifacts from 15:52/15:57 predate FIX-1…FIX-4. Build the flavors **in separate invocations** (see BUILD-1), then `tool/verify_retired_secrets.sh` and `apksigner verify --print-certs` on the **artifacts** |
| **GUI-1** | Sale retry on device + clean up the orphan sales | 30 min (S) | **open, needs the user** — the deadlock fix is installed; the user clicks Caisse → add → Valider la vente. The two hung attempts each committed a sale row with **no stock deduction** (insertSale commits first); either ignore them in Historique or wipe `hanouti` and re-provision the 20 items |
| **I18N-1** | Arabic `stockQty` wording | ✅ 5 min (S) | **done 2026-11-17** — `الكمية في المخزون` → `مخزون`; forced by the 199 px subtitle budget. **Flagged to the user**: they may prefer the original wording and accept a tighter Arabic line |

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
- **The shopkeeper flavor must make zero HTTP requests.** Proven by
  `HttpOverrides` in `security_regression_test.dart` and by the release-APK
  grep. Both must stay green.
- **A green suite does not mean the app works.** FIX-1 (every sale hung) and
  FIX-3 (truncated names) both shipped with 182/182 green: `sqflite_common_ffi`
  does not reproduce the Android plugin's per-database queueing, and no test
  rendered a row. Keep clicking the app on a **release** build.
- **`uiautomator` exposes no Flutter text** on this app (release *or* debug),
  even with an accessibility service enabled. GUI verification is human, or
  via logcat (`logInfo`) — never blind coordinate tapping.
- **APK transfer to the Windows host:** the Tailscale link stalls above
  ~260 MB. Split into 15 MB chunks, `copy /b` them together, verify the sha256
  on both ends, then install.
- **The emulator camera is `hw.camera.back = emulated`**, not `virtualscene`,
  so the scanner cannot be driven with a poster without restarting the AVD.
- **Commit messages:** repeated `-m` flags; a heredoc is on the user's
  denied-command list.
