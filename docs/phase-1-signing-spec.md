# Phase 1 — Per-admin signing keys (root + admins, QR-distributed directory)

**Status:** written spec (no code) · **Owner:** personal · **Date:** 2026-11-16
**Gates:** the ~8 h phase-1 implementation.
**Parent:** `docs/per-admin-keys-strategy.md` (decisions D1–D10, distribution option (i)).
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

The root key never signs shop-facing artifacts, so it is used rarely ⇒ less exposure.
**No private key is ever committed, logged or put in an APK.**

## 2. Signers directory

`assets/signers.json` — baked initially, replaced only by scanning a directory QR.

```jsonc
{
  "version": 3,                       // monotonic; a lower version is ignored
  "updated_at": 1718000000000,
  "signers": [
    {"id": "founder-admin", "name": "Manu", "role": "founder",
     "public_key": "<base64url 32 B>"},
    {"id": "admin-2", "name": "Sara", "role": "admin",
     "public_key": "<base64url 32 B>"}
  ]
}
```

Envelope (same shape as the existing QR token):
`base64url(payloadJson) . base64url(ed25519_signature)` — signed by the **root** key.
Verified against the **baked root public key**, which ships as a Dart const in
`lib/data/signing.dart` (a public key, so not a secret).

## 3. Sign / verify API

`lib/data/signing.dart` (new):
- `Future<SignersDirectory> loadDirectory()` — baked asset, then the scanned override.
- `VerifyResult verifyArtifact(String json, SignersDirectory dir)` — returns
  `{ok, signer, error}` where `error ∈ {not-json, bad-signature, unknown-signer, tampered}`.
- `Future<String> signArtifact(Map<String, dynamic> payload, SignerKey key)` — appends
  `signature` last.
- Key generation + storage: `generateSigner()`, private key persisted in the app's private
  store. **Phase 1 uses `shared_preferences`** (device sandbox is the boundary); secure
  storage (Keystore/Keychain) is a later hardening, noted in §8.

## 4. Provisioning QR (per-admin)

```jsonc
{
  "shop_key": "maison-du-marche",
  "business_name": "Maison du Marché",
  "issued_at": 1718000000000,
  "nonce": "A3F9K2Q7",
  "ttl_seconds": 1800,
  "signer_id": "founder-admin"        // NEW: who provisioned
}
```
Signed by the **issuing admin's** key. The shopkeeper:
1. verifies the signature against the directory (hard reject on unknown signer),
2. records `provisioned_by = <signer display name>` (new `Config` map, `shop_key → name`),
3. stores nothing else about the token (unchanged).

## 5. Catalog delta

Payload gains `signer_id`; the HMAC is replaced by an Ed25519 signature over
payload-minus-signature (same canonical pattern: append `signature` last, strip first).

Verify chain (all offline):
```
delta.signer_id ──▶ public key from directory ──▶ verify signature
directory itself ──▶ baked root public key ──▶ verify signature
```

**Unknown signer ⇒ hard reject** with
`"unknown signer — scan an updated directory from your admin"`. Nothing is applied.
On success: `catalog.db` gains `signer_log(id, version, signed_by, applied_at, entry_count)`.

## 6. Directory distribution — QR only (decision (i))

- The **admin app** renders the directory as a QR (built from the server registry — phase 3;
  in phase 1 it is built by `tool/gen_signer_keys.dart` and baked).
- The **shopkeeper** scans it with the existing `QrScanPage`, verifies it with the baked root
  key, and replaces the directory **only if `version` is higher**.
- No file channel for trust material, no API call — the shopkeeper's trust root changes only
  by scanning an admin's screen in person.

## 7. Migration from the shared HMAC

`_provisioningSecret` is **compromised** (git history + shipped APKs) ⇒ hard cutover:
1. Generate root + founder-admin (+ admin) keypairs with the tool.
2. Bake `assets/signers.json` (public halves only).
3. Ship the root public key in `lib/data/signing.dart`.
4. Sign QR/delta with the admin keys.
5. **Delete** the HMAC secret and its code paths; rebuild both flavors.
6. Re-issue QRs (old ones are TTL-bound anyway) and re-issue any pending delta.

## 8. Files touched

| File | Change |
|---|---|
| `pubspec.yaml` | `+ cryptography` (**done**) |
| `lib/data/signing.dart` | **new** — Ed25519 sign/verify, directory model, baked root public key |
| `lib/data/signers_directory.dart` | **new** — load / scan / replace / version guard |
| `lib/data/provisioning.dart` | QR payload + `signer_id`; Ed25519; remove the HMAC secret |
| `lib/data/catalog_delta.dart` | payload + `signer_id`; Ed25519; hard reject |
| `lib/data/myhanout_file.dart` | directory → signer → artifact verify chain |
| `lib/data/config.dart` | `provisioned_by` map |
| `lib/screens/shop_entry_screen.dart` | directory-QR scan; record `provisioned_by` |
| `assets/signers.json` | **new** — baked directory |
| `tool/gen_signer_keys.dart` | **new** — keypair generation; prints the public half |
| `test/poc/ed25519_poc_test.dart` | **done** |
| tests | verify-chain + hard-reject + version-regression |

**Out of scope (phase 2/3):** attribution UI, listing-bundle signing (closes C1), admin
management UI, server registry endpoints, secure key storage.

## 9. Acceptance criteria

1. `tool/gen_signer_keys.dart` generates a keypair; the public half is printed for
   `signers.json`, and `git grep` finds **no** private-key material anywhere in the tree.
2. The baked directory verifies against the root key; a one-byte tamper is rejected.
3. An artifact signed by a **listed** admin verifies; one signed by an **unknown** key is
   hard-rejected with the "unknown signer" message and nothing is applied.
4. A scanned directory QR replaces the directory and bumps `version`; a **lower** version is
   ignored.
5. After a signer is removed, their QR/delta is rejected.
6. The HMAC secret is gone from the tree, and **both release APKs grep-clean** for it.
7. The shopkeeper still makes **zero** API calls (APK grep + the existing guardrail test).
8. `provisioned_by` is recorded and readable from the shop screen.

## 10. Risks

- **Directory staleness** — a new admin cannot reach a shopkeeper until the directory reaches
  the device; the hard-reject message must say so (by design, D9).
- **Root key** — single point of trust on one device; rotation needs an app update.
- **Private keys in `shared_preferences`** — readable on a compromised/rooted device; phase-1
  accepted, Keystore/Keychain later.
- **Dependency** — `cryptography` is pure Dart; verify release-build size/startup before
  shipping (POC covered behaviour, not size).
