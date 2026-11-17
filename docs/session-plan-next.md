# Next working session — myhanout shopkeeper

Written 2026-11-16 at the close of phase 2. The backlog (`docs/backlog.md`) is
the source of truth for *what*; this file is *how to pick up cold*.

## Where we are

- **Repo** `/home/hermes/perso/shopkeeper`, `main`, **0 ahead / 0 behind**
  `origin/main`, HEAD `5a793ca`. Working tree clean.
- **Gates, actually run:** `flutter analyze` → No issues found;
  `flutter test` → **182/182**.
- **Phases delivered:** phase 1 (Ed25519 signing, criteria 1–18 closed, criterion
  15 recorded N/A) and phase 2 (listing bundle + join + attribution).
- **Both APKs are signed** with the release keystore
  (SHA-256 `67c4aaeb303c704c8ae6b6cd29a48c629b0977e3958b802072f2c3f8f695a690`).

## Before writing any code — read these

1. `docs/backlog.md` — the source of truth.
2. `docs/phase-1-signing-spec.md` §12 — verification evidence and what is
   deliberately N/A.
3. `docs/phase-b-listing-bundle-join-spec.md` §6 — decision log. **D10** (2026-11-16)
   reopens D2: the listing bundle **is** Ed25519-signed. Do not re-litigate.
4. Skill `shopkeeper-development` → `references/security-signing.md` — the two
   artifact channels and the pitfalls hit while building them.

## Next steps, in order

### 1. REL-1 — refresh the release artifacts (~1 h, S)

The release APKs predate phase 2. Do this before anything ships.

```bash
cd /home/hermes/perso/shopkeeper
export ANDROID_HOME=/home/hermes/android-sdk
flutter build apk --release --flavor shopkeeper
flutter build apk --release --flavor admin
bash tool/verify_retired_secrets.sh          # expect 0 hits everywhere
/home/hermes/android-sdk/build-tools/36.0.0/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-shopkeeper-release.apk
```

**Gate:** the grep prints 0 for the HMAC, the baked token and every forbidden
host; `apksigner` shows the SHA-256 above. *Do not trust a green build to prove
the signing — check the artifact.*

### 2. OPS-1 — back up the signer seeds (~15 min, S)

`~/.myhanout-keystore/signers-seeds.txt` is the **only** copy of the root and
signer private keys. The keystore *password* is already on the Windows desktop;
the `.jks` and the seeds are not. Losing the seeds means no new admin or
salesman can ever be authorised.

### 3. TEST-1 — fix the `s5-shop` leak (~30 min, S)

`test/poc/inventory_refresh_poc_test.dart` leaves rows behind, and
`listing_import_test.dart` already works around it. Make the POC test
self-cleaning (delete `catalog.db`/`-wal`/`-shm` and close the shop) so the next
test that shares a key does not inherit them.

### 4. A3 — prod `catalog_version` round-trip (~1 h, S, **blocked**)

Needs the prod bearer token. Server side is `barcode-mapper` (`master`, no
remote). Verify `POST /v1/shops/{key}/catalog-version` then `GET
/v1/shops/{key}` on `:8020`.

### 5. Then choose: parked POS features

E1 clôture de caisse (16 h) · D1–D4 prix conseillé (10 h) · E2 ticket +
imprimante (20 h) · E3 backup auto (12 h) · G1 conflits (8 h).

## Watch-outs carried forward

- **The release keystore password and the seeds have never been printed.** They
  live in `~/.myhanout-keystore/`; `android/key.properties` is git-ignored and
  points at the `.jks` by absolute path.
- **`test/poc/ed25519_poc_test.dart` and friends use their own throwaway trust.**
  Never point a test at the real directory: `Signing.verifyDirectory` checks the
  **baked** root, so a rotated test directory must pass its own `rootPublicKey`.
- **`flutter test` shares one SQLite factory across files.** Any test that opens
  a shop DB must clear it in `setUp`, not just in `tearDown`.
- **Do not bind a catalog delta to a shop.** It is universal by decision; the
  listing bundle is the per-shop channel.
- **The shopkeeper flavor must make zero HTTP requests.** Proven by
  `HttpOverrides` in `security_regression_test.dart`, and by the release-APK
  grep. Both must stay green.
- **Commit messages:** use repeated `-m` flags. A heredoc is on the user's
  denied-command list.
