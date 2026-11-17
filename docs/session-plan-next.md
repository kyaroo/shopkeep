# Next working session — myhanout shopkeeper

Written 2026-11-17 after the device GUI hardening pass. The backlog
(`docs/backlog.md`) is the source of truth for *what*; this file is *how to pick
up cold*.

## Where we are

- **Repo** `/home/hermes/perso/shopkeeper`, `main`, **0 ahead / 0 behind**
  `origin/main`, HEAD `a402f37`. Working tree clean.
- **Gates, actually run:** `flutter analyze` → No issues found;
  `flutter test` → **187/187**.
- **Delivered so far:** phase 1 (Ed25519 signing, criteria 1–18 closed), phase 2
  (listing bundle + join + attribution), and a device pass that found four
  real defects (FIX-1…FIX-4 in the backlog).
- **On the emulator:** release x64 build installed (sha256 `9ad3d25f…`), shop
  `hanouti`, catalog → 2, 22 products, 20 with real photos, delivered over
  `content://` from signed artifacts.

## Before writing any code — read these

1. `docs/backlog.md` — the source of truth, and its **Watch-outs** (they now
   carry the lessons from this pass).
2. `docs/phase-1-signing-spec.md` §12 — verification evidence.
3. `docs/phase-b-listing-bundle-join-spec.md` §6 — decision log. **D10**
   reopens D2: the listing bundle **is** Ed25519-signed. Do not re-litigate.
4. Skill `shopkeeper-development` → `references/security-signing.md`.

## Next steps, in order

### 1. GUI-1 — sale retry on the device (~30 min, needs the user)

The deadlock fix is installed but **no sale has completed on device yet**.
Caisse → add a product (manual entry or scan) → **Valider la vente**, then read
logcat for `sale completed: N line(s), T cents, shop hanouti`.

Two hung attempts each committed a sale row with **no stock deduction**
(`insertSale` commits before `deductStock`). Either ignore them in Historique or
wipe `hanouti` and re-provision the 20 items (`tool/pick_catalog_sample.py` →
`make_listing_bundle.dart` → `make_catalog_delta.dart`, then two VIEW intents).

### 2. REL-2 — refresh the release artifacts (~1 h, S)

The signed APKs from 15:52/15:57 predate FIX-1…FIX-4. Before anything ships:

```bash
cd /home/hermes/perso/shopkeeper
export ANDROID_HOME=/home/hermes/android-sdk
flutter build apk --release --flavor shopkeeper      # separate invocations
flutter build apk --release --flavor admin
bash tool/verify_retired_secrets.sh                  # expect 0 hits
```

**Gate:** `apksigner verify --print-certs` on the **artifacts** shows SHA-256
`67c4aaeb…a690`. Never trust a green build to prove the signing.

### 3. I18N-1 — confirm the Arabic stock wording (~5 min, needs the user)

`stockQty` ar went `الكمية في المخزون` → `مخزون` to fit the 199 px subtitle
budget. If the original wording matters more, revert and accept ellipsis.

### 4. BUILD-1 — the admin release flake (optional, 30 min)

Still unreproduced: 3/3 admin-only builds succeeded. Both earlier failures ran
admin immediately after shopkeeper in one invocation. Workaround stands: build
the flavors separately. Low priority until it bites a real release.

### 5. Then choose: parked POS features

E1 clôture de caisse (16 h) · D1–D4 prix conseillé (10 h) · E2 ticket +
imprimante (20 h) · E3 backup auto (12 h) · G1 conflits (8 h).

## Watch-outs carried forward

- **A green suite does not mean the app works.** Two of this pass's four defects
  shipped green. Click the app on a **release** build.
- **`uiautomator` sees no Flutter text here.** GUI verification is human or
  logcat — never blind coordinate tapping.
- **Release builds cannot be inspected with `run-as`.** That is why `logInfo`
  exists; use it rather than adding debug hooks.
- **The emulator camera is `emulated`**, so the scanner cannot be poster-driven.
- **The Tailscale link stalls above ~260 MB** — chunk APKs at 15 MB and verify
  the sha256 on both ends.
- **`test/poc/ed25519_poc_test.dart` and friends use their own throwaway trust.**
  Never point a test at the real signers directory.
- **`flutter test` shares one SQLite factory across files.** Any test that opens
  a shop DB must clear it in `setUp`, not just in `tearDown`.
- **Do not bind a catalog delta to a shop.** It is universal by decision; the
  listing bundle is the per-shop channel.
- **The keystore password and the signer seeds have never been printed.** They
  live in `~/.myhanout-keystore/` and on the Windows desktop.
- **Commit messages:** repeated `-m` flags; a heredoc is on the denied list.
