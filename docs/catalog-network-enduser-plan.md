# Implementation Plan: Hybrid Networkless-First Catalog for End-User (Shopkeeper) Flavor

> Implementation status (2026-10-23): seed-only shipped in commit 2f112aa (asset + bootstrap + local browse/prefill). Network refresh and settings catalog card are deferred.

Investigation/plan only. No code modified. Baseline: `flutter test` green (47 tests).

## Goal
Ship the shopkeeper flavor with a **bundled read-only catalog seed** (`catalog_seed.db`,
~14,669 OFF-derived products) as a Flutter asset so end users get full offline
search and prefill with **zero data usage**. Network access becomes strictly
optional via a manual **"Refresh catalog"** action that pulls a delta from the
tailnet server (`CatalogSyncClient.search` / `resolve`) and merges it into the
local `catalog.db`. Reuse `CatalogDb`, `CatalogProvider`, `CatalogSyncClient`,
`SyncConfig`. End users remain read-only; no server changes; tailnet-only.

## Current State
- Admin flavor owns the network side: `CatalogDb`, `CatalogProvider`,
  `CatalogSyncClient` (resolve/search/push), `SyncConfig`, and screens
  `CatalogHomePage`, `BrowsePage`, `CaptureDialog`, `SyncSettingsDialog`.
- End-user flavor is POS-only: per-shop `Db` (products with price/stock),
  `CartProvider`, `ProductFormDialog` with OFF-only `lookupProduct`.
- Shared code exists but is not wired into the shopkeeper `main.dart`.
- Server read API (`/v1/products/search`, `/v1/products/{barcode}`) is
  read-only, ungated by `CATALOG_OPEN`, and returns lean merged rows
  (owner overrides win). `search` supports `q`, `category`, `limit` (<=100),
  `offset` and returns `{total, limit, offset, products:[...]}`.
- No bundled seed asset exists yet; `assets/` contains only `lang/` and fonts.

## Assumptions
1. End users are **read-only** consumers of the catalog; they never push or
   edit catalog entries (founder/admin owns authoring). The end-user flavor
   must not expose `CatalogProvider.syncNow` (push) or capture/edit screens.
2. Catalog server is reachable only on the tailnet; client config (URL +
   bearer token) lives in `SyncConfig` (SharedPreferences).
3. `catalog.db` (local, writable, holds seed + refresh deltas) is a separate
   file from per-shop DBs and coexists on the same device.
4. Product model has no category field; catalog category is informational for
   prefill only (name/barcode). Do not change `Product` schema.
5. Seed is a **bootstrap only**: it is copied to `catalog.db` only when
   `catalog.db` does not yet exist. Refreshes are never clobbered by a newer
   bundled seed; updates arrive via "Refresh catalog".
6. Base flows (search, browse, scan prefill) use **zero network**. Network is
   touched only by the explicit refresh action and by the optional resolve
   fallback on a local miss (when configured).

## Architecture Decisions
- **Local-first, read-only seed.** `CatalogDb` is the single source of truth
  for end-user search/prefill. The bundled seed makes it populated on day one.
- **Seed bootstrap inside `CatalogDb.init()`** (best-effort, single-flight).
  If the asset or Flutter binding is unavailable (tests, corrupt file), init
  falls back to the existing empty-DB `onCreate` path. No test changes required
  to keep the 47 green.
- **No auto-sync.** No background refresh, no push. Refresh is a manual button.
- **Reuse, don't fork.** Add only read-only helpers and pull/merge logic:
  `CatalogProvider.configured`, `browseLocal`, `refreshFromServer`,
  `CatalogDb` pagination/count-by-search, `SyncConfig.lastCatalogRefreshAt`.
- **Admin-only surfaces stay gated** by `kIsAdmin` in the UI; end-user UI
  shows only read-only browse/picker and refresh.
- **Pagination for local browse.** `catalog_source` scale (~14,669 rows) means
  `BrowsePage` must page the local SQL query (default 50) instead of loading
  all rows into memory.

## Seed Asset Handling

### File and registration
- Asset path: `assets/catalog_seed.db` (lean SQLite, schema v3, no photos,
  no `pending_deletes`).
- Register in `pubspec.yaml`:
  ```yaml
  flutter:
    assets:
      - assets/lang/
      - assets/catalog_seed.db
  ```
- Size budget: ~14,669 rows * lean fields ≈ 2–5 MB uncompressed. If the
  shipped APK budget is tight, gzip the asset to `catalog_seed.db.gz` and
  decompress on first copy (optional; default raw for simplicity).

### Schema / build-time generation
- Seed must match `CatalogDb` schema v3 (`products` table with `name_ar`,
  `name_en`, indexes `idx_products_name`, `idx_products_category`) and
  `PRAGMA user_version = 3` so `openDatabase` neither recreates nor
  "upgrades" it.
- `pending_deletes` table may be absent in the seed; `CatalogDb.onUpgrade`
  only adds it for pre-v2 DBs, and end users never delete catalog rows, so
  absence is acceptable. To be safe, include an empty `pending_deletes` table.
- New build script `tools/build_catalog_seed.py` (run by maintainer, not on
  device):
  1. Read server DB (`CATALOG_DB`, default `/data/catalog.db`) or, for
     guaranteed API parity, paginate `GET /v1/products/search` on the tailnet.
  2. Apply owner-overrides (owner `products` win over `catalog_source`,
     mirroring `_resolve_row`).
  3. Create `assets/catalog_seed.db` with the v3 schema, insert rows
     (`name`, `name_ar`, `name_en`, `category`, `created_at`, `updated_at`;
     `updated_at` preserved for client-side delta merge), build indexes,
     set `user_version=3`.
  4. Run `PRAGMA quick_check` and print the row count (target ~14,669).

### Runtime bootstrap (first launch only)
- `CatalogSeedLoader.ensureSeeded(dbPath)`:
  - If `File(dbPath).existsSync()` → return (never clobber refreshes).
  - Try `rootBundle.load('assets/catalog_seed.db')`; on any failure (no
    binding, asset missing, corrupt) → return silently and let `CatalogDb`
    create an empty DB via `onCreate`.
  - Write bytes to `$dbPath.tmp`, run `PRAGMA quick_check`; on success rename
    to `dbPath`, on failure delete tmp and return.
- `CatalogDb.init()` becomes single-flight (`_initFuture`) and calls
  `ensureSeeded` before `openDatabase`. Eager vs lazy is configurable; default
  **lazy** (first use) to protect cold start, matching the original plan.
- Concurrency: single-flight guard prevents double copy when multiple callers
  invoke `init()` simultaneously.

### Asset/versioning notes
- A newer app build may ship a newer seed, but an existing `catalog.db` is
  never overwritten. New/changed products arrive via "Refresh catalog".
- If `catalog.db` is corrupt, delete it (manual recovery) and the next launch
  re-seeds. Document in risk register.

## Phases

### Phase 1 — Provider wiring + seed bootstrap (no UI changes)
Files:
- `lib/main.dart` (`MyhanoutApp`): wrap `LocalizedApp` with
  `CatalogProvider` alongside `CartProvider` using `MultiProvider`; call
  `loadSyncConfig()` on creation. Keep lazy `init()` (no eager DB open at
  startup).
- `lib/data/catalog_db.dart`: add single-flight `init()`, optional pagination
  params to `all()`, optional `search` to `count()`.
- `lib/data/catalog_seed_loader.dart` (new): best-effort asset copy described
  above.
- `lib/providers/catalog_provider.dart`: add `configured` getter forwarding
  `SyncConfig.isConfigured`; add `browseLocal`.

Changes:
```dart
MultiProvider(providers: [
  ChangeNotifierProvider(create: (_) => CartProvider(shopKey, businessName: businessName)),
  ChangeNotifierProvider(create: (_) => CatalogProvider()..loadSyncConfig()),
])
```
- `CatalogRepository` interface gains backward-compatible optional params:
  `all({String? search, int? limit, int? offset})` and
  `count({String? search})`. Defaults preserve existing callers.
- `CatalogDb.all` applies `LIMIT/OFFSET` only when provided; `count` adds a
  `WHERE name LIKE ? OR ...` clause when `search` is non-empty.

Risks:
- Startup cost if seed copy or `init()` runs eagerly. Default remains lazy.
- Widget tests pumping `HomePage` now need `CatalogProvider` in tree.
- Seed copy adds ~2–5 MB to APK and a one-time first-use delay.

Tests:
- Add `test/shopkeeper_home_smoke_test.dart` mirroring
  `catalog_home_smoke_test.dart`, pumping `HomePage` with both providers and
  `sqfliteFfiInit`.

### Phase 2 — Read-only local catalog browse/picker (offline)
Files:
- `lib/providers/catalog_provider.dart`: add
  `Future<Map<String,dynamic>?> browseLocal({String q='', int limit=50, int offset=0})`
  returning `{total, limit, offset, products:[...]}` built from
  `_repo.all(...)` + `_repo.count(...)`, mapping entries to the same product
  map shape BrowsePage expects (`name`, `category`, `origin: 'local'`,
  `image_url: null`).
- `lib/screens/browse_page.dart`: add a `localOnly` flag (default `true` for
  end-user). When true, call `provider.browseLocal` instead of
  `browseServer`; keep search debounce, pagination, pull-to-refresh (refresh
  re-runs the local query). Show "Cached"/"Offline catalog" hint. Keep
  `onSelect` callback for picker use; row tap returns the product map and pops.
  Admin-only actions (sync settings, capture) remain gated by `kIsAdmin`.
- `lib/screens/inventory_screen.dart` (`InventoryBody`): add a
  "Browse catalog" button (search row or mini-FAB) pushing
  `BrowsePage(localOnly: true, onSelect: ...)`; on selection open
  `ProductFormDialog` with barcode + name pre-filled.

Changes:
- `BrowsePage` constructor gains `final bool localOnly; final void Function(Map<String,dynamic>)? onSelect;`.
- No network call in local mode → zero data usage.

Risks:
- Loading 14,669 rows without pagination would OOM the list. Pagination is
  mandatory; verify `_loadMore` works against local totals.
- `BrowsePage` currently assumes server product maps include `brand`; local
  maps omit it. Subtitle rendering must null-check (already does).

Tests:
- Widget smoke: push `BrowsePage(localOnly: true)` with a provider backed by
  a seeded/empty DB; expect no crash and empty/"no products" state.
- Widget smoke: push `BrowsePage(localOnly: true)` with `onSelect`; tap a row
  and verify callback fires (use a pre-seeded unique entry).

### Phase 3 — Prefill from local catalog on scan (zero data)
Files:
- `lib/screens/inventory_screen.dart` (`ProductFormDialog._scan`): after a
  barcode scan and local inventory miss, check
  `CatalogProvider.get(code)` first; if hit, set `_name`/`_barcode` and show
  `autoFilledHint`. Only if local miss and `provider.configured`, try
  `CatalogProvider.resolveFromServer(code)` (network fallback) and cache it.
  Finally fall back to `CartProvider.lookupProduct` / manual entry.
- `lib/screens/checkout_screen.dart` (`scanToAdd`): same order — local catalog
  → optional network resolve → OFF lookup → `_NewFromScanDialog`.
- `lib/providers/cart_provider.dart`: optional `lookupCatalog` helper
  delegating to `CatalogProvider`; recommendation stays as in original (UI
  reads `CatalogProvider` directly to avoid coupling).

Changes:
- Name stays French primary for shop inventory (existing convention);
  `name_ar` is catalog-side only and is not copied into `Product.name`.

Risks:
- `resolveFromServer` writes to `catalog.db` and calls `load()` (notifies).
  Guard with `mounted` checks (already present).
- Network fallback uses data; default unconfigured setups use zero data.

Tests:
- Unit: `CatalogProvider.get` returns a seeded entry without network.
- Unit: `resolveFromServer` returns null without throwing when unconfigured.
- Unit: on resolve miss, OFF lookup path still attempted (manual verification).

### Phase 4 — Optional "Refresh catalog" (pull delta + merge)
Files:
- `lib/data/sync_config.dart`: add `lastCatalogRefreshAt` (int, default 0) with
  persistence key `catalog_last_refresh_at` and accessor.
- `lib/providers/catalog_provider.dart`: add
  ```dart
  Future<bool> refreshFromServer({
    int pageSize = 100,
    void Function(int fetched, int total)? onProgress,
  })
  ```
  plus a `_refreshing` flag and `refreshing` getter.
- `lib/screens/settings_screen.dart`: add a "Catalog" card showing local count,
  last-refresh time, configured status, and a "Refresh catalog" button with a
  progress dialog; reuse `SyncSettingsDialog` for URL/token configuration.

Implementation notes:
- Load `SyncConfig`; if not configured, set `_syncMessage` and return false.
- Paginate `client.search(q: '', limit: pageSize, offset: offset)` until
  `offset >= total`. Page size is capped at 100 by the server.
- For each server row, compute the client-side delta: upsert only when the
  local entry is missing or `server.updated_at > local.updatedAt`. Count
  inserted/updated/skipped.
- Map server fields to `CatalogEntry` (`name`, `name_ar`, `name_en`,
  `category`; no photo/brand). Preserve `updated_at`.
- On first-page failure, abort and return false; rows already upserted remain
  (partial refresh is acceptable and resumable on next run).
- After success, persist `lastCatalogRefreshAt`, call `load()`, set
  `_syncMessage` (e.g. "Refreshed: 12 new, 3 updated, 14654 unchanged").
- Guard against concurrent refreshes (`if (_refreshing) return false;`).
- Duration note: ~147 requests for 14,669 rows at page size 100; expected
  1–2 minutes on tailnet. Show progress and keep the UI responsive.

Risks:
- Long-running manual action; user may navigate away. Run with progress
  callback and disable the button while active; do not block the UI thread
  (each request already awaits).
- Partial failure leaves a mixed catalog; next refresh re-checks all rows via
  `updated_at`, so it is idempotent.
- Network usage occurs only here; document clearly in the UI ("Uses mobile
  data / tailnet").

Tests:
- Unit: `refreshFromServer` returns false without throwing when unconfigured.
- Unit: with a fake `http.Client` injected through `SyncConfig`/client
  factory, refresh upserts rows and updates the count. (May require adding an
  optional `clientFactory` to `SyncConfig`; document as test seam.)
- Widget: settings screen pumps with `CatalogProvider` and opens the
  SyncSettingsDialog and the refresh button without crash.

### Phase 5 — Configuration & no-network handling
Files:
- `lib/screens/settings_screen.dart`: catalog card (above) + existing backup
  cards. Requires `CatalogProvider` in tree (Phase 1).
- `lib/data/sync_config.dart`: keep null defaults; no baked secrets. Optional
  `testConnection()` helper in `CatalogSyncClient` (GET search limit 1) may
  be added; not required for v1.
- Android manifest: if the tailnet uses plain HTTP, add a
  `network_security_config.xml` permitting the tailnet domain (or
  `usesCleartextTraffic`). Document; do not change the server.

Changes:
- Tailnet-only messaging: "Cannot reach catalog server" is an expected state,
  not a bug. Refresh button stays disabled/hidden when unconfigured.

Risks:
- Cleartext HTTP blocked on Android 9+; verify tailnet URL scheme.
- Bearer token stored in SharedPreferences (unencrypted). Acceptable for v1.

Tests:
- Widget: settings screen opens `SyncSettingsDialog` without crash.
- Unit: `browseLocal`/`refreshFromServer` return null/false and do not throw
  when unconfigured or when the client throws.

### Phase 6 — Verification
- Run `flutter analyze` and `flutter test`; all 47 existing tests remain green
  plus new tests.
- Regression targets: `cart_test`, `db_test`, `catalog_db_test`,
  `sync_db_test`, `catalog_home_smoke_test`, `widget_test`.
- Manual QA on device:
  1. Fresh install → seed count ~14,669; search/prefill works in airplane mode.
  2. Configure tailnet URL/token → "Refresh catalog" updates count and
     `_syncMessage`; re-run in airplane mode shows refreshed rows.
  3. Scan a barcode present in seed → form prefilled, zero network.
  4. Scan an unknown barcode with network configured → resolve caches it.
  5. Unconfigured device → no network calls during browse/search/scan.
- Measure cold start and first-use seed copy time; keep under noticeable
  regression (target < 1 s additional on first launch).

## New/Modified Files Summary
Modified:
- `pubspec.yaml` (asset registration)
- `lib/main.dart` (MultiProvider + CatalogProvider)
- `lib/data/catalog_db.dart` (single-flight init, pagination, count-by-search)
- `lib/data/sync_config.dart` (lastCatalogRefreshAt)
- `lib/providers/catalog_provider.dart` (configured, browseLocal, refreshFromServer)
- `lib/screens/browse_page.dart` (localOnly, onSelect, pagination)
- `lib/screens/inventory_screen.dart` (browse button, local-first prefill)
- `lib/screens/checkout_screen.dart` (local-first prefill)
- `lib/screens/settings_screen.dart` (catalog card + refresh)

New:
- `assets/catalog_seed.db` (binary asset, ~14,669 rows)
- `lib/data/catalog_seed_loader.dart`
- `tools/build_catalog_seed.py`
- `test/shopkeeper_home_smoke_test.dart`
- `test/catalog_refresh_test.dart`
- `test/catalog_seed_bootstrap_test.dart`

Unchanged (reused as-is):
- `lib/data/catalog_sync_client.dart`, `lib/models/catalog_entry.dart`,
  `lib/screens/capture_dialog.dart`, `lib/screens/sync_settings_dialog.dart`,
  `lib/data/db.dart`, per-shop models/providers.

## Risk Register
1. **APK size + first-use latency** from bundling 2–5 MB seed. Mitigate with
   optional gzip and lazy copy; measure.
2. **Seed staleness.** Seed never auto-updates; "Refresh catalog" is the only
   path. UI must show last-refresh time and make refresh discoverable.
3. **Test singleton state.** `CatalogDb.instance` persists across tests and
   now may contain ~14,669 seeded rows. New/changed tests must use unique
   barcodes and avoid exact total-count assertions (except a dedicated seed
   bootstrap test that asserts `count() >= 14000`).
4. **Schema drift.** Seed must be v3 with `user_version=3`; otherwise
   `onUpgrade` runs and may add columns to an already-complete schema (harmless
   but noisy). Verify in build script.
5. **Corrupt/partial seed.** `ensureSeeded` validates with `PRAGMA quick_check`
   and writes via temp+rename; a bad asset leaves an empty DB rather than
   crashing.
6. **Provider tree churn** breaks widget tests that pump `HomePage`,
   `InventoryBody`, `SettingsScreen`, or `BrowsePage` without
   `CatalogProvider`. Update those tests to inject it.
7. **Long refresh.** ~147 sequential requests; must show progress and remain
   cancellable-by-navigation-safe. Partial results persist.
8. **Scope creep.** Keep end-user read-only: no push, no capture/edit, no
   server changes. `syncNow` stays admin-gated in the UI.
9. **Tailnet cleartext/HTTPS mismatch** can silently fail on device; verify
   with real hardware and document `network_security_config.xml`.
10. **Token storage** in SharedPreferences (unencrypted) is acceptable for v1
    but noted.

## Test Plan (new)
- Unit: `CatalogDb.init` with missing asset leaves an empty, usable DB.
- Unit: seed bootstrap copies asset when `catalog.db` is absent (when asset
  present) and does not overwrite an existing DB.
- Unit: `CatalogDb.all(search:, limit:, offset:)` paginates and filters.
- Unit: `CatalogProvider.configured` reflects `SyncConfig`.
- Unit: `CatalogProvider.browseLocal` returns total + page without network.
- Unit: `CatalogProvider.get` returns seeded entry without network.
- Unit: `CatalogProvider.resolveFromServer` returns null without throwing when
  unconfigured.
- Unit: `CatalogProvider.refreshFromServer` returns false without throwing when
  unconfigured; with a fake client it upserts rows and reports counts.
- Widget: `HomePage` pumps with `CartProvider` + `CatalogProvider`.
- Widget: `BrowsePage(localOnly: true)` pumps unconfigured/empty without crash.
- Widget: settings screen opens `SyncSettingsDialog` and refresh button
  without crash.
- Regression: existing 47 tests remain green.

## Out of Scope
- Server changes or new endpoints (including delta endpoints).
- Price/stock/category fields on `Product` beyond existing.
- Automatic background sync or push from shopkeeper.
- Multi-shop catalog partitioning (catalog is global per device).
- Replacing the seed at runtime (refresh handles updates).