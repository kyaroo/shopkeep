# Security Risk Analysis — myhanout POS data-exchange channels

**Date**: 2026-11-16 · **Version**: 1.0 · **Author**: Security Architect
**Scope**: the three data-exchange channels of the myhanout POS system —
(1) catalog server ↔ admin app, (2) admin app ↔ shopkeeper app,
(3) shopkeeper app ↔ server.
**Method**: code-grounded threat model (STRIDE per channel) + prioritized risk
register. Every finding cites the real file/line it was derived from; every
Critical/High finding carries an exploit path and copy-paste-ready remediation.
**Repositories inspected**:
`/home/hermes/perso/shopkeeper` (Flutter, HEAD `34e79cb`) and
`/home/hermes/perso/barcode-mapper` (FastAPI catalog server, `server/app.py`).

---

## 1. Executive summary

The system's *architecture* is sound where it was deliberately designed:
file-per-shop SQLite isolation, parameterized SQL everywhere, constant-time
token comparison on the server, TLS termination at Caddy, a bounded exposure
window for the catalog, and a container hardened with `read_only` rootfs,
`cap_drop: ALL` and a non-root user. The risks are concentrated in **shared
secrets shipped inside the client** and in **trust decisions that were locked
before the threat model was written**.

| # | Severity | Finding | Channel |
|---|---|---|---|
| C1-01 | **Critical** | Production bearer token hardcoded in client source and git history | 1 |
| C2-01 | **Critical** | Provisioning + catalog-delta HMAC secret hardcoded in **both** release APKs | 2 |
| C2-02 | **High** | Unvalidated `shop_key` → filesystem path traversal in the DB path | 2 |
| C1-02 | **High** | Server shop registry has no ownership model (hijack / delete / desync any shop) | 1 |
| C1-03 | **High** | `POST /v1/sync` trusts client `updated_at`, unbounded batch, no rate limit | 1 |
| C2-03 | **High** | Catalog delta is universal (not shop-bound) **and** signed with an extractable key | 2 |
| C2-04 | **High** | Delta receiver is not defensive: unchecked casts crash, unbounded photo decode OOMs | 2 |
| C2-05 | **High** | Unsigned JSON import wipes products/sales/**audit_log**, ignores `shop_key` binding | 2 |
| C3-01 | **High** | The shopkeeper "offline lock" is a tree-shaking accident, not a control | 3 |
| C2-08 | **Medium** | Release APKs are signed with the **debug** keystore | 2 |

**Immediate actions (P0, this week)**: rotate the catalog bearer token and the
provisioning/delta HMAC secret (both are in git history and in shipped APKs);
remove the baked token/defaults; validate `shop_key`; add an explicit
`kIsAdmin` gate + regression test for all server calls in the shopkeeper flavor.

**Counts**: 2 Critical · 7 High · 7 Medium · 2 Low · 4 Informational.

---

## 2. System overview

### 2.1 Components

| Component | Tech | Identity / deployment |
|---|---|---|
| Catalog server | FastAPI + SQLite (WAL), Docker | `catalog.myhanout.ma`, Caddy TLS, loopback `127.0.0.1:8020`, internal Docker network, `read_only` rootfs, `cap_drop: ALL`, non-root uid 10001 |
| Admin app | Flutter, flavor `admin` (`--dart-define=ADMIN=true`) | `applicationId com.myhanout.admin` |
| Shopkeeper app | Flutter, flavor `shopkeeper` | `applicationId com.myhanout.myhanout` |
| Local stores | SQLite (`sqflite`) | `catalog.db` (universal catalog) + `myhanout_<shopKey>.db` per shop |

Both apps are the **same codebase**; flavor differences are compile-time
(`lib/build_config.dart`) plus Gradle `applicationId`. `shared_preferences`
namespaces therefore never bleed between the two APKs.

### 2.2 Data classification

| Data | Class | Where it lives |
|---|---|---|
| Catalog names/ar/en, category, photo | Public-ish (OFF-derived, ODbL) | `catalog.db`, seed asset, server `catalog_source` + `products` |
| Price (`price_cents`), stock (`stock_qty`) | **Commercial — confidential per shop** | `myhanout_<shopKey>.db` only |
| Sales / sale_items / audit_log | **Financial — confidential per shop** | `myhanout_<shopKey>.db` only |
| Bearer token, HMAC secret | **Credentials** | client source + git history (see findings) |

### 2.3 The three channels

**CH1 — catalog server ↔ admin app.** HTTPS + `Authorization: Bearer <shared
secret>` (`lib/data/catalog_sync_client.dart:81-84`). Endpoints used:
`GET /v1/products/search`, `GET /v1/products/{barcode}`, `GET /v1/products?barcodes=`,
`POST /v1/sync`, `POST/GET/DELETE /v1/shops`, `POST /v1/shops/{key}/catalog-version`,
`GET/POST /v1/admin/catalog-open`.

**CH2 — admin app ↔ shopkeeper app.** Five distinct sub-channels, all
**offline / out-of-band**:

| Sub-channel | Carrier | Authentication |
|---|---|---|
| CH2a provisioning QR | camera scan of `base64url(payload).base64url(HMAC-SHA256)` | embedded HMAC secret (`lib/data/provisioning.dart`) |
| CH2b `.myhanout` catalog delta | WhatsApp / share / `VIEW` intent | same HMAC secret (`lib/data/catalog_delta.dart:66`) |
| CH2c typed shop code | keyboard | **none** (`lib/screens/shop_entry_screen.dart:72-105`) |
| CH2d JSON catalog export/import | FilePicker / share | **none** (`lib/data/import_export.dart`) |
| CH2e listing bundle (planned, Phase B) | file | SHA-256 + `shop_key` binding (spec only, no code) |

**CH3 — shopkeeper app ↔ server.** Design intent: **none** — the POS flavor is
100 % offline. In practice the network client is compiled into the shopkeeper
APK and the configuration layer defaults to a live URL + token
(`lib/data/sync_config.dart:13-15,33-41`).

### 2.4 Trust boundaries

| ID | From | To | Control (actual) | Weakness |
|---|---|---|---|---|
| TB1 | Internet | catalog server | Caddy TLS, bounded exposure, bearer auth | single shared token; no WAF/rate limit |
| TB2 | catalog server | admin app | shared bearer token, self-asserted `device_id` | token in client; no per-device identity |
| TB3 | admin app | shopkeeper app (QR) | HMAC-SHA256 shared secret | secret shipped in both APKs |
| TB4 | admin app / **any app** | shopkeeper app (file) | HMAC over `.myhanout`; `VIEW` intent | same secret; no user confirmation |
| TB5 | shopkeeper app | catalog server | none (by design) | latent defaults + unguarded client methods |
| TB6 | admin app | third-party APIs (OFF, UPCitemDB, MyMemory) | admin-gated for OFF/UPC; **MyMemory ungated** | product names leave the trust boundary |
| TB7 | any installed app | shopkeeper app | exported activity + intent filters | can drive the delta receiver |

---

## 3. Method and severity scale

Each channel was walked with STRIDE. Likelihood × impact → risk → priority.
Severity follows the project scale:

- **Critical** — authentication bypass, RCE, or full data compromise; actively exploitable.
- **High** — significant confidentiality/integrity loss; exploitable with modest effort.
- **Medium** — requires specific conditions; limited blast radius.
- **Low** — defense-in-depth / minor disclosure.
- **Informational** — best-practice deviation.

Priorities: **P0** immediate · **P1** this sprint · **P2** next sprint · **P3** backlog.

---

## 4. CH1 — catalog server ↔ admin app

### 4.1 STRIDE

| Threat | Component | Risk | Attack scenario | Control |
|---|---|---|---|---|
| Spoofing | `/v1/*` auth | **Critical** | Token is public (client + git) → call any endpoint as "admin" | none effective |
| Spoofing | `device_id` | High | Self-asserted, editable in UI; server cannot tell devices apart | none |
| Tampering | `POST /v1/sync` | High | Client controls `updated_at`; write far-future value to pin a row forever | `updated_at` compare only |
| Tampering | `/v1/shops*` | High | Upsert/delete any `shop_key`; set any `catalog_version` | none (any token holder) |
| Repudiation | server | Medium | `--no-access-log`, no audit table → token abuse leaves no trace | none |
| Info disclosure | `/v1/health` | Low | Unauthenticated `open` + `public_url` | none needed, but mute |
| DoS | `POST /v1/sync` | Medium | Unbounded `entries` array, no body limit, no rate limit | per-entry photo cap only |
| Elevation | `/v1/admin/catalog-open` | High | Any token holder can open the global write gate | shared token |

### 4.2 Findings

#### C1-01 — Critical — Production bearer token hardcoded in the client (and git history)

**Evidence**
- `lib/data/sync_config.dart:13-15`
  `static const String defaultUrl = 'https://catalog.myhanout.ma';`
  `static const String defaultToken = 'a07d7ef8…b7e9c';`
- `SyncConfig.load()` falls back to those constants
  (`lib/data/sync_config.dart:33-41`), so a fresh install is *configured*.
- Verified in the shipped artifact:
  `grep -a -c "a07d7ef8…" build/app/outputs/apk/admin/release/app-admin-release.apk` → **1**.
- Git history contains it: commits `3c30335` (“default admin catalog sync URL+token”)
  and `8919062`.

**Exploit path.** Extract the string from the APK (or read the public repo).
`GET /v1/products/search` returns the full catalog; `POST /v1/shops` registers or
**overwrites** any shop; `DELETE /v1/shops/{key}` deletes one;
`POST /v1/shops/{key}/catalog-version` desyncs a shop's delta guard;
`POST /v1/admin/catalog-open` opens writes; `POST /v1/sync` then poisons every
catalog row for every shopkeeper who refreshes.

**Blast radius.** Total: read = whole catalog; write = catalog integrity for all
shops + shop registry + the global write gate. One secret, no rotation, no
revocation, no per-device scope.

**Remediation (P0).**
1. Rotate `CATALOG_TOKEN` on the server **now**; treat the current value as
   compromised (it is in git history — rewriting history does not un-leak it).
2. Delete the constants; require explicit configuration:
```dart
// lib/data/sync_config.dart
static Future<SyncConfig> load() async {
  final prefs = await SharedPreferences.getInstance();
  return SyncConfig(
    url: prefs.getString(_kUrl),      // null until the user sets it
    token: prefs.getString(_kToken),  // null until the user sets it
    lastSyncedAt: prefs.getInt(_kLastSync) ?? 0,
    deviceId: prefs.getString(_kDevice) ?? '',
  );
}
```
3. Store the token in `flutter_secure_storage` (Keystore/EncryptedSharedPreferences),
   not `SharedPreferences`; render it in an obscured field.
4. Server-side: issue **per-device** tokens with scope (`read`, `write`, `admin`)
   and a revocation list; reject the old global token.

#### C1-02 — High — Server shop registry has no ownership/authorization model

**Evidence** `server/app.py`: `register_shop` 224-238 (upsert on conflict),
`list_shops` 241-251, `get_shop` 254-267, `set_shop_catalog_version` 274-290,
`delete_shop` 293-302. Every route calls only `_auth()` — a single global token
check — then operates on **any** `shop_key` from the path/body.

**Exploit path.** With the leaked token (C1-01): `POST /v1/shops/{victim}/catalog-version`
with `{"catalog_version": 999999}` → every subsequent legit `.myhanout` delta for
that shop is rejected by the receiver's base-version guard
(`lib/data/myhanout_file.dart:56-60`) → permanent update DoS. `DELETE /v1/shops/{key}`
removes the shop from the admin distribution list. `POST /v1/shops` with a
victim `shop_key` overwrites `business_name`/`device_id`.

**Blast radius.** All shops; availability + integrity of the catalog delivery chain.

**Remediation (P0).**
- Add a `devices` table with per-device credentials and an `owner`/`role`.
- Authorize per resource: a device token may only touch **its own** `shop_key`;
  only an admin token may `POST/DELETE /v1/shops` or set `catalog_version`.
- Reject `catalog_version` updates that are not monotonically increasing.
- Record an audit row on every mutation (who/device/version/ts).

#### C1-03 — High — `POST /v1/sync` trusts client `updated_at`; unbounded batch

**Evidence** `server/app.py:462-528`. `Entry.updated_at` is client-supplied
(`app.py:135`); conflict rule `if cur and cur[0] > e.updated_at` (`app.py:490`);
`SyncBody.entries` has no length cap (`app.py:152`); only the *photo* is capped
(`MAX_PHOTO_BYTES`, `app.py:33,483`).

**Exploit path.**
- **Poisoning**: push rows with arbitrary `name`/`category`/`photo_base64` for any
  barcode → every shopkeeper that refreshes imports the poisoned values
  (`lib/providers/catalog_provider.dart:67-108`).
- **Update pinning**: push `updated_at = 9e18` → the server keeps the attacker's
  row and rejects every future legitimate edit (`app.py:490-493`).
- **DoS**: a multi-gigabyte JSON body with millions of small entries exhausts
  memory/CPU; there is no rate limit.

**BlastRadius.** Catalog integrity for all shops; availability of the sync endpoint.

**Remediation (P1).**
```python
# server/app.py
MAX_ENTRIES_PER_SYNC = 2000          # reject/4xx above
MAX_BODY_BYTES = 8 * 1024 * 1024     # middleware / Caddy client_max_body_size

# Never trust the client clock for ordering:
now_ms = int(time.time() * 1000)
updated_at = now_ms                  # server-assigned, monotonic per row
# Keep the client value only as an opaque provenance field.
```
Plus per-token rate limiting and a server-side alert on bulk tombstones.

#### C1-04 — Medium — Token at rest / in transit to a user-chosen host

**Evidence** `lib/data/sync_config.dart:43-49` writes the token to
`SharedPreferences` in plaintext; `SyncSettingsDialog`
(`lib/screens/sync_settings_dialog.dart:111-114`) renders it in a plain
`TextField`; `SyncConfig.url` is user-editable and used verbatim in
`CatalogSyncClient` (`catalog_sync_client.dart:113,164,181,209,295`).

**Exploit path.** (a) Any app with device access / a backup extraction reads the
token. (b) A social-engineering step that sets `url` to `https://attacker/`
ships the token to the attacker. (c) Screen capture / shoulder surfing reads the
token field.

**Remediation (P1).** Secure storage; obscured field; on URL change require an
explicit re-confirmation and show the host; pin the expected host for the prod
build; never send the token to a host other than the configured one.

#### C1-05 — Medium — No audit trail or access logging on the server

**Evidence** `server/Dockerfile` runs `uvicorn … --no-access-log`; `app.py` has
no audit table and no logging of who changed what.

**Impact.** Repudiation and no incident detection: a leaked token can be abused
for weeks with no trace. Violates the project's own audit philosophy (the app
side has `audit_log`, the server side has nothing).

**Remediation (P1).** Structured access log (token-id/device, route, status,
bytes, ts) to a file Caddy also captures; a `catalog_audit` table for
`sync`/`shops`/`catalog-open` mutations; alert on `catalog-open` toggles and on
`DELETE /v1/shops`.

#### C1-06 — Low — Information disclosure, weak default, no rate limiting

**Evidence** `app.py:26` `TOKEN = os.environ.get("CATALOG_TOKEN", "dev-token-change-me")`;
`app.py:208-210` `/v1/health` is unauthenticated and returns `open` + `public_url`;
no rate limiting anywhere.

**Remediation (P2).** Fail closed at boot if `CATALOG_TOKEN` is unset (generate
and print a strong secret instead of defaulting); return `{"status":"ok"}` only
on `/v1/health`; add a token-bucket limit on `/v1/*` (Caddy or app middleware).

### 4.3 CH1 — controls that work (keep)

- Constant-time token compare (`app.py:171`, `hmac.compare_digest`).
- Parameterized SQL throughout; `limit`/`offset` clamped (`app.py:371-372`);
  `barcodes` split and bound (`app.py:447`).
- Per-entry photo cap with partial-accept semantics (`app.py:483-485`).
- Read endpoints ungated by `CATALOG_OPEN` (writes-only gate) — deliberate and safe.
- TLS at Caddy, bounded exposure via `expose-catalog.sh`, loopback-only publish,
  internal Docker network, read-only rootfs, `cap_drop: ALL`, non-root runtime.

---

## 5. CH2 — admin app ↔ shopkeeper app

### 5.1 STRIDE

| Threat | Component | Risk | Attack scenario | Control |
|---|---|---|---|---|
| Spoofing | provisioning QR | **Critical** | Secret is in both APKs → mint a QR for any `shop_key` | HMAC (key is public) |
| Spoofing | `.myhanout` delta | **Critical** | Same secret signs deltas → rewrite any device's catalog | HMAC (key is public) |
| Tampering | delta payload | High | Unchecked casts / unbounded photo → crash or OOM | none |
| Tampering | `shop_key` → file path | High | Typed code `x/../myhanout_victim` escapes the intended path | none on this path |
| Repudiation | JSON import | High | Import deletes `audit_log` and replaces economic data | none |
| Info disclosure | MyMemory / `image_url` | Medium | Product names sent to a third party; remote images fetched | none |
| DoS | delta receiver | High | Malformed signed file → unhandled exception | none |
| Elevation | CH2c typed join | Medium | Any code binds the device to any shop key (no verification) | none (by design) |

### 5.2 Findings

#### C2-01 — Critical — Provisioning + delta HMAC secret hardcoded in both APKs

**Evidence**
- `lib/data/provisioning.dart:7`
  `const String _provisioningSecret = 'myhanout-provisioning-secret-change-me';`
- Used for QR tokens (`provisioning.dart:24-31`) **and** for `.myhanout` deltas
  (`lib/data/catalog_delta.dart:66,84`) — one key, two security contexts.
- Verified in shipped artifacts:
  `grep -a -c "myhanout-provisioning-secret-change-me" build/app/outputs/apk/admin/release/app-admin-release.apk` → **1**;
  same command on `build/app/outputs/apk/shopkeeper/release/app-shopkeeper-release.apk` → **1**.
- Git history: commit `8b26365` (“strong shop keys + QR provisioning”).

**Exploit path.** Extract the secret from either APK (it is a `const` string in
`libapp.so`). Then:
1. Mint a provisioning QR for `shop_key = "victim"` / any `business_name`
   (`Provisioning.sign` is a two-line HMAC) → a shopkeeper who scans it binds to
   the attacker's chosen shop identity (`shop_entry_screen.dart:38-71`).
2. Mint a `.myhanout` delta with arbitrary `upserts`/`deletes`
   (`catalog_delta.dart:64-69`) → any device that opens the file rewrites its
   catalog; `deletes` tombstones rows (`catalog_delta.dart:131-133`) and the
   device will not re-fetch them (offline).
3. Because the key is shared, a leaked QR key is also a catalog-write key.

**BlastRadius.** Every device, every shop, the whole catalog — from one string.

**Remediation (P0).**
1. **Rotate** the secret and treat all QR codes and deltas issued before the
   rotation as compromised.
2. Never ship a signing key in the client. Preferred: the admin obtains a
   **short-lived, single-use provisioning token from the server** (server holds
   the secret); the device verifies it with a server-issued public assertion or
   by an online check. If offline verification must stay, derive the key per
   flavor at build time (`--dart-define=PROVISIONING_SECRET=…`) and treat it as
   obfuscation, not a control — say so in the doc.
3. **Separate the contexts**: QR key ≠ delta key, and include a `context` field
   in the signed payload so a QR key cannot sign a delta.
4. Add explicit rotation guidance (the current comment says “rotate by changing
   this constant and rebuilding”, which is how it rotted).

#### C2-02 — High — Unvalidated `shop_key` → filesystem path traversal

**Evidence**
- `lib/data/db.dart:80-84`:
  `shopDbPath(key) => join(await getDatabasesPath(), 'myhanout_$shopKey.db')`
  — the raw key is interpolated into a path.
- `lib/data/db.dart:53-76` `Db.open` does `file.parent.createSync(recursive: true)`
  then `openDatabase(file.path)`; `closeShop` (`db.dart:86-95`) **deletes** `_file`.
- `slugify` (`lib/utils/slug.dart`) restricts keys to `[a-z0-9_]`, but it is
  applied only to admin-created keys — **not** to:
  - the QR payload: `shop_entry_screen.dart:49` `payload['shop_key'].trim().toLowerCase()`;
  - the typed code: `shop_entry_screen.dart:73` `_codeController.text.trim().toLowerCase()`.

**Exploit path (no secret needed).** Open the shop-entry screen and type
`x/../myhanout_<victim>` (or `x/../../databases/anything`). `AppState.shopKey`
becomes that string (`shop_entry_screen.dart:98-104`), `CartProvider` opens
`myhanout_x/../myhanout_<victim>.db`, which resolves to the victim shop's real
database file. `Db.open` creates the intermediate directory, then the app reads
and **writes** the victim's products/sales. `closeShop` on such a key deletes the
resolved file. The same path is reachable with a forged QR (C2-01).

**BlastRadius.** Cross-shop read/write/delete inside the app sandbox; the
file-per-shop isolation guarantee (“the file is the tenant”) is void on this path.

**Remediation (P0).**
```dart
// lib/utils/slug.dart
final _shopKeyRe = RegExp(r'^[a-z0-9_-]{1,64}$');
bool isValidShopKey(String key) => _shopKeyRe.hasMatch(key);

// lib/data/db.dart
static Future<String> shopDbPath(String shopKey) async {
  if (!isValidShopKey(shopKey)) {
    throw ArgumentError('invalid shop key');
  }
  // Never build a path from raw user input: hash it into one safe segment.
  final digest = sha256.convert(utf8.encode(shopKey)).toString().substring(0, 32);
  return join(await getDatabasesPath(), 'shop_$digest.db');
}
```
Apply the same check in `Provisioning.verify` consumers (`_handleToken`),
`_joinShop`, and `ShopProvisioningService.createShop` (defense in depth), and
reject `.` / `..` / `/` explicitly. Note this changes on-disk filenames —
provide a one-time migration for existing `myhanout_<key>.db` files.

#### C2-03 — High — Universal (unbound) catalog delta + extractable signing key

**Evidence** `lib/data/catalog_delta.dart:11-19` states the catalog is universal
and “deliberately *not* bound to a shop — any device may apply any validly signed
delta”; the signature key is C2-01. The receiver's only guard is
`base_version == installed` (`lib/data/myhanout_file.dart:56-60`).

**Exploit path.** One leaked key (C2-01) → one forged delta with
`base_version = <victim's installed version>` applies to **every** shop, because
nothing binds it to a recipient. `target_version` is not validated to be
`base+1`, so an attacker can jump the device's installed version to an arbitrary
value and permanently reject the legitimate next delta (same desync as C1-02).

**BlastRadius.** Catalog integrity for all shops; availability of the delivery chain.

**Remediation (P1).** Bind deltas to a recipient (a `shop_key` or a catalog
epoch + per-shop key) and validate `target_version == base_version + 1` on
receive; keep the universal-catalog decision only if the signing key is
server-held and per-recipient. Add `context` to the signed payload.

#### C2-04 — High — Delta receiver is not defensive (crash / OOM)

**Evidence**
- `lib/data/catalog_delta.dart:72-98` `verify` wraps only `jsonDecode` in
  try/catch; the subsequent casts are unchecked:
  `map['base_version'] as int`, `m['barcode'] as String`, `m['name'] as String`.
- `lib/data/myhanout_file.dart:46-78` `applyJson` has no try/catch; a throw
  propagates to `_applyPendingFile` (`lib/main.dart:233-240`), an unhandled future.
- `catalog_delta.dart:101-108` `base64Decode(photoB64)` is unbounded — the 50 KB
  budget exists only on the **build** side (`lib/services/catalog_delta_service.dart:12`),
  not on receive. A signed multi-megabyte photo is decoded into memory per row.

**Exploit path.** Send a `.myhanout` file (via `VIEW` intent or share) that is
validly signed (C2-01) but has `barcode: 123`, or a 100 MB `photo_base64`.
Result: unhandled `TypeError`/`FormatException` (app crash on launch) or OOM.

**BlastRadius.** Any device that opens the file — availability + potential data loss.

**Remediation (P1).**
```dart
// lib/data/myhanout_file.dart
static Future<String> applyJson(String json, {SettingsService? settings}) async {
  try {
    final store = settings ?? const ConfigSettingsService();
    final verification = CatalogDelta.verify(json);
    if (!verification.ok) return 'rejected: ${verification.error}';
    final d = verification.delta!;
    // --- new guards ---
    if (d.upserts.length > 20000 || d.deletes.length > 20000) return 'rejected: too many rows';
    if (d.targetVersion != d.baseVersion + 1) return 'rejected: bad version jump';
    ...
  } catch (e) {
    return 'rejected: malformed delta';   // never throw into the UI
  }
}
```
Plus in `CatalogDelta.verify`: type-check every field (`is String`, `is int`),
and reject `photo_base64` whose decoded length exceeds `kMaxDeltaPhotoBytes`
**before** decoding.

#### C2-05 — High — Unsigned JSON import wipes the shop and its audit trail

**Evidence**
- `lib/screens/settings_screen.dart:191-214` `_importCatalog` picks any `.json`
  (not gated by `kIsAdmin`) and calls `importCatalogJson`.
- `lib/data/import_export.dart:179-252`: inside one transaction it
  `DELETE FROM audit_log / sale_items / sales / products` (lines 186-189) and
  re-inserts whatever the file contains. `Catalog.fromMap` (lines 56-82) parses
  `shop_key` but **never compares it** to the active shop; there is no checksum
  and no signature.

**Exploit path.** Open Settings → Import catalog → choose a crafted JSON
(`{"version":1,"products":[…]}`). The shop's prices, stock, sales history and the
entire `audit_log` are destroyed and replaced. No confirmation beyond the file
picker, no signature, no shop binding.

**BlastRadius.** Complete loss of commercial data + audit trail for the shop.

**Remediation (P1).** Require `catalog.shopKey == activeShopKey` (abort otherwise);
verify a checksum/signature; **never delete `audit_log`**; make import
additive/transactional with a automatic backup; add an explicit confirmation
dialog listing rows to be replaced. Apply the same rules to the Phase B listing
bundle (the spec already adds `sha256` + `shop_key` binding — implement them as
security controls, not metadata).

#### C2-06 — Medium — The delta receiver auto-applies with no confirmation; any app can drive it

**Evidence**
- `android/app/src/main/AndroidManifest.xml`: two `VIEW` intent filters
  (`application/vnd.myhanout`, and `application/octet-stream` + `pathPattern .*\.myhanout`)
  on an **exported** activity, for `content` and `file` schemes.
- `MainActivity.kt:41-45` `onNewIntent` invokes a `newUri` method channel that
  **no Dart code handles** (`lib/data/myhanout_file.dart` only implements
  `getInitialUri`), so warm-start intents are silently dropped.
- `lib/main.dart:226-240` a cold-start intent is applied automatically; the only
  feedback is a snackbar.

**Exploit path.** A malicious app sends `ACTION_VIEW` with a `content://` URI to
the activity. On a cold start the app reads and applies the file with no prompt.
Without C2-01 the signature check rejects it, so the severity is bounded by the
leaked key — but the UX (silent apply) is itself the problem.

**Remediation (P1).** Show a confirmation dialog (shop, base→target version,
upsert/delete counts, sender app) before applying; handle `newUri` or remove the
call; keep the activity exported but validate the calling package.

#### C2-07 — Medium — Provisioning token is reusable and spoofable in display identity

**Evidence** `lib/data/provisioning.dart:41-63` — no nonce tracking, TTL only
(`defaultTtl` 30 min, up to 7 days offered in `provisioningTtlChoices`); the
payload carries `business_name`, which the receiver stores verbatim
(`shop_entry_screen.dart:59-60`). The Phase B spec (§3.1) explicitly leaves
single-use out of scope.

**Impact.** An intercepted QR works again within its TTL; a forged QR sets an
arbitrary shop display name.

**Remediation (P2).** Track spent nonces (server registry or on-device) for
high-value joins; default to the shortest TTL; show the shop key on the QR
dialog and require a tap-to-confirm.

#### C2-08 — Medium — Release builds signed with the debug keystore

**Evidence** `android/app/build.gradle.kts:43`:
`signingConfig = signingConfigs.getByName("debug")` inside `buildTypes.release`.
The debug key is public and shared across every debug build.

**Impact.** No authentic release identity: a third party can produce an APK
signed with the same key and distribute it as an “update”; also incompatible
with Play App Signing and with any future key rotation.

**Remediation (P1).** Create a dedicated release keystore (backed up offline),
reference it from a non-committed properties file, and never ship a
debug-signed release. Treat already-distributed debug-signed releases as
untrusted.

#### C2-09 — Medium — Third-party egress and server-driven remote content

**Evidence**
- `lib/data/translation_service.dart:24-41` sends the raw product name to
  `api.mymemory.translated.net` (HTTPS, no key) from the admin capture dialog
  (`lib/screens/capture_dialog.dart:91-105`) — product names leave the trust
  boundary, with no consent or logging.
- `lib/screens/browse_page.dart:269-286` renders `image_url` from server data
  with `Image.network` — the client fetches whatever host the catalog row names.

**Impact.** Catalog/business data exfiltration to a third party; if the catalog
server is compromised (C1-01/C1-03), shopkeeper devices become beacons to
attacker-chosen hosts.

**Remediation (P2).** Gate translation behind an explicit user action (it is)
plus a privacy note, or self-host; allowlist image hosts or proxy image fetches.

### 5.3 CH2 — controls that work (keep)

- HMAC-SHA256 with `Random.secure()` nonce, constant-time comparison, per-token
  `ttl_seconds` and a 60 s clock-skew guard (`provisioning.dart`).
- Base-version guard on delta apply (`myhanout_file.dart:56-60`) — prevents
  half-apply and replay after a version advance.
- Deltas carry catalog fields only; `applyCatalogPhoto` touches only
  `photo`/`photo_source` where `photo IS NULL` (`db.dart:245-257`) — price/stock
  are genuinely never overwritten by a delta (verified).
- Separate `applicationId` per flavor → separate `shared_preferences` namespaces.
- Photo budget enforced on the build side (`catalog_delta_service.dart:12`).

---

## 6. CH3 — shopkeeper app ↔ server

### 6.1 Verified: the POS read/scan paths are offline

This is a **positive** finding, verified in code and in the shipped artifact:

- Checkout scan resolves locally only: `lib/screens/checkout_screen.dart:33-34`
  → `CartProvider.findByBarcode` (SQLite).
- `CartProvider.lookupProduct` returns null when `!kIsAdmin`
  (`lib/providers/cart_provider.dart:110-111`) — OFF/UPC lookups are tree-shaken out.
- Inventory browse uses `BrowsePage(localOnly: true)`
  (`lib/screens/inventory_screen.dart:200-207`).
- `main.dart:102-104` only calls `loadSyncConfig()` in the admin flavor.
- Artifact check on `build/app/outputs/apk/shopkeeper/release/app-shopkeeper-release.apk`:
  `catalog.myhanout.ma` → 0, `Bearer ` → 0, `mapper-owner-01` → 0,
  `v1/products/search` → 0, `sync_token` → 0; while `myhanout/view` → 1 and
  `myhanout-catalog-delta` → 1 (the receiver is intentionally present).

### 6.2 Findings

#### C3-01 — High — The offline lock is a tree-shaking accident, not a control

**Evidence**
- `lib/data/sync_config.dart:33-41` — `load()` falls back to the baked
  `defaultUrl`/`defaultToken`, so `isConfigured` is **true on a fresh install**
  even though the user never configured anything.
- `lib/providers/catalog_provider.dart:67-108` (`resolveFromServer`),
  `:118-156` (`browseServer`), `:246-249` (`syncNow`) are compiled into the
  shopkeeper flavor and contain **no `kIsAdmin` guard**. They are currently
  unreachable from shopkeeper UI, but any future call site — or a build that
  drops `kIsAdmin` — silently turns the POS into a network client using the
  production token.
- `ShopProvisioningService.createShop` defaults to `registerOnServer: true`
  (`lib/data/shop_provisioning_service.dart:24,44-53`); only the current callers
  pass `false` (settings) or are admin-gated (shop entry).

**Why it matters.** The invariant “the shopkeeper never talks to the server” is
the foundation of the whole delivery design (offline lock, no server-side
listing). Today it holds because no shopkeeper screen calls those methods and
because AOT tree-shakes the token string — both fragile, neither tested.

**Remediation (P0).**
```dart
// lib/build_config.dart
/// Network egress is an admin-flavor capability, not a runtime option.
const bool kNetworkEnabled = kIsAdmin;

// lib/providers/catalog_provider.dart
Future<CatalogPrefill?> resolveFromServer(String barcode) async {
  if (!kNetworkEnabled) return null;
  ...
}
Future<CatalogBrowseResult?> browseServer({...}) async {
  if (!kNetworkEnabled) return null;
  ...
}
Future<bool> syncNow() async {
  if (!kNetworkEnabled) return false;
  ...
}
```
Make `SyncConfig.isConfigured` false unless the user explicitly set both fields
(see C1-01), and add a regression test that pumps the shopkeeper app and asserts
zero sockets / zero `http` calls (a `HttpOverrides` global that fails the test
on any request is a cheap, strong guard).

#### C3-02 — Medium — The shopkeeper APK embeds the catalog trust root

**Evidence** artifact check: `myhanout-provisioning-secret-change-me` → **1** and
`myhanout-catalog-delta` → **1** in the shopkeeper release APK; `myhanout/view`
and `getInitialUri` → 1. The delta receiver and its signing key are therefore
in the offline device.

**Impact.** Compounding factor for C2-01/C2-03: the offline device is remotely
catalog-editable by anyone who can hand it a file.

**Remediation (P1).** Same as C2-01; additionally consider a distinct
shopkeeper-flavor key and a server-held root for delta signing.

#### C3-03 — Medium — Server-driven remote content enters the shop

**Evidence** `CatalogRow.imageUrl` / `brand` / `license`
(`lib/models/catalog_row.dart:14-20`) come straight from server JSON;
`browse_page.dart:269-286` loads `image_url` with `Image.network`; the server's
`search` returns `image_url` unvalidated (`server/app.py:352-426`).

**Impact.** A compromised server (or leaked token + `POST /v1/sync`) can make
every shopkeeper device fetch attacker-chosen URLs, and can inject arbitrary
names/categories/photos into the local catalog.

**Remediation (P2).** Allowlist image hosts (or proxy and cache), validate/limit
`image_url` server-side, and treat catalog rows as untrusted display data.

#### C3-04 — Low — Self-asserted device identity

**Evidence** `lib/data/sync_config.dart:26,39` default `mapper-owner-01`,
editable in `SyncSettingsDialog`; sent as `device_id`
(`catalog_sync_client.dart:94,148`). The server stores it
(`server/app.py:55,232`) but never verifies it.

**Impact.** No device-level attribution or revocation; combined with a shared
token, one leaked credential is indistinguishable from the legitimate admin.

**Remediation (P2).** Per-device credentials (C1-01) + a server device registry.

---

## 7. Cross-cutting findings

| ID | Sev | Finding | Evidence | Priority |
|---|---|---|---|---|
| X-01 | Medium | `Audit.log` swallows all failures → the audit trail can be silently lost; `importCatalogJson` deletes `audit_log` | `lib/data/audit.dart:37-40`; `import_export.dart:186` | P2 |
| X-02 | Info | `Catalog.fromMap` accepts missing/extra fields silently; no schema validation on import | `import_export.dart:56-82` | P3 |
| X-03 | Info | Seed validation checks only the 16-byte SQLite magic, not `PRAGMA quick_check` as the plan claims; a truncated-but-magic-valid seed is promoted | `catalog_seed_loader.dart:69-85` vs `docs/catalog-network-enduser-plan.md` | P3 |
| X-04 | Info | `Db.closeShop` deletes the DB file and is unreferenced outside `db.dart` — a footgun once path traversal is fixed | `db.dart:86-95` | P3 |
| X-05 | Info | Delta canonicalization relies on decode→`jsonEncode` key order; a different JSON producer (e.g. Python `ensure_ascii`) breaks verification | `catalog_delta.dart:72-98` | P3 |
| X-06 | Positive | Parameterized SQL everywhere; no string-concatenated SQL with user input | `db.dart`, `catalog_db.dart`, `app.py` | — |
| X-07 | Positive | WAL, file-per-shop isolation, base-version guard, separate SharedPreferences namespaces | `db.dart:39`, `main.dart`, gradle | — |

---

## 8. Prioritized risk register (consolidated)

| ID | Channel | Finding | STRIDE | Sev | Likelihood | Priority |
|---|---|---|---|---|---|---|
| C1-01 | 1 | Prod bearer token hardcoded in client + git | Spoofing | **Critical** | High | **P0** |
| C2-01 | 2 | Provisioning/delta HMAC secret in both APKs + git | Spoofing | **Critical** | High | **P0** |
| C2-02 | 2 | `shop_key` path traversal (typed join, no secret) | Tampering | High | High | **P0** |
| C3-01 | 3 | Offline lock not enforced; defaults make `isConfigured` true | Spoofing | High | Medium | **P0** |
| C1-02 | 1 | Shop registry: no ownership / any-token mutation | Elevation | High | Medium | **P0** |
| C1-03 | 1 | Sync trusts client `updated_at`; unbounded batch; no rate limit | Tampering/DoS | High | Medium | P1 |
| C2-03 | 2 | Universal unbound delta + extractable key | Tampering | High | Medium | P1 |
| C2-04 | 2 | Receiver: unchecked casts, unbounded photo decode | DoS | High | Medium | P1 |
| C2-05 | 2 | Unsigned import wipes shop + audit_log | Tampering/Repudiation | High | Medium | P1 |
| C2-08 | 2 | Release APKs debug-signed | Supply chain | Medium | High | P1 |
| C1-04 | 1 | Token plaintext at rest; editable URL; visible field | Info disc. | Medium | Medium | P1 |
| C1-05 | 1 | No server audit / access log | Repudiation | Medium | High | P1 |
| C2-06 | 2 | Silent auto-apply of VIEW intents; `newUri` unhandled | Tampering | Medium | Medium | P1 |
| C3-02 | 3 | Trust root embedded in the offline APK | Spoofing | Medium | Medium | P1 |
| C2-07 | 2 | QR reusable within TTL; spoofable business name | Spoofing | Medium | Medium | P2 |
| C2-09 | 2 | MyMemory egress; arbitrary `image_url` fetch | Info disc. | Medium | Medium | P2 |
| C3-03 | 3 | Server-driven remote content in the shop | Tampering | Medium | Low | P2 |
| C1-06 | 1 | Health info leak; weak default token; no rate limit | Info disc./DoS | Low | Low | P2 |
| C3-04 | 3 | Self-asserted `device_id` | Spoofing | Low | Medium | P2 |
| X-01…X-05 | — | Cross-cutting | — | Info | — | P3 |

---

## 9. Remediation roadmap

### P0 — immediately (credentials are public)

1. **Rotate** `CATALOG_TOKEN` and the provisioning/delta HMAC secret; assume both
   are compromised (git history + shipped APKs).
2. **Remove** `SyncConfig.defaultUrl` / `defaultToken`; `isConfigured` must be
   false until the user configures it.
3. **Validate `shop_key`** everywhere and hash it into the DB filename
   (C2-02 code above).
4. **Gate every server call** behind `kNetworkEnabled`/`kIsAdmin`
   (`resolveFromServer`, `browseServer`, `syncNow`, `registerShop`) and add a
   zero-network regression test for the shopkeeper flavor.
5. **Server**: per-device scoped credentials; reject the rotated-out global token.

### P1 — this sprint

6. Server: resource ownership + monotonic `catalog_version` + audit table +
   access logs + rate limits + body/entry caps (C1-02/03/05).
7. Deltas: recipient binding + `target == base + 1` + receive-side size/type
   validation (C2-03/04).
8. Import: shop binding, checksum, no `audit_log` deletion, confirmation (C2-05).
9. Receiver: confirmation dialog, handle/remove `newUri`, validate caller (C2-06).
10. Release signing with a dedicated keystore (C2-08).

### P2 — next sprint

11. Secure storage for the token; obscured field; URL-change confirmation (C1-04).
12. Single-use / short-lived provisioning (C2-07); translation consent + image
    host allowlist (C2-09, C3-03).
13. Health endpoint minimalism + fail-closed default secret + rate limiting (C1-06).

### P3 — backlog

14. Import schema validation (X-02); real `PRAGMA quick_check` on the seed (X-03);
    remove or guard `closeShop` (X-04); document the canonicalization rule (X-05).

---

## 10. Residual / accepted risks (locked decisions — restated, not re-litigated)

These are deliberate architecture choices; the register above prices the *secrets
and code around them*, not the decisions themselves.

- **Universal catalog, deltas not shop-bound** (`docs/backlog.md`, Phase B §0):
  accepted for catalog semantics; the security cost is C2-03 and it should be
  revisited if the catalog becomes shop-specific.
- **Manual file delivery (WhatsApp/share) instead of HTTP push**: accepted for
  offline operation; it moves the trust problem to the file signature, which is
  why C2-01 is Critical.
- **Listing bundle not HMAC-signed** (Phase B §1.2): accepted for *economic* data;
  the spec's `sha256` + `shop_key` binding must be implemented as real controls
  (and the current JSON import has neither — C2-05).
- **Token in `SharedPreferences` “acceptable for v1”** (`docs/catalog-network-enduser-plan.md`
  risk 10): **no longer acceptable** now that the token is the production token
  and is shipped in the admin APK — see C1-01/C1-04.

---

## 11. Security test plan (add these)

| Test | Channel | Asserts |
|---|---|---|
| `SyncConfig.load()` with empty prefs | 3 | `isConfigured == false`; no default URL/token |
| Shopkeeper widget test under `HttpOverrides` that throws | 3 | zero network requests during browse/scan/join |
| `isValidShopKey` unit test | 2 | rejects `..`, `/`, `\`, absolute paths, >64 chars |
| `Db.open('../../x')` | 2 | throws `ArgumentError`; no file created outside `databases/` |
| `Provisioning.forge` test | 2 | a token signed with a *wrong* key is rejected; expired/future-dated rejected |
| `CatalogDelta.verify` fuzz | 2 | wrong types / huge `photo_base64` / bad version jump → `failed`, never throws |
| `MyhanoutFile.applyJson` malformed | 2 | returns a rejection string; no unhandled exception |
| `importCatalogJson` wrong shop | 2 | aborts; `audit_log` untouched |
| Server: wrong-scope token | 1 | `POST /v1/shops/{other}` / `catalog-open` → 403 |
| Server: batch/DoS | 1 | `entries > cap` → 4xx; body > cap → 413 |
| CI: grep the release APKs for the secrets | all | fail the build if either secret appears |

---

## Appendix A — verification evidence (re-runnable)

```bash
# 1. Secrets in shipped artifacts
grep -a -c "a07d7ef88372d390615a90f1c8acfbcc89724f65a11283cd77e59a7c148b7e9c" \
  build/app/outputs/apk/admin/release/app-admin-release.apk            # -> 1
grep -a -c "myhanout-provisioning-secret-change-me" \
  build/app/outputs/apk/shopkeeper/release/app-shopkeeper-release.apk   # -> 1

# 2. Offline lock: no server markers in the POS APK
for p in catalog.myhanout.ma "Bearer " mapper-owner-01 v1/products/search; do
  grep -a -c -- "$p" build/app/outputs/apk/shopkeeper/release/app-shopkeeper-release.apk
done                                                                 # -> all 0

# 3. Secrets in git history
git log --oneline -S "a07d7ef88372d390615a90f1c8acfbcc89724f65a11283cd77e59a7c148b7e9c" -- lib/
git log --oneline -S "myhanout-provisioning-secret-change-me" -- lib/
```

Note on (1)/(2): Flutter release APKs store `lib/*/libapp.so` uncompressed, so
`grep -a` over the APK reliably finds AOT string constants; a hit is conclusive,
and for the POS APK the absence is corroborated by the code-path analysis in §6.1.

## Appendix B — key files

| File | Role |
|---|---|
| `lib/data/sync_config.dart` | baked URL/token, plaintext prefs |
| `lib/data/catalog_sync_client.dart` | CH1 client, `Bearer` header |
| `lib/data/provisioning.dart` | CH2a/CH2b HMAC secret, QR verify |
| `lib/data/catalog_delta.dart` | `.myhanout` sign/verify/apply |
| `lib/data/myhanout_file.dart` | delta receiver + base-version guard |
| `lib/data/db.dart` | per-shop path derivation, `closeShop` |
| `lib/data/import_export.dart` | unsigned JSON import/export |
| `lib/data/catalog_seed_loader.dart` | seed bootstrap |
| `lib/providers/catalog_provider.dart` | server browse/resolve/sync (ungated) |
| `lib/screens/shop_entry_screen.dart` | QR + typed join (unvalidated key) |
| `lib/screens/settings_screen.dart` | import entry point (not admin-gated) |
| `android/app/src/main/kotlin/com/myhanout/MainActivity.kt` | `readUri`, `newUri` |
| `android/app/src/main/AndroidManifest.xml` | exported `VIEW` intent filters |
| `android/app/build.gradle.kts` | flavors, debug-signed release |
| `barcode-mapper/server/app.py` | CH1/CH3 server |
