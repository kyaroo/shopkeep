# Phase B — Listing bundle + join rework: specification

**Status:** written spec (no code) · **Owner:** personal (Manu Aachá) · **Date:** 2026-11-15
· **Reviewed 2026-11-15**: blocking defect B-1 (new-row `name`) fixed, factual errors
F-1…F-5 corrected; §1.2 "no HMAC" left **open** as a decision (see §7).
**Gates:** this document is the B0 gate for all of Phase B (~18 h: B1/B3 export+import, B2 upsert, B6 join).
**Deliverable location:** `docs/phase-b-listing-bundle-join-spec.md` in the shopkeeper repo
(`/home/hermes/perso/shopkeeper`).

---

## 0. Context & architecture this builds on

These decisions are **locked** and are stated here so every B item reads consistently:

| Store | Scope | Content |
|---|---|---|
| `catalog` | universal | barcode, name/ar/en, category, **photo @128px**, retail price |
| `listing` | per shop | barcode, `price_cents`, `stock_qty` |

- Shopkeeper carries the **whole catalog** locally; zero network for browse/prefill.
- Catalog updates flow admin → shopkeeper as **signed `.myhanout` deltas**
  (HMAC = QR secret, `base_version` guard, universal — never shop-bound).
- Delivery is **manual file exchange** (WhatsApp / Android share). Shopkeeper is
  100 % offline — no HTTP push from the POS app.
- The server is the single source of truth for `catalog_version`; read endpoints
  are ungated; writes (`POST /v1/sync`) are gated by `CATALOG_OPEN`.
- All server headends where the current code stands: `GET /v1/shops`,
  `GET/POST /v1/shops/{key}`, `POST /v1/shops/{key}/catalog-version`,
  `GET /v1/products/search`, `GET /v1/products/{barcode}`,
  `GET /v1/products?barcodes=...`, `POST /v1/sync`, `GET/POST /v1/admin/catalog-open`.
  **None of these are listing-related.**

---

## 1. Listing bundle

### 1.1 Exact file contents (shape)

A listing bundle is a **JSON** file. The **three listing fields** are the only
required per-item data: `barcode`, `price_cents`, `stock_qty`.

Top-level schema (versioned, machine-parseable):

```jsonc
{
  "format": "myhanout-listing-v1",
  "version": 1,
  "shop_key": "maison-du-marche",   // the shop this bundle belongs to (binding)
  "exported_at": 1718000000000,     // epoch ms, when the export was taken
  "sha256": "a3f5c9e...16hex",     // SHA-256 of the payload with `sha256` omitted
  "listings": [
    { "barcode": "0011210006508", "price_cents": 450, "stock_qty": 12 },
    { "barcode": "0011210006510", "price_cents": 1200, "stock_qty": 4 }
  ]
}
```

Rules for the payload:

- `format` is `myhanout-listing-v1`. Future versions bump `version`; importers
  reject unknown `format` before doing anything else.
- `listings` is an array of objects; every object carries **exactly** the three
  fields. No names, no photos, no categories — the bundle is deliberately
  **economic-only**.
- `barcode` is the **natural key** for the shop's listing (unique within a shop's
  `products` table).
- `price_cents` / `stock_qty` are signed 32-bit integers (cents, quantity).
- `sha256` is the hex SHA-256 of the canonical JSON payload **with the `sha256`
  field omitted** — a field cannot cover bytes that contain itself. This is the
  same payload-minus-signature pattern the catalog-delta HMAC uses.

Why the extra fields? `format`/`version` make the schema forward-compatible;
`shop_key` binds the bundle to one shop so an import refuses a bundle addressed
to a different shop; `sha256` detects corruption or tampering; `exported_at` is
for audit/timeline in later features.

### 1.2 Signing — no HMAC

**A listing bundle is not signed with the HMAC/QR secret.** Rationale, by the
data being carried:

- The HMAC/PR secret signs **catalog deltas**, because a delta carries the
  *founder's authoritative catalogue* from the admin side to the shopkeeper, and
  a tampered delta could silently rewrite shop product metadata.
- The listing bundle carries the **shop's own economic data** — the price and
  stock it already owns. The shopkeeper is the author of that data; there is no
  separate, untrusted author for it.
- Signing a snapshot proves "it was valid when signed," but the file is a
  *visible snapshot* shared over WhatsApp; anyone who can produce a valid
  snapshot can edit its price after the fact. A signature after the fact is
  therefore not a protection against the real risk (the shop owner's own
  tampering with its own pricing).
- The bundle carries its **own integrity machinery** instead: the `shop_key`
  binding and the `sha256` payload checksum, so an import can refuse a file that
  belongs to another shop or that has been altered in transit.

The `shopkeeper` APK therefore treats the bundle as self-authenticating data,
not as a signed artifact.

### 1.3 Size budget

Because the bundle has **no photos**, it is compact, but the import must still be
bounded so a giant shop cannot freeze a phone:

| Constraint | Value | Rationale |
|---|---|---|
| Max bundle file size (on import) | **10 MB** | Already 100× above any realistic shop listing (~400 KB for 4 000 rows); leaves a wide margin under any share target. |
| Max rows per bundle | **10 000** | ~0.6 MB at ~60 B/row; same margin. Under 10k, a single export is always cheap. |
| Per-row payload | exactly 3 fields, < 128 B | keeps the whole file small; no photo overflow possible. |

If a shop has **> 10 000 products**, the exporter produces **multiple bundles**
(e.g. by barcode range) — the import merges them all into one listing. No bundle
is ever imported individually at "catalog scale."

### 1.4 Android share / import path

The path reuses, and only extends, the mechanism already built for catalog deltas:

**Export** (admin device or shopkeeper):

1. Build the JSON per §1.1.
2. Write it to a file whose name is `catalog_<shop_key>_listing_v<version>.myhanout`
   (the `.myhanout` suffix keeps the file type recognisable alongside deltas).
3. Put it in the app's private documents directory (`path_provider`).
4. Share it with the platform file-picker/WhatsApp chooser via `share_plus`
   (`Intent.createChooser` with `ACTION_SEND`). The user picks the recipient.

**Import** (receiving shopkeeper device):

1. Android launches `MainActivity` with the shared file's `file://` /
   `content://` URI (same mechanism the delta receiver uses — the app is
   installed with a `VIEW` intent filter for `.myhanout` files).
2. `MainActivity` resolves the URI through the existing method channel
   `myhanout/view` — currently `getInitialUri` / `readUri` — and hands it to the
   app shell.
3. The shell inspects the file's `format` field: `myhanout-catalog-delta` →
   existing delta path (`MyhanoutFile`); `myhanout-listing-v1` →
   **new `myhanout/import` handler** created for this spec (same URI-capture
   plumbing, one new method).
4. The import handler (per §2) verifies checksum + shop binding, then applies a
   single transactional upsert, and reports a short summary.

No new permission is required: the file arrives through a normal `VIEW` intent,
which Android grants to the installed app.

---

## 2. Upsert / conflict rules (B2)

### 2.1 Owner map

| Field | Owned by | Where it lives |
|---|---|---|
| `barcode`, `name`, `name_ar`, `name_en`, `category`, `photo`, `retail price` | **catalog** (universal) | catalog DB + deltas |
| `price_cents`, `stock_qty` | **listing** (per shop) | the shop's `products` row |

The two domains share the same table (`products`) and are therefore **schema-
separated, never content-colliding**: catalog deltas write `name`/`photo`, the
listing import writes `price_cents`/`stock_qty`.

### 2.2 Import semantics (per bundle)

1. Load the file; parse; validate `format`/`version` before touching storage.
2. Verify `sha256` against the payload re-encoded with the `sha256` field omitted.
   On mismatch → **abort whole import** with a clear error (do not partial-apply).
3. Verify `shop_key` binding equals the **currently active shop's**
   `shop_key`. On mismatch → abort with "bundle belongs to another shop."
4. Open the active shop's DB file (`myhanout_<shop_key>.db`) inside **one**
   explicit transaction.
5. For each listing item, upsert by `barcode`. **A new row must be given a
   `name`**: `products.name` is `NOT NULL` (`lib/data/db.dart:110`) and the bundle
   deliberately carries no name (§1.1), so the importer **seeds it from the local
   catalog** — the device holds the whole catalog, so this is free and offline.
   Unknown barcode → fall back to the barcode string itself.
   `INSERT INTO products (barcode, name, price_cents, stock_qty, source)
      VALUES (?, ?, ?, ?, 'listing-import')
    ON CONFLICT(barcode) DO UPDATE SET price_cents=excluded.price_cents,
    stock_qty=excluded.stock_qty`
   The `DO UPDATE` clause touches **only** the two economics columns, so an
   existing row's catalog fields are never rewritten.
   *(Optional: seed `photo` for a new row from the catalog too — free, and the
   inventory row shows a thumbnail immediately. Not required for B0.)*
6. Nothing else is written: `id`, `name_ar`, `name_en`, `category`, `photo`,
   `photo_source`, `low_stock_threshold` are **untouched on an existing row**, and
   `name` is written **only when the row is created** (seeded from the catalog, see
   step 5). `source` is written only on insert (`listing-import`).
7. New vs. existing determines only the `source` provenance value recorded:
   `listing-import` for rows inserted by this import; existing rows keep their
   prior value. (The `source` column tracks *how* a product's economics arrived,
   so later conflict flags can distinguish admin-entered, export-imported, or
   shop-entered prices.)
8. Return an `ImportResult`: `applied` (rows matched+inserted), `new` (rows
   inserted). No deletion occurs on import.
9. Commit; on any per-row parse error the entire import is rolled back and
   reported with the offending barcode. The shop's listing is unchanged.

### 2.3 What an import may and may not overwrite

| Field | May overwrite on import? | Notes |
|---|---|---|
| `price_cents`, `stock_qty` | **Yes** (per barcode) | the two economics fields this bundle carries |
| `barcode` | No | natural key; never rewritten |
| `name` | **Only on insert** | the bundle carries none; a new row is seeded from the **local catalog** (barcode string as fallback). Never overwritten on an existing row |
| `name_ar / name_en / category` | **No** | catalog-owned; the bundle carries no such field |
| `photo` / `photo_source` | **No** (optionally seeded on insert) | catalog/display data; the bundle carries no photo |
| `source` | Yes, only for a *new* row (set to `listing-import`); existing value preserved for matches | provenance marker, never a business value |
| `low_stock_threshold` | **No** | inventory config, never part of the bundle |
| `id` | **No** | server-side surrogate, never rewritten |

### 2.4 What is explicitly out of scope (not part of B0)

- **Deleting a product on import**: the bundle is a snapshot; a barcode absent
  from the bundle never means "delete." Deletes are an explicit admin action
  (and the catalog's tombstones use the separate `pending_deletes` mechanism).
- **Merge conflicts between two bundles**: if two devices export the same shop
  concurrently, the importer is still a deterministic upsert by barcode; the
  final value is whichever `price_cents`/`stock_qty` the last bundle applied.
  True merge handling is G2 (conflicts) — parked, not in B0.
- **Server-side listing storage**: the listing is a local file+DB; see §4.

---

## 3. Join rework (B6)

### 3.1 How a device joins a shop (post-CAT9/B4 flow)

Joining is **purely local**. The QR is self-contained and verifiable inside the
app; no server round-trip is part of the join.

1. **Admin** (founder app) generates a provisioning QR for the shop. The QR is
   the **signed provisioning token** (B4), rendered by `QrImageView`.
2. The shopkeeper scans it with the shopkeeper app → `QrScanPage` returns the
   raw token string.
3. The app verifies the token with the **embedded provisioning HMAC secret**
   (no network): signature + expiry (`ttl_seconds` from the token) +
   clock-skew guard (60 s) — exactly the existing `Provisioning.verify`.
4. If valid, the app extracts `shop_key` and `business_name`, then:
   - creates the shop locally (`SettingsService.addShop(shopKey, businessName)`),
   - sets the active shop (`SettingsService.setCurrentShopKey(shopKey)`),
   - stores the per-shop display name (`shop_names`),
   - **does not persist the token** — it is verified and then discarded. It is
     **not single-use**: the same code verifies again within its `ttl_seconds`.
     Enforcing single use needs nonce tracking (out of scope for B0).
5. The shop's data lives in the automatically-created file
   `myhanout_<shopKey>.db` (opened on demand via `Db.open(shopKey)`). No new
   table/column, no server write.

### 3.2 What the QR carries

The token payload is the existing B4 token:

```jsonc
{
  "shop_key": "maison-du-marche",   // join identity (stable across devices)
  "business_name": "Maison du Marché",
  "issued_at": 1718000000000,       // epoch ms
  "nonce": "A3F9K2Q7",              // random per-QR; makes each code unique
  "ttl_seconds": 1800               // lifetime the receiver enforces (no server round-trip)
}
```

Secured with `base64url(payload).base64url(HMAC-SHA256(secret))` using the
embedded provisioning secret. The **only server-dependent thing the join uses
is the existing `shops` registry** (`POST /v1/shops` registration done by the
admin at shop creation) — the device itself never POSTs or GETs anything to
discover the shop.

### 3.3 What happens on a second device

- A second phone scans the **same** QR → gets the same `shop_key` → opens the
  same shop and, on demand, the same DB file `myhanout_<shopKey>.db` on that
  phone.
- The **shop_key is the durable join identity**; the `nonce` is per-QR only
  (guarantees each code is unique, but is NOT the join identity).
- Each device keeps its own local copy of the file (file-per-shop + per-device
  sqflite storage). They do **not** share one literal
  file — two phones each maintain `myhanout_<shopKey>.db` on their own device.
- The app's model is **single-active-shop**: `AppState.shopKey` points at one
  shop at a time; screens close the previous DB and open the new one. A device
  can only be "in" one shop at a time.
- Consequence and design note: two devices that both edit the same shop's
  price/stock can diverge (each holds its own copy). This is the same as
  "each phone is its own shopkeeper" — the authoritative source is whichever
  device's data the shopkeeper chooses to keep, and the channel to reconcile is
  the admin-side `registerShop` + `catalog_version`, not a network listing sync.
  Real multi-device write-conflict handling is G2 (parked).

### 3.4 Interaction with the per-shop listing

- The listing **belongs to the shop**, not to the device. Joining a shop means
  the device now carries that shop's DB file, which contains the **whole
  listing** (`price_cents`, `stock_qty`) alongside the universal catalog.
- Switching shops = swap the active DB; the catalog (universal, no shop in its
  name) and the listing (per-shop, inside the DB file) live in the same file,
  so a join is a single `Db.open(shopKey)` away — the device gets the whole
  catalog **and** the shop's listing, no extra sync.
- The catalog sync URL/token (settings) is a **separate per-server config**, so
  a device that joins a shop does not automatically get a sync server; the
  shopkeeper sets the URL/token in settings (existing flow). This keeps join
  (§3.1) free of any network, as intended.

---

## 4. API surface — server needs **no new endpoints**

Phase B is a **purely local file exchange** (§1) + a **local join** (§3).
Neither touches the server.

| B item | Server involvement | New endpoints needed? |
|---|---|---|
| B1/B3 export+import (§1) | None (file share + local import) | **0** |
| B2 upsert (§2) | None (local DB upsert) | **0** |
| B6 join (§3) | None, except the shop already registered by admin via `POST /v1/shops` (existing) | **0** |
| Catalog sync | Existing read endpoints + gated `POST /v1/sync` | **0** |

Read endpoints used by future/catalog work that this spec does **not** add:

- `GET /v1/shops/{key}` → `catalog_version` for a fresh install (existing read).
- `POST /v1/shops/{key}/catalog-version` → only the **admin** reports the
  generation after a catalog push (existing write).

The **only** new surface for Phase B is a new Android method channel method
`myhanout/import` on the client (§1.4) and its screen/handler wiring — no server
code at all.

---

## 5. Verification / acceptance criteria (for the implementer)

The implementer proves the spec by behavior, not by description:

1. **Export**: share a bundle from shop `X`; the file's `format` is
   `myhanout-listing-v1`, `shop_key` equals `X`, `sha256` verifies against the
   raw bytes, and `listings` carries exactly `{barcode, price_cents, stock_qty}`
   — no name/photo.
2. **Import, same shop**: importing the file into the same shop applies every
   `price_cents`/`stock_qty`, adds new barcodes with `source=listing-import`,
   and leaves `name`/`photo`/`category`/`low_stock_threshold`/`id` untouched.
3. **Server key refuse**: sharing a bundle for shop `X`, then importing it
   into the *different* active shop `Y` → import aborts with "bundle belongs to
   another shop," and `Y`'s listing is unchanged.
4. **Corrupt file**: flip one byte after the export → import aborts with the
   checksum error; the listing is unchanged.
5. **Non-gallery**: a list of >10 000 products exports as multiple bundles and
   each imports idempotently to one listing (no lost/partial rows, one
   transaction per bundle).
6. **Join**: admin generates a QR; shopkeeper scans it on a second device;
   both devices end with `shopKey` set, the same shop's DB file open, the same
   same listing loaded, and no token persisted. A second scan of the same QR
   cannot join a *different* shop — the payload names exactly one `shop_key`
   (that is binding, not single-use enforcement; see §3.1).
7. **Server**: **no server code changes and no new endpoints** — `server/app.py`
   gains nothing in Phase B (verify: no commits on `barcode-mapper` touching
   `server/`). Client-side, the tree is clean and pushed when implementation
   starts.

---

## 6. Decision log

| # | Decision | Evidence |
|---|---|---|
| D1 | Listing bundle format = signed-free JSON, `myhanout-listing-v1` | Optional integrity (sha256+shop_key); no vendor-secret needed for shop-owned data |
| D2 | No HMAC on the listing bundle | Catalog deltas carry *authoritative foreign data*; the listing is the shop's own, and signing a visible snapshot adds no protection |
| D3 | Import upserts only `price_cents`/`stock_qty` by `barcode` | Listing is the only owner of those fields; catalog delta must never write them (already enforced) |
| D4 | Import never deletes | Bundle is a snapshot; deletes are explicit admin action |
| D5 | Atomic import, one transaction per bundle, abort on any error | Prevent partial/corrupt listings |
| D6 | Size budget 10 MB / 10 000 rows | Compact no-photo payload; phone-safe |
| D7 | Join = self-contained signed token, no server round-trip | B4 already proves tokens verify offline |
| D8 | Second device = same `shop_key`, own DB file, single-active-shop | File-per-shop architecture; no cross-device write sync in B |
| D9 | No new server endpoints in Phase B | All four B items are local file/DB operations |

---

## 7. Risks / open items

- **Concurrent edits across devices** (§3.3): two devices editing the same
  shop's price/stock will diverge; B0 cannot solve it (G2, parked).
- **WhatsApp file-size behaviour**: §1.3 sets a 10 MB hard cap; if the
  recipient platform drops larger files, the spec's importer already aborts
  cleanly rather than corrupting.
- **QR `nonce` uniqueness**: `nonce` is a random per-QR string; 8 chars from a
  32-char alphabet is **40 bits** (≈1.1e12), ample for the expected volume.
  Upgrading to a random 12-char nonce is a one-line change after B0.
- **OPEN — needs a decision (§1.2 "no HMAC").** The rationale says the listing is
  the shop's own data with no untrusted author, but §1.4 also lets the **admin**
  export a listing and send it to provision a shop — foreign-authored data, the
  same shape as the catalog delta. `shop_key` blocks cross-shop imports but
  authenticates nothing. Fine if the threat model is "the shopkeeper may edit its
  own prices anyway"; if the admin→shopkeeper listing is meant to be authoritative,
  reuse the catalog-delta HMAC instead.
