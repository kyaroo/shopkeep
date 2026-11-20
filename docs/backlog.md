# myhanout — Backlog & done-log

Reconciled **2026-11-20** against real `git` / `flutter` / `curl` output.
This file is the single source of truth; `backlog-CAT9.md`,
`next-session-plan.md` and `docs/session-plan-next.md` are superseded
(kept for history only — `session-plan-next.md` still describes the **old
four-tab** admin IA and must not be followed).
Estimates: single developer, hours (S ≤2h · M 3–5h · L 8–20h).

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
- **Admin shell IA = three tabs: Shops / Catalog / Settings.** Shops is the
  single shop manager (create with contact fields, per-shop menu, join);
  Catalog owns the universal catalog + the sync card; Settings houses the
  catalog/app versions and the signer material. The POS is the **shopkeeper
  flavor** on the salesman's phone — the admin flavor never routes into the POS.

## Mainline (verified 2026-11-20)
- **shopkeeper** `/home/hermes/perso/shopkeeper`, `main` = `395127b` (b9 phase +
  cleanup; committed, **not pushed**; tree clean).
  - `flutter analyze` → **No issues found!**
  - `flutter test` → **244/244**
  - `tool/verify_flavor_gates.sh` → PASS · `tool/verify_catalog_export_gate.sh` → ok
  - Latest artifact: **b9 x64 admin** (`--dart-define=ADMIN=true
    --dart-define=APP_VERSION=0.1.0`, versionCode 9), sha256 `a28a962f…02f88e`,
    installed + launched on `emulator-5555` (`mFocusedApp=com.myhanout.admin`,
    no `FATAL`/`E/flutter` in logcat).
  - **Not rebuilt since b9:** the **arm64 shopkeeper** APK (last kit = b6,
    versionCode 6). `settings_screen.dart` and `catalog_sync_client.dart` are
    shared, so a shopkeeper rebuild is due before the next kit.
  - Gates held: `screens → lib/data/db.dart` = **0** imports; typed client↔UI
    contract; paged inventory (50/page); injected `SettingsService`,
    `CatalogRepository`, `CatalogSyncClientFactory`.
- **catalog-server** `/home/hermes/perso/barcode-mapper`, `master` = `6ccafde`,
  **no git remote** (local-only by design); tree clean. `server/app.py` is the
  whole service.
  - `python3 -m unittest discover -s server/tests -v` → **49/49 OK**
  - Prod `barcode-mapper-catalog` **recreated from the new image** and verified
    live: `health=200`; startup `signers directory v2: 3 signer(s)`;
    `/v1/sync/status` → `role=owner`; `/v1/catalog/version` → 200; `PATCH
    …/info` (own name) → 200; bogus token → 403; shops `hamidyougo` +
    `hanoutihamid` intact. Prod + test on hardened `docker compose`.

## Done — b9 phase (2026-11-20)
- **Admin IA → three tabs** (Shops / Catalog / Settings); the Security tab is
  gone and its signer material moved into Settings.
- **Shops tab is the single shop manager**: the create form now takes business
  name + key + address / city / owner name / phone (contact fields optional,
  non-blocking, forwarded through `ShopProvisioningService.createShop` →
  `registerShop`); per-shop menu = **Shop info / Export listing / Export
  history / Delete**; **« Use this shop » deleted** — it popped the root route
  of an embedded screen and produced the black screen; **Join shop** moved here.
- **Shop info editing**: `ShopInfoScreen` edits the four contact fields for
  **both** roles; `business_name` is editable by the **owner token only**
  (server-enforced) and read-only otherwise, fail-closed while the role is
  unknown. `GET /v1/sync/status` now returns the caller's `role`.
- **Catalog sync card** collapsed to a header row + **one row of three icon
  buttons** (tooltips keep the labels); the status pill probes the
  **authenticated** `GET /v1/catalog/version` → `Token · Server OK` / `Token
  rejected` / `Server unreachable` / `Checking…` / `Token missing` / `Not
  configured`. Owner-only by design: it answers "may this token push the
  catalog", not "is this token valid".
- **Settings tab** = catalog version (+ admin-only Export catalog), app version
  (`const String.fromEnvironment('APP_VERSION')`), signers directory + import.
  Business name / shop management / backup / attribution / about removed from
  the admin body; the **shopkeeper** branch keeps its read-only name and its
  listing/history/restore exports behind `if (!kIsAdmin)`.
- **Server**: `PATCH /v1/shops/{key}/info` accepts `business_name` for the owner
  only (403 salesman) with the **same uniqueness rule as `register_shop`**
  (NOCASE index + strip/casefold pass → 409) and a blank-name guard (400).
- **Build**: `tool/build_release_bundle.sh` passes `--dart-define=APP_VERSION`
  (from pubspec) to both flavors.
- **Tests**: app 234 → **244**; server 43 → **49**; both flavor gates updated
  and green. Commits: app `fa2f5cd`, server `65be883`. Nothing pushed.

## Done — cleanup (2026-11-20)
- **Dead code:** deleted `lib/admin_main.dart` (a second, unused `AdminSetupApp`);
  `lib/admin_home_app.dart` stays (used by `main.dart`, `app_router.dart`, tests).
- **Last direct `SyncConfig.defaultClient()` call site removed** — shop deletion
  in `admin_setup_screen.dart` now goes through the injected `clientFactory`
  (wired from `AdminHomeApp`), matching every other screen/service.
- **arm64 shopkeeper b9 rebuilt** (`--dart-define=APP_VERSION=0.1.0`,
  versionCode 9) — `tool/verify_retired_secrets.sh` → 0 hits, forbidden hosts 0.
  The phone deliverable now matches the admin build.
- **SRV-1 closed:** `server/SIGNER_ROTATION.md` (founder, offline) — build a
  root-signed envelope, ship `signers.json`, restart/recreate, verify the
  fail-closed startup, distribute by QR; linked from `DEPLOY.md`.
- **SRV-3 closed:** prod `CATALOG_PUBLIC_URL` → `https://catalog.myhanout.ma`;
  verified `GET /v1/health` → `{"public_url":"https://catalog.myhanout.ma"}`.
- **Hygiene:** deleted `C:\Users\M\Desktop\myhanout-admin-token.txt`;
  `docs/session-plan-next.md` marked superseded (it describes the old four-tab
  IA); MCP graph re-indexed — `shopkeeper` 2069 nodes / 6413 edges at `395127b`,
  `catalog-server` 639 / 1237 at `6ccafde` (both verified by searching a symbol
  unique to the new commits).
- Commits: app `395127b`, server `6ccafde`.

## Done — earlier phases (condensed)
- **b6 phase (2026-11-18/19):** global monotone catalog generation on the server
  (`catalog_state`, `catalog_changes`), owner-only `/v1/catalog/version` + paged
  `/v1/catalog/diff`; admin pull/publish with version confirmation;
  multi-generation deltas applied atomically; per-shop menu + not-registered
  card; signer import verified against the root-signed directory; Settings tab
  hosts the settings page; server-side signers directory (fail-closed Ed25519);
  prod + test hardened on `docker compose`.
- **Catalog cycle:** CAT1–CAT9 (OFF ingest 13,125 photos / 49.5 MB, install-time
  seed, `catalog_version` column + POST/GET, shopkeeper records the version,
  `.myhanout` intent filter, « Distribution du catalogue » screen); BUG A/B/C;
  B4 QR v2 per-shop TTL; CAT3b `products.source` (**backend only, no UI yet**).
- **Device GUI hardening (2026-11-17):** FIX-1 sale deadlock (sqflite
  transaction queueing), FIX-2 manual barcode entry, FIX-3 truncated names,
  FIX-4 stock-line wrap; release-side `logInfo` outcome log.
- **Delivery loop:** B0–B3, B6, B7 (`ListingPushScreen`, signed
  `.myhanoutlisting`), EXP-1 (three distinctly-named exports, no photos,
  catalog admin-only), C2 (`content://` round-trip on a release build).
- **Housekeeping:** REL-1/REL-2 (release rebuilds + retired-secret grep, kits
  scanned), OPS-1 (signer seeds + keystore off the build host), TEST-1 (test DB
  leak), BUILD-1 (sequential flavor builds — never two Gradle builds at once),
  LINT 74 → 0, A1 (barcode-mapper app dropped), A4/A5/G2, I18N-1, ARCH-1…5,
  offline isolation proven by `HttpOverrides` + release-APK grep.

## Open — app
| ID | Item | Est. | State |
|---|---|---|---|
| **GUI-1** | Sale retry on device + clean up the orphan sales | 30 min (S) | **open, needs the user** — the deadlock fix is installed; the user clicks Caisse → add → « Valider la vente ». The two hung attempts each committed a sale row with **no stock deduction**; either ignore them in Historique or wipe `hanouti` and re-provision the 20 items |
| **TEST-2** | Device GUI smoke pass on a **release** build — make it a release gate | 1 h (S), recurring | **open** — the suite cannot catch device-only defects (FIX-1, FIX-3, FIX-4 all shipped green). Script: cold-launch → apply a signed listing + delta over `content://` → validate a sale (logcat `sale completed: …`) → Inventaire in fr/en/ar → Paramètres → Sauvegarde. Needs the user to click; outcome read from logcat |
| **GUI-3** | GUI test session for the **b9** IA | ~1 h (S), needs the user | **open, re-scoped 2026-11-20** — covers the **three tabs** (Shops/Catalog/Settings), the create form with contact fields, the per-shop menu, the icon-only sync card + pill, the shopkeeper flavor gate (no Shop info / no signer surface). Emulator needs an x64 admin build; the physical device needs an arm64 shopkeeper installed (MIUI: Install via USB). No assistant vision |

## Open — server
**None.** SRV-1 and SRV-3 were closed 2026-11-20 — see "Done — cleanup".

## Parked (not now — decisions 2026-11-15 / 2026-11-19)
- **SRV-2** server serves the signers directory (owner-only `GET`) so devices can
  pull it — decided "later"; devices get the roster from the APK asset or QR.
- **5(ii)** signer-key-minted short-lived sync token (challenge-response) — the
  manual token stays; the server-side directory (its prerequisite) now exists.
- **C2** photo capture in the *shopkeeper* product form (already in the admin
  catalog UI via `CaptureDialog`).
- **C** POS features: E1 clôture de caisse (16 h) · D1–D4 prix conseillé (10 h) ·
  E2 ticket + imprimante (20 h) · E3 backup auto (12 h) · G1 conflits (8 h).
- **F1/F2** per-ABI / release build matrix.

## Resolved questions
- **Admin IA (2026-11-20):** three tabs Shops/Catalog/Settings; Settings houses
  only the versions + signer material; the Security tab is removed; business
  name / attribution / backup leave the admin Settings. The catalog never mixes
  with a shop's individual listing — catalog export/restore stays on Catalog,
  listing/history export is per-shop.
- **Shop data (2026-11-20):** the four contact fields are collected at creation
  (non-blocking) and editable afterwards; `business_name` is owner-token-only;
  the salesman and the owner may both edit the contact fields.
- **POS (2026-11-20):** the salesman uses the **shopkeeper flavor** on his phone;
  the admin flavor does not route into the POS.
- **App version (2026-11-20):** compile-time `--dart-define=APP_VERSION` from
  pubspec; no plugin.
- **Sync status (2026-11-20):** the pill probes `/v1/catalog/version`
  (owner-only, catalog-related) — a valid salesman token reads "Token rejected"
  there by design; `/v1/sync/status` is the any-role route and carries `role`.
- **Signer directory (2026-11-19):** the server holds a static copy of the
  root-signed roster, rotated manually by the founder (offline), verified at
  startup (fail-closed). The sync token stays a **manual** shared secret.
- **iOS: dropped (2026-11-19).** Android-only.
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
  `admin_setup_screen` (shop deletion); the other screens/services take an
  injected `clientFactory`. Make the shop-deletion path injectable too.
- **An embedded screen must not `Navigator.pop()` unconditionally** — it pops
  the shell's only route and blacks the screen (this was « Use this shop »).
- **An owner-only route answers 403 for a *valid* salesman token.** Label it as
  "may push the catalog", or probe an any-role route.
- **The app version needs `--dart-define=APP_VERSION`** on every build; without
  it the Settings row reads `dev`.
- **A green suite does not mean the app works.** FIX-1 (every sale hung) and
  FIX-3 (truncated names) both shipped green: `sqflite_common_ffi` does not
  reproduce the Android plugin's per-database queueing, and no test rendered a
  row. Keep clicking the app on a **release** build.
- **`uiautomator` exposes no Flutter text** on this app (release *or* debug).
  GUI verification is human, or via logcat (`logInfo`) — never blind tapping.
- **APK transfer to the Windows host:** the Tailscale link stalls above
  ~260 MB. Split into 15 MB chunks, `copy /b` them together, verify the sha256
  on both ends, then install. The Windows adb daemon dies per SSH session —
  chain `adb connect 127.0.0.1:5555 && adb -s 127.0.0.1:5555 …` in one call.
- **The emulator camera is `hw.camera.back = emulated`**, so the scanner cannot
  be driven with a poster without restarting the AVD.
- **A `kIsAdmin` gate cannot be tested** — it is a compile-time const. Guard such
  gates at the source (`tool/verify_catalog_export_gate.sh`) and check the
  closing bracket of an `if (kIsAdmin) ...[` spread by eye.
- **Commit messages:** repeated `-m` flags; a heredoc is on the user's
  denied-command list.
- **Both compose files share project `server`** → each reports the other as an
  orphan; never `down --remove-orphans` on one.
- **`app.py` is baked into the image** (no bind mount) → code changes need
  `docker compose build` + `up -d`, not a restart.
- **`release/` is git-ignored** (812 MB of APKs; reproducible from source).
- **The test volume can go root-owned** → `attempt to write a readonly database`;
  fix with `docker exec -u root barcode-mapper-catalog-test chown -R 10001:999 /data`.
- **Never run two Flutter/Gradle builds concurrently** (daemon crash).
- **Code-graph MCP slugs:** `shopkeeper` and `catalog-server` are the fresh ones;
  re-index after a large change — the long-name duplicates are stale.
