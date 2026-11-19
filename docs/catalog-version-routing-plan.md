# Plan — catalog version model + admin routing (2026-11-19)

Status: strategized, not implemented. Supersedes the earlier "APK carries the
catalog / no in-app pull" decision. All decisions below are locked with the user.

## Locked model

- The catalog is **universal**; one **global monotone generation counter**.
  Latest = best.
- Server holds the **global version** (latest generation) and each shop's
  **catalog_version** (the base that shop is on).
- Admin **push** ("publish changes") creates a new server generation.
- Admin **pull** ("update catalog") brings the admin's local catalog to the
  latest generation.
- Distribution computes the difference: admin version N vs shop version M, and
  delivers **one multi-generation delta** `base = M`, `target = N` containing
  generations M+1…N.
- The shop applies it and advances to N. Listing (price/stock) is untouched.
- Generation 1 = the existing seed (built by the completed server-side OFF
  ingest). A future seed rebuild is a release-time event that bumps the
  baseline explicitly.
- Shops at v0 (never reported) are still refused.
- The APK seed remains only the fresh-install baseline.

## Phase 0 — Server (approval required: schema + endpoints + deploy)

- Global version: `catalog_state` key `global_catalog_version`, baseline 1.
- Change log: `catalog_changes(version, barcode, op, payload_json,
  PRIMARY KEY(version, barcode))` + index on version.
- `POST /v1/sync`: in one transaction — upsert accepted rows, write the change
  log against `version = global + 1`, bump the global version. Partial
  acceptance kept; rejected entries are NOT logged.
- `GET /v1/catalog/version` -> `{version}`.
- `GET /v1/catalog/diff?from_version=M&limit=&offset=` ->
  `{from_version, to_version, total, next_offset, changes:[{version, barcode,
  op, row}]}`; owner token only; photos <= 50 KB / 128 px.
- Concurrency: the transaction keeps the counter and the log consistent
  (last-writer-wins on conflicting rows).
- Tests: version bump; log = accepted rows only; diff paging/filter;
  owner-only; photo budget; concurrent pushes.

## Phase 1 — Admin pull + multi-generation guard (app)

- New `lib/services/catalog_pull_service.dart` (admin-only): fetch the diff
  from the local version, apply all pages in one transaction, advance
  `Config.catalog_version` only on full success.
- `lib/data/catalog_delta.dart`: relax `verify` to accept `target > base`
  (multi-generation); keep the apply guard `base == installed`.
- Settings tab: "Update catalog" (pull) with a confirmation showing local
  V -> latest and the change counts.
- Tests: multi-gen verify/apply; transactional pull; version advance only on
  full success.

## Phase 2 — Distribution difference + confirmation

- `catalog_push_screen.dart`: show shop version M, admin version N, difference
  N-M; build one delta `base=M -> target=N` from the diff; confirmation box
  shows M -> N, difference, additions/updates/deletes; on confirm, deliver and
  report the shop version = N.
- Keep the founder/admin push-time role recheck.
- Tests: difference math; confirmation gating; report only after confirm;
  base-mismatch refusal.

## Phase 3 — Routing / IA (user's six decisions)

- Remove the app-bar three-dot menu on both flavors (`admin_home_screen.dart`,
  `main.dart`); delete `widgets/shop_actions_menu.dart` + its test. Settings
  only via the Settings tab; shopkeeper keeps its gear icon.
- Shops tab per-shop menu: add Shop info -> `ShopInfoScreen(shopKey)` and
  Export listing -> `ListingPushScreen(shopKey)`; keep Delete.
- `listing_push_screen.dart`: optional `shopKey` param.
- Catalog tab: remove "Manage catalog" and "Export listing"; keep one global
  "Distribute catalog"; fold add/edit/delete into the embedded `BrowsePage`,
  gated by `SignerSeedImport.canPush(activeRole)`; host owns add/scan.
- Delete `catalog_home_page.dart` + `catalog_home_smoke_test.dart`.
- Settings tab: Update catalog / Publish changes / Sync settings.
- Tests: routing; per-shop menu; Catalog tab button set; manage gating
  (salesman read-only); flavor gates.

## Phase 4 — Not-registered state

- Shop creation: if sync is unconfigured or the registration call fails, show
  a clear "Not registered on server" state (local shop stays usable).
- Tests: unconfigured + failed registration both surface the state.

## Phase 5 — Gates + build

- `flutter test`, `flutter analyze`, `verify_flavor_gates.sh`,
  `verify_catalog_export_gate.sh`, `security_regression_test.dart`
  (shopkeeper zero-HTTP), server `unittest`.
- Build the b6 kit (both flavors) after the gates.

## Order / dependencies

0 -> 1 -> 2 -> 3 -> 4 -> 5. Phase 0 unblocks 1 and 2. Phase 2 shares the
Catalog tab with Phase 3, so do 2 before 3.

## Risks

- Multi-gen delta size: page the diff; enforce the photo budget; a large N-M
  can exceed the file budget.
- Two admins pushing: the transaction keeps counter + log consistent; the last
  push wins on conflicting rows (`updated_at` rule).
- Baseline: generation 1 = the existing seed; the OFF ingest is server-side
  and already run. A rebuild bumps the baseline at release time only.
- Existing shops at v1/v3 get the diff from their M; v0 is refused.

## Approvals

- Phase 0 server schema + endpoints + deploy (a server write).
- The model change itself (supersedes "APK carries the catalog / no pull").
