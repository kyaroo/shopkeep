# Catalog Server Interactions (shopkeeper side)

Companion doc to `barcode-mapper/server/API_AND_APP_INTERACTIONS.md`.
Shopkeeper consumes the catalog server (FastAPI) via `CatalogSyncClient`.

## Key files

- `lib/data/catalog_sync_client.dart` — HTTP client (push/resolve/search/shops/catalog-open).
- `lib/data/sync_config.dart` — persisted url/token/deviceId.
- `lib/providers/catalog_provider.dart` — configured, browseLocal, refreshFromServer.
- `lib/data/catalog_db.dart` — local cache (seed + deltas).
- `lib/data/catalog_seed_loader.dart` — first-launch seed bootstrap.
- `lib/screens/settings_screen.dart` — catalog card + refresh.
- `lib/screens/inventory_screen.dart`, `lib/screens/checkout_screen.dart` — local-first prefill.

## Endpoints used

- `GET /v1/products/search` — browse/refresh (paginated, 100/page).
- `GET /v1/products/{barcode}` — resolve on scan miss.
- `GET /v1/products?barcodes=...` — batch resolve.
- `POST /v1/shops`, `GET /v1/shops/{key}` — provisioning.
- `GET/POST /v1/admin/catalog-open` — write gate control (admin flavor).
- `POST /v1/sync` — owner push (admin only, gated).

## Flow summary

Local seed first → zero network for browse/prefill → optional refresh pulls
deltas by `updated_at` → admin push gated by `CATALOG_OPEN`.
