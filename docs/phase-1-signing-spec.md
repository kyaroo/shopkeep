# Phase 1 — Per-admin signing keys (root + admins + salesman, QR-distributed directory)

**Status:** written spec (no code) · **Owner:** personal · **Date:** 2026-11-16
**Gates:** the ~8 h phase-1 implementation.
**Parent:** `docs/per-admin-keys-strategy.md` (D1–D10, distribution option (i)).
**Review:** `docs/phase-1-signing-review.md` — all Critical/High findings folded in below;
residual items are listed explicitly in §11 rather than dropped.
**Evidence:** `test/poc/ed25519_poc_test.dart` — Ed25519 round-trip, tamper and wrong-key
rejection, measured sizes (public 32 B · private 32 B · signature 64 B). Dependency
`cryptography` added and verified under `flutter test`.

---

## 1. Keys and roles

| Key | Holder | Signs | Private key lives in | Public half |
|---|---|---|---|---|
| **root** | founder | the signers directory only | founder's device | **baked** into both APKs |
| **founder-admin** | founder | provisioning QR, delta, listing bundle | founder's device | in the directory |
| **admin-N** | that admin | same as founder-admin | that admin's device | in the directory |
| **salesman-N** | that salesman | provisioning QR **only** | that salesman's device | in the directory |

**Capabilities** (locked 2026-11-16):

| Role | Provision / join shops | Push catalog delta | Sign the directory |
|---|---|---|---|
| `founder` | ✓ | ✓ | ✓ (root key) |
| `admin` | ✓ | ✓ | ✗ |
| `salesman` | ✓ | **✗** | ✗ |

The root key never signs shop-facing artifacts, so it is used rarely ⇒ less exposure.
A **salesman** is the in-person role: it joins shops and carries the directory QR, and it
cannot touch catalog economics. **No private key is ever committed, logged or put in an APK.**

## 2. Signers directory

`assets/signers.json` holds **the signed envelope**, not a decoded payload, so it can be
re-verified on every load.

```jsonc
// payload (the bytes that get signed)
{
  "format": "myhanout-signers-v1",
  "alg": "ed25519",
  "version": 3,                          // int, monotonic; lower/equal is a no-op
  "updated_at": 1718000000000,             // int, epoch ms; displayed, never used to expire
  "signers": [
    {"id": "founder-admin", "name": "Manu", "role": "founder",
     "public_key": "<base64url, 32 B>"},
    {"id": "salesman-1", "name": "Omar", "role": "salesman",
     "public_key": "<base64url, 32 B>"}
  ]
}
// envelope on disk = base64url(payloadJson) . base64url(ed25519_signature)
```

Field rules: `id` unique, `[a-z0-9][a-z0-9_-]{0,62}`; `name` ≤ 80 chars, display-only;
`role ∈ {founder, admin, salesman}`; `public_key` exactly 32 B base64url; `version` ≥ 1.
**Duplicate `id` or a bad key length ⇒ reject the whole directory.** Verified against the
**baked root public key** (a Dart const in `lib/data/signing.dart` — public, not a secret).

## 3. Canonical bytes and the sign/verify API

**Canonical JSON** (both sides must produce identical bytes):
UTF-8 · **keys sorted** · **no whitespace** · integers only for versions/timestamps ·
**duplicate keys rejected** · sign the **exact bytes transmitted** (for the dotted QR
envelope, sign `payloadJson` itself — never a re-encoding).

`lib/data/signing.dart` (new):
- `Future<SignersDirectory> loadDirectory()` — baked asset, else the persisted override
  **re-verified against the baked root key on every load**; on any mismatch, fall back to
  the baked directory (fail-closed for the override, never for the app).
- `VerifyResult verifyArtifact(String json, {required SignersDirectory dir,
  required String expectedFormat, required Set<String> allowedRoles})` →
  `{ok, signer, error}` with
  `error ∈ {not-json, unknown-format, missing-signature, bad-signature, unknown-signer,
  forbidden-role, malformed-field, stale-version}`.
- `Future<String> signArtifact(Map<String, dynamic> payload, SignerKey key)` — appends
  `signature` last.
- `generateSigner()` — keypair generated **on the device**, private half persisted in the
  app's private store. **Phase 1 uses `shared_preferences`** (see §11); Keystore/Keychain
  later.

## 4. Authorization (roles)

Every artifact carries `format`; the verifier resolves the signer's `role` from the
directory and checks it against the artifact's capability table (§1). Failure is a
`forbidden-role` rejection, e.g. *"Omar is a salesman and cannot push catalog changes"*.
Routing happens on `format` **before** any signature work, so a directory envelope can never
be fed to the provisioning verifier or vice versa.

## 5. Provisioning QR

```jsonc
{
  "format": "myhanout-provision-v1",
  "alg": "ed25519",
  "shop_key": "maison-du-marche",
  "business_name": "Maison du Marché",
  "issued_at": 1718000000000,
  "nonce": "A3F9K2Q7",                    // single-use; recorded on apply
  "ttl_seconds": 1800,
  "signer_id": "salesman-1"               // who provisioned
}
```
Allowed roles: `founder`, `admin`, `salesman`. The shopkeeper:
1. verifies against the directory, and checks the role may provision;
2. rejects a **replayed `nonce`** (nonces persisted per shop, bounded, pruned after the TTL);
3. records `provisioned_by = <signer display name>` and `provisioned_by_id`;
4. keeps `shop_key` validation (`isValidShopKey`) — unchanged.

`business_name` stays **display-only and spoofable** (signed, but the operator reads it from
the screen they are pointing at) — recorded as a residual risk, not a control.

## 6. Catalog delta

```jsonc
{
  "format": "myhanout-catalog-delta",
  "alg": "ed25519",                       // a v1 HMAC and a v1 Ed25519 delta are distinct
  "fileVersion": 2,                        // bumped: the HMAC era is v1
  "signer_id": "admin-2",
  "base_version": 1794500000,
  "target_version": 1794500001,            // MUST equal base_version + 1
  "generated_at": 1794500000,
  "upserts": [ … ], "deletes": [ … ],
  "signature": "…"                         // last, stripped first
}
```
Allowed roles: `founder`, `admin` (**not** salesman).

Verify chain (all offline):
```
delta.signer_id ──▶ role check ──▶ public key from directory ──▶ verify signature
directory ───────▶ baked root public key ──▶ verify signature
base_version == installed  AND  target_version == base_version + 1
```
**Hard reject** on unknown signer / forbidden role / bad signature / version jump — nothing
applied, state unchanged. On success `catalog.db` (bumped to **schema v4**) gains
`signer_log(id, version, signed_by, signed_by_id, applied_at, entry_count, applied_on_shop)`.

## 7. Directory distribution — QR only

- The **admin app** renders the directory as a QR (phase 3: built from the server registry;
  phase 1: built by the tool and baked).
- The **shopkeeper** scans it, verifies with the baked root key, replaces **only if
  `version` is higher**; the previous directory is retained on any failure.
- **Chunking:** a directory that exceeds one QR is split into numbered chunks
  (`index`, `count` in the payload); all chunks must arrive and the reassembled payload is
  verified once. A partial set is rejected.
- No file channel for trust material, no API call — trust changes only by scanning a
  screen in person (a procedural control; see §11).

## 8. Migration checklist

**HMAC removal touches:** `lib/data/provisioning.dart` (secret, `signatureFor`,
`verifySignature`), `lib/data/catalog_delta.dart` (sign/verify), 
`lib/data/shop_provisioning_service.dart` (QR sign). Keep `generateShopKey` (nonce).

**Ripple** (beyond the obvious): `lib/services/catalog_delta_service.dart`,
`lib/services/catalog_push_service.dart`, `tool/make_catalog_delta.dart`,
`tool/make_poc_delta.dart`, `test/poc/catalog_delta_poc_test.dart`,
`test/poc/catalog_version_guard_poc_test.dart`, `test/services/*`,
`test/unit/provisioning_test.dart`, `test/helpers/mock_providers.dart`,
`lib/data/settings_service.dart`.

1. Generate the root keypair (tool; private half imported one-way into the founder device)
   and the founder-admin keypair (**on the founder device** via `generateSigner()`).
2. Bake `assets/signers.json` (envelope) and register it in `pubspec.yaml`.
3. Ship the root public key in `lib/data/signing.dart`.
4. Switch QR + delta to Ed25519; bump `fileVersion`.
5. **Delete** the HMAC secret and its code paths; rebuild both flavors.
6. Bump `CatalogDb` to v4 with `signer_log` in `onCreate` + `onUpgrade`.
7. Re-issue QRs (old ones are TTL-bound) and any pending delta; old APKs in the wild will
   reject them (see §11).

## 9. Files touched

| File | Change |
|---|---|
| `pubspec.yaml` | `+ cryptography` (**done**), `+ assets/signers.json` |
| `lib/data/signing.dart` | **new** — Ed25519, canonical JSON, directory model, baked root key |
| `lib/data/signers_directory.dart` | **new** — load (re-verify) / scan / chunk / replace |
| `lib/data/provisioning.dart` | typed QR payload, `signer_id`, nonce check, Ed25519 |
| `lib/data/catalog_delta.dart` | typed payload, `signer_id`, `fileVersion` 2, Ed25519, `+1` rule |
| `lib/data/myhanout_file.dart` | format → role → directory → signer → verify chain |
| `lib/data/catalog_db.dart` | **v4**: `signer_log` |
| `lib/data/config.dart`, `lib/data/settings_service.dart` | `provisioned_by` / `provisioned_by_id`, used nonces |
| `lib/screens/shop_entry_screen.dart`, `lib/screens/qr_scan_page.dart` | route by `format`; directory scan |
| `assets/signers.json` | **new** |
| `tool/gen_signer_keys.dart` | **new** — root keypair only; private half never printed/written |
| tests | POC (**done**) + the criteria in §10 |

**Out of scope (phase 2/3):** attribution UI, listing-bundle signing (closes C1), admin /
salesman management UI, server registry endpoints, secure key storage.

## 10. Acceptance criteria

1. Tool generates the **root** keypair; the public half goes into `signers.json`;
   **no private-key material** in the tree **or git history** (`git log -S`).
2. The baked directory verifies against the root key; a one-byte tamper — payload **or**
   signature — is rejected.
3. A listed admin's artifact verifies; an unknown key is hard-rejected with the exact
   message, and **DB/prefs state is unchanged**.
4. A scanned directory replaces the directory and bumps `version`; a lower/equal version is
   a no-op; the previous directory survives a bad scan.
5. After a signer is removed **and the device has the new directory**, their QR/delta is
   rejected.
6. HMAC secret absent from tree and history; both release APKs grep-clean; an **HMAC-signed
   delta is rejected** after cutover.
7. Shopkeeper makes **zero** API calls: APK grep markers + the guardrail test extended with
   an `HttpOverrides` that fails any request.
8. `provisioned_by` / `provisioned_by_id` recorded and readable via
   `SettingsService.getProvisionedBy(shopKey)` with a widget test.
9. **A tampered persisted directory override is rejected on load**; the baked directory is
   used. **(CR-01)**
10. `target_version != base_version + 1` is rejected; the installed version is unchanged.
    **(CR-02)**
11. Malformed artifacts (wrong types, duplicate keys, oversized `photo_base64`, too many
    rows) are rejected, never thrown. **(CR-09)**
12. A provisioning QR whose `nonce` was already used is rejected. **(CR-10)**
13. A directory with duplicate `signer_id`s or a bad key length is rejected at load.
14. A directory signed by the wrong root key is rejected and the previous one retained.
15. A signed fixture produced by a **non-Dart** producer verifies in Dart, and vice versa
    (canonical JSON). **(CR-07)**
16. A **salesman** artifact is rejected for a catalog delta (`forbidden-role`), and an
    admin's is rejected for a directory.
17. `signer_log` rows carry version, `signed_by`, `applied_at`, `entry_count`,
    `applied_on_shop`, and are queryable.
18. `assets/signers.json` ships in **both** APKs; the APK is signed with the **release**
    keystore and the baked root fingerprint matches `lib/data/signing.dart`. **(CR-03)**

## 11. Accepted residual risks (explicit)

| Risk | Why accepted / mitigation |
|---|---|
| **Catalog delta stays universal** (C2-03) | Locked product decision (any device may apply any signed delta). The risk report conditioned universality on a **server-held** key, which this design deliberately rejects. Mitigation in phase 1: `target = base + 1` stops version-jump desync. **Residual: one compromised admin key still reaches every shop.** |
| **Installed APKs keep the compromised HMAC** | Old builds can't be patched. Mitigation: forced update / version gate, or accept old APKs as untrusted. Re-issuing deltas is not sufficient. |
| **Release APKs are debug-signed** (C2-08) | Needs a dedicated keystore — a build-infra task, tracked as criterion 18. |
| **Private keys in `shared_preferences`** | Phase-1 boundary is the device sandbox; Keystore/Keychain deferred. |
| **Directory staleness** | A new admin/salesman can't reach a shop until the directory arrives; hard reject says so (D9). |
| **Root key** | Single point of trust on one device; rotation needs an app update. |
| **"In-person QR" is procedural** | It narrows the channel but is not a technical control. |
| **Silent auto-apply of VIEW intents** | Signature still gates it; confirmation dialog deferred. |
| **`business_name` spoofable** | Display-only; the shopkeeper reads it from the screen they face. |
| **Dependency** | `cryptography` is pure Dart; verify release size/startup before shipping. |

## 12. Verification evidence (as of 2026-11-16)

`bash tool/verify_retired_secrets.sh` re-extracts the retired values from git
history on every run and prints **counts only**:

| Check | Result |
|---|---|
| working tree (`lib/ assets/ tool/ test/`) — HMAC / baked token / root private key | **0 / 0 / 0 hits** |
| `app-shopkeeper-release.apk` — HMAC / baked token | **0 / 0 hits** |
| `app-admin-release.apk` — HMAC / baked token | **0 / 0 hits** |
| `app-shopkeeper-release.apk` — `openfoodfacts.org`, `upcitemdb`, `mymemory`, `catalog.myhanout.ma` | **0 hits each** |
| git history | HMAC in 5 commits, token in 8 — **expected and accepted**: history cannot be rewritten without a force-push, so the hard cutover (not history editing) is the mitigation. Old APKs remain readable as untrusted. |

Criteria closed by tests: 2, 3, 4, 5, 7, 8 (accessor + persistence; the
display is phase-2 attribution UI), 9, 10, 11, 12, 13, 14, 16, 17.
Criterion 15 (cross-language vector) is **not applicable**: every producer and
consumer is the same Dart `Signing.canonicalize`, and no non-Dart producer
exists.

**Criterion 18 (release signing) — closed 2026-11-16.** `android/key.properties`
(git-ignored, per-machine) points at a PKCS12 keystore kept outside the repo at
`~/.myhanout-keystore/myhanout-release.jks`; `build.gradle.kts` reads it and
falls back to the debug key when absent, so a fresh clone still builds. Both
release APKs verify with
`apksigner` → SHA-256 `67c4aaeb303c704c8ae6b6cd29a48c629b0977e3958b802072f2c3f8f695a690`,
certificate `CN=myhanout, OU=POS, O=myhanout, L=Marrakech, ST=Marrakech, C=MA`,
valid to 2056-11-08. **The password is backed up on the Windows desktop**
(`Desktop/myhanout-release-keystore-password.txt`, SHA-256 verified). Losing
both the keystore and that password blocks every future update of the
`com.myhanout.*` IDs.

**Baked signers directory rotated 2026-11-16** (`assets/signers.json` → version 2,
signers `founder-admin` (founder), `admin-1` (admin), `salesman-1` (salesman));
the previous demo root/admin keys are burned. Private seeds live outside the
repo at `~/.myhanout-keystore/signers-seeds.txt`. `tool/gen_signer_keys.dart`
never prints them and refuses to write them inside the repo.

Additional defect found and fixed while closing these: the strict JSON parser
indexed past the end of the input (`RangeError` instead of `FormatException`),
so malformed content could have escaped `verify` as an exception. `verify` now
also catches anything that still escapes.
