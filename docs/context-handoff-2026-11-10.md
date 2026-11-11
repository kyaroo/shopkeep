# Context Handoff — myhanout (shopkeeper) — 2026-11-10

Purpose: hand off the current state so a fresh context can continue without re-discovery.

## 1. Applications

| App | Repo | Role |
|---|---|---|
| **shopkeeper** (`myhanout`) | `/home/hermes/perso/shopkeeper` | Flutter POS. Flavors: `shopkeeper` (`com.myhanout.myhanout`, customer POS) + `admin` (`com.myhanout.admin`, catalog/shop registry). |
| **catalog-server** | `/home/hermes/perso/barcode-mapper/server` | FastAPI catalog API (`/v1/products`, `/v1/sync`), Docker, SQLite at `/data/catalog.db`. |
| **barcode-mapper** | `/home/hermes/perso/barcode-mapper` | No standalone Flutter app anymore (merged into shopkeeper `admin` flavor); only `server/` + `.hermes/plans/` remain. |

## 2. Codebase MCP index (updated this session)

| Project | HEAD | Nodes / Edges |
|---|---|---|
| `shopkeeper` | `99dfd39b5e027f610bbf21da9f5cc5750005f5a6` | 849 / 2110 |
| `catalog-server` | `9caa3c83d7dd8e3843b4730a9abe719d03c49432` | 130 / 284 |

> Note: the graph reflects **git HEAD**, not the dirty working tree. Re-index after committing.

## 3. Git state (working tree)

- HEAD: `99dfd39` — "Add cross-repo catalog contract + provisioning service + slug + widgets + launcher assets"
- Uncommitted: **22 files changed (+684 / −657)** — includes this session's edits plus pre-existing dirty changes (lang JSON, launch backgrounds, data/, screens/, theme.dart).

## 4. This session's work

1. **Re-indexed** codebase MCP (shopkeeper + catalog-server); committed the untracked additions as `99dfd39`.
2. **Catalog page** (`lib/screens/catalog_home_page.dart`): replaced grey `Icons.inventory_2` fallback with branded teal `_ProductGlyph` (`Icons.store`, `colorScheme.secondary`, 44×44). Added `import '../models/catalog_entry.dart'`.
3. **Browse page** (`lib/screens/browse_page.dart`): same `_ProductGlyph` fallback in `_Thumb` (empty URL + errorBuilder).
4. **Design/theme audit + fixes** (`lib/theme.dart`, `lib/screens/sync_settings_dialog.dart`):
   - Fixed stale doc comment (claimed Roboto / "Inter not pinned" → actual: Tajawal for Arabic, Inter for Latin).
   - Added `primary`/`onPrimary` to the `AppColors` extension (fields, constructor, `copyWith`, `lerp`, light/dark status).
   - Aligned `sync_settings_dialog.dart` muted text: `Colors.grey` → `AppPalette.surfaceVariant`.
   - Verified: `flutter analyze` → **No issues found**.
5. **Investigated** `evanca/flutter-ai-rules` — AI coding-agent skills (36 Flutter/Dart skills) for Claude Code/Codex/Cursor. Relevant for agent-assisted Flutter dev; **not** an app-side AI SDK.

## 5. Open items / next steps

- [ ] **Commit or review the dirty working tree** (22 files; net ~+27 lines but heavy churn). The session's edits (browse_page, catalog_home_page, sync_settings_dialog, theme) are uncommitted and **not yet in the graph**.
- [ ] **Re-index after committing** so the graph reflects the design/theme + catalog/browse changes.
- [ ] Optionally **install flutter-ai-rules** for agent-assisted dev (`npx skills add evanca/flutter-ai-rules`, Node 22.20+).
- [ ] Catalog image strategy (from earlier): BrowsePage OFF `image_url` caching; `InventoryBody` leading still uses `StockBadge` only.
- [ ] `lib/data/db.js` deleted (347 lines) — confirm intentional.
- [ ] Cross-repo contract `docs/catalog-server-interactions.md` vs actual `CatalogSyncClient` endpoints.

## 6. Key references

- Theme/design system: `lib/theme.dart` (`AppPalette`, `AppColors`, `AppTextStyles`).
- POS entry: `lib/main.dart` (`HomePage` tabs: checkout / inventory / salesHistory).
- Admin entry: `lib/admin_main.dart` → `AdminSetupScreen`.
- Catalog screens: `lib/screens/catalog_home_page.dart`, `browse_page.dart`, `capture_dialog.dart`.
- Flavor gating: `lib/build_config.dart` (`kIsAdmin` via `--dart-define=ADMIN=true`).
- Build: `flutter build apk --flavor <shopkeeper|admin> --debug`.
