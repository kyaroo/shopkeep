# Next working session — myhanout shopkeeper

> **SUPERSEDED 2026-11-20.** This pick-up guide describes the **b6 four-tab IA**
> (Catalog/Shops/Security/Settings) and the state at `4bd339d` / 234 tests. The
> admin shell is now **three tabs (Shops/Catalog/Settings)** at `fa2f5cd`+ with
> 244 tests. Use `docs/backlog.md` (reconciled 2026-11-20) instead; this file is
> kept only for history.

Written 2026-11-19 after the b6 phase. The backlog (`docs/backlog.md`) is the
source of truth for *what*; this file is *how to pick up cold*.

## Where we are

- **App repo** `/home/hermes/perso/shopkeeper`, `main` = `4bd339d`
  ("b6: global catalog versions, admin tab IA, signer import"), working tree
  clean, **1 ahead of `origin/main`** (not pushed).
- **Server repo** `/home/hermes/perso/barcode-mapper`, `master` = `f64d8e9`,
  no remote, working tree clean.
- **Gates, actually run:** `flutter analyze` → No issues found;
  `flutter test` → **234/234**; `tool/verify_flavor_gates.sh` PASS;
  `tool/verify_catalog_export_gate.sh` PASS;
  `tool/verify_release_bundle.sh release/kits/myhanout-v0.1.0-b6` PASS;
  `tool/verify_retired_secrets.sh` → 0 hits (now scans release kits);
  server `python3 -m unittest discover -s server/tests` → **43/43**.
- **Delivered:** b6 phase — global catalog version model (server generation +
  owner-only version/diff, admin pull/publish with confirmation), admin tab IA,
  signer QR import, Settings-tab hosts settings, server-side signers directory,
  prod + test on hardened `docker compose`.
- **On the emulator:** b6 x64 admin installed and running. **Physical phone:**
  b5 shopkeeper installed; the b6 arm64 shopkeeper is staged in
  `/sdcard/Download/` (install is the tester's; MIUI may need Install via USB).
- **Servers:** prod `127.0.0.1:8020` and test `127.0.0.1:8021`, both healthy
  (`docker compose`, read-only, cap-drop, restart unless-stopped).

## Before writing any code — read these

1. `docs/backlog.md` — the source of truth, and its **Watch-outs**.
2. `docs/catalog-version-routing-plan.md` — the locked version/routing model.
3. `docs/peer-to-peer-distribution.md` — the delivery model.
4. `docs/phase-1-signing-spec.md` §12 — verification evidence.
5. Skill `shopkeeper-development` → `references/security-signing.md`.

## Next steps, in order

### 1. GUI-1 — sale retry on the device (~30 min, needs the user)
The deadlock fix is installed but no sale has completed on device yet.
Caisse → add → **Valider la vente**, then read logcat for
`sale completed: N line(s), T cents, shop …`. The two hung attempts each
committed a sale row with **no stock deduction** — ignore them or wipe and
re-provision.

### 2. GUI-3 — b6 GUI test session (~1 h, needs the user)
Write the script (base: `docs/gui-test-session-2026-11-18.md`, but that one is
b5/superseded). Cover the tab shell, Settings-tab-is-settings (2a), signer
pill, per-shop menu, not-registered card, publish/pull with version
confirmation, role-gated catalog CRUD, and the shopkeeper flavor gate.

### 3. TEST-2 — device smoke pass on a release build (~1 h, recurring)
Cold-launch → apply a signed listing + delta over `content://` → validate a
sale → Inventaire in fr/en/ar → Paramètres → Sauvegarde (shopkeeper: listing +
history; admin: catalog export + the "listing/history live on the shopkeeper
app" note). The suite cannot catch this class of defect.

### 4. Server small items
- **SRV-3** (15 min): set prod `CATALOG_PUBLIC_URL` to `https://catalog.myhanout.ma`
  (currently the loopback default).
- **SRV-1** (~1 h): write the signer-directory rotation runbook.
- **SRV-2** (later): serve the roster so devices can pull it.

### 5. Then choose: parked
5(ii) signer-key-minted token · C2 shopkeeper photo capture · C POS features
(E1 clôture 16 h · D1–D4 prix conseillé 10 h · E2 ticket 20 h · E3 backup 12 h ·
G1 conflits 8 h) · F1/F2 build matrix.

## Watch-outs carried forward

- **A green suite does not mean the app works.** Click the app on a **release**
  build; FIX-1 and FIX-3/FIX-4 shipped green.
- **A `kIsAdmin` gate cannot be tested** (compile-time const) — source-guard it
  (`tool/verify_catalog_export_gate.sh`).
- **`sqflite_common_ffi` ≠ the Android plugin**; a transaction self-deadlock
  passes ffi.
- **`uiautomator` sees no Flutter text here.** GUI verification is human or
  logcat (`logInfo`) — never blind coordinate tapping.
- **Release builds cannot be inspected with `run-as`** — that is why `logInfo`
  exists.
- **The emulator camera is `emulated`**; the scanner cannot be poster-driven.
- **Tailscale stalls above ~260 MB** — chunk APKs at 15 MB, verify sha256.
- **Do not bind a catalog delta to a shop.** It is universal; the listing
  bundle is the per-shop channel.
- **The keystore password and signer seeds have never been printed.**
- **Commit messages:** repeated `-m` flags; a heredoc is on the denied list.
- **Both compose files share project `server`** → each reports the other as an
  orphan. Never `down --remove-orphans` on one.
- **`app.py` is baked into the image** (no bind mount) → code changes need
  `docker compose build` + `up -d`, not just a restart.
- **`release/` is git-ignored** (812 MB of APKs, reproducible from source).
- **The test volume can go root-owned** (e.g. a root-run backup/restore) → the
  app then fails with `attempt to write a readonly database`; fix with
  `docker exec -u root barcode-mapper-catalog-test chown -R 10001:999 /data`.
