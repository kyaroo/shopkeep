# Per-admin signing keys + attribution — strategy

**Status:** strategy (design, no code) · **Owner:** personal · **Date:** 2026-11-16
**Gates:** the ~18 h of signing/attribution work below.
**Triggered by:** `docs/security-risk-analysis.md` — C2-01 (one shared HMAC secret in both
release APKs), C2-03 (universal delta + extractable key), and the open C1 (listing bundle
has no HMAC).

## 0. Locked decisions (from the user, 2026-11-16)

| # | Decision |
|---|---|
| D1 | **Asymmetric keys** (Ed25519). Private keys never leave their owner's device. |
| D2 | **Founder first, then admins** — the founder creates/approves admins. |
| D3 | **Server holds the signer registry**; the **shopkeeper makes no API call** — it verifies offline against a local copy. |
| D4 | **Per-admin provisioning** — the QR records which admin provisioned the shop. |
| D5 | **Attribution** — every applied change records who signed it. |

## 1. The problem

- One shared HMAC secret (`lib/data/provisioning.dart`) signs provisioning QRs **and** catalog
  deltas. It is compiled into both APKs and is in git history ⇒ **compromised by design**.
- A delta carries no signer identity, so a push cannot be attributed.
- The listing bundle (planned) has no signature at all (open question C1).

## 2. Trust model — a two-level mini-PKI

```
root key (founder)  ──signs──▶  signers directory  ──lists──▶  admin public keys
                                      │
                                      ▼
       artifact (delta / listing / QR) signed by an admin key
```

- **Root key** — Ed25519, founder's device only. Public half **baked** into both APKs.
- **Admin key** — Ed25519, one per admin, generated **on that admin's device**. Public half
  published in the directory.
- **Signers directory** — `{version, signers:[{id,name,role,public_key}], updated_at}`,
  signed by the root key. Baked initially (`assets/signers.json`), **updatable offline**
  via a `myhanout-signers` file (same VIEW-intent channel as deltas).
- **No secret ever sits on a shopkeeper device** — only public keys. A compromised
  shopkeeper cannot forge, and cannot impersonate an admin.

### Verification chain (fully offline)
1. Verify the **directory** against the baked **root public key**. Unknown/tampered ⇒ reject.
2. Look up `signer_id` in the directory; verify the **artifact** against that public key.
3. Unknown signer ⇒ reject with *"unknown signer — request an updated directory"*.

## 3. What changes per artifact

| Artifact | Today | After |
|---|---|---|
| Provisioning QR | `base64url(payload).base64url(HMAC)` | + `signer_id`; Ed25519 signature |
| `.myhanout` catalog delta | HMAC over payload−signature | + `signer_id`; Ed25519 signature |
| `myhanout-listing-v1` bundle | `shop_key` + `sha256`, **no HMAC** (C1 open) | + `signer_id`; Ed25519 signature — **settles C1** |
| Signers directory | — | new, root-signed, offline-updatable |

Payload/verify keep the existing canonical pattern (sign payload-minus-signature, append
`signature` last, strip first) — only the algorithm and the `signer_id` change.

## 4. Attribution ("committed in their name")

- **Shop side:** every listing change writes `audit_log` with `changed_by = <signer name>`
  (the table already exists and is mandatory).
- **Catalog side:** `catalog.db` gains `signer_log(id, version, signed_by, applied_at,
  entry_count)` — one row per applied delta, so "who pushed what, when" survives.
- **Admin side:** the existing push tracker records the author next to each push.
- **Provisioning:** the shop records `provisioned_by = <signer name>` (D4) — a shop's
  history shows which admin set it up.

## 5. Key lifecycle

| Event | Flow |
|---|---|
| **Create admin** | Admin installs the admin APK → keypair generated **on their device** → public key registered (`POST /v1/signers`) → founder approves → founder builds a new root-signed directory → sent to shopkeepers offline |
| **Revoke** | Founder removes the signer → new directory → distributed. Takes effect when a device receives it (offline reality — no silent revocation) |
| **Rotate** | Revoke + add |
| **Admin device lost** | Revoke that `signer_id`; the private key never left the device |
| **Root key compromise** | Rebuild with a new root key (the only case that needs an app update) |

## 6. Server's role (registry, not verification path)

- `GET /v1/signers`, `POST /v1/signers`, `DELETE /v1/signers/{id}` — the registry the admin
  app reads/writes (it has network).
- The founder's app builds the directory from the registry and signs it.
- **The shopkeeper never calls these** (D3) — the server is not on the verification path.

## 7. Migration from the shared secret

- Treat `_provisioningSecret` as **compromised** (git history + shipped APKs). Retire it.
- **Hard cutover** recommended: shipping both schemes keeps the compromised key valid.
  Existing QRs are already TTL-bound; deltas must be re-issued.
- Sequence: root key + directory → sign with admin keys → remove the HMAC → rebuild both
  flavors → re-issue QRs/deltas.

## 8. Risks / trade-offs

- **Directory staleness** — a shopkeeper that never updates rejects a new admin's artifacts.
  Mitigation: explicit error + the founder re-sends the directory.
- **Revocation is not instant** — it propagates only as far as the directory has travelled.
- **Root key = single point of trust** — one device; rotation needs an app update.
- **Dependency** — Ed25519 needs a Dart implementation (`cryptography` package); verify it is
  pure Dart (no platform channel) before committing.
- **Signature size** 64 B — negligible next to a 128 px photo.

## 9. Phasing (~18 h)

| Phase | Scope | Est. |
|---|---|---|
| **1** | Root + admin keys, directory, sign/verify chain, QR + delta signed (keys made by a tool, directory baked) | 8 h |
| **2** | Attribution (`signer_log`, `audit_log.changed_by`, push tracker) + listing bundle signing (closes C1) | 5 h |
| **3** | Admin UI (create/approve/revoke, register, send directory) + server registry endpoints | 5 h |

## 10. Open questions

1. Does the admin app **fetch** the registry from the server, or is the directory built by hand?
2. Stale directory on a shopkeeper: **hard reject** with a clear message (recommended) or accept-with-warning?
3. Does the founder use the **root key** for provisioning too, or a separate founder admin key?
4. Algorithm: **Ed25519** (recommended) or ECDSA P-256?
