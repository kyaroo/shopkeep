# Catalog seed release procedure

This is the founder-side, host-only release path for the offline catalog that
ships inside every APK. It applies to the **universal catalog** decision: the
APK carries a catalog snapshot (the "seed"); there is **no in-app catalog pull**
and app upgrades **never overwrite an existing `catalog.db`**.

## Invariants — read first

- The catalog is universal. The APK ships a seed so a brand-new install is
  complete offline.
- **No re-seed on upgrade (decision 2a).** `CatalogSeedLoader.ensureSeeded`
  copies the bundled `assets/catalog_seed.db` only when no `catalog.db` exists;
  on upgrade an existing shop keeps its current catalog version and data.
- **No in-app catalog pull exists.** A shop never downloads the catalog from
  the app. Existing shops receive founder-signed `.myhanout` deltas out of band;
  new shops are registered at the APK's seed version.
- `seedCatalogVersion` in `lib/data/catalog_seed_loader.dart` is the base
  version a freshly seeded install adopts. If it does not match the generation
  of the bundled DB, every subsequent delta is rejected by the base-version
  guard — silently, far from the build. Hence the gate below.
- The seed schema is `CatalogDb` v3 plus the nullable `retail_price_cents`
  column (carried from the server's `catalog_source`); `PRAGMA user_version`
  stays 3 because the column is additive.

## Procedure

1. **Founder edits the catalog.** Use the admin app / server tooling to update
   `catalog_source` (names, photos, and `retail_price_cents` where known).
   The server DB is the source of truth for the next seed generation.

2. **Sync now pushes to the server.** The admin's catalog sync publishes the
   edits so the server DB dump reflects the new generation. Confirm the dump is
   current before building a seed from it — never seed from a stale dump.

3. **Regenerate the seed (host only).** From the repo root:

   ```bash
   python3 tool/build_catalog_seed_with_photos.py <server_catalog.db> assets/catalog_seed.db
   ```

   The tool rewrites `assets/catalog_seed.db` and emits a sibling manifest,
   `assets/catalog_seed.manifest.json`, containing `catalog_version`, `sha256`,
   `row_count` and `schema_version`. `catalog_version` defaults to the current
   `seedCatalogVersion`; pass `--catalog-version N` to override when the
   generation number is managed independently. The tool runs entirely on the
   host — it does not build an APK, deploy, migrate a DB, or contact the server.

4. **Bump `seedCatalogVersion`.** If this seed is a new generation, raise the
   constant in `lib/data/catalog_seed_loader.dart` to match the seed's
   `catalog_version`, then regenerate (step 3) so the manifest picks up the new
   value. Existing installs are unaffected — they keep their version and get
   founder-signed deltas; only new installs adopt the bumped base.

5. **Run the verify gate.** This is the release blocker:

   ```bash
   bash tool/verify_catalog_seed.sh
   ```

   It passes only when `seedCatalogVersion` equals the manifest's
   `catalog_version`, the DB's SHA-256 equals the manifest `sha256`, the row
   count and `PRAGMA user_version` match the manifest, and the DB carries the
   `retail_price_cents` column. A mismatch fails the gate — do not build until
   it is green.

6. **Build the kit** with the existing release tooling once the gate is green:

   ```bash
   bash tool/build_release_bundle.sh <build-number> [version-name]
   ```

   The seed gate is deliberately a separate, manual step: it is **not** wired
   into `build_release_bundle.sh`, so run it yourself before every kit.

## What is deliberately absent

- No in-app catalog pull / refresh of an existing `catalog.db`.
- No re-seed of existing shops on upgrade (decision 2a).
- No server deploy, DB migration, device/ADB step, or APK build in the seed tool.
- No automatic invocation of the seed gate from the release-bundle script.
