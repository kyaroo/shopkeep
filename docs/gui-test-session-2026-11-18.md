# GUI test session — 2026-11-18 (b5 kit)

Focused on today's changes: shop-info read/edit, paged shop list, admin catalog
tab consolidation, per-role server tokens, and the offline flavor gate.
Executed in **another session** by the user (human observation — no vision,
no assistant screenshots). Record PASS/FAIL and exact on-screen text per test.

## Build / environment
- Kit: `release/kits/myhanout-v0.1.0-b5/` (both flavors, versionCode 5,
  signed by the pinned founder cert). built 2026-11-18 20:41 UTC.
- Emulator: **admin/founder**, x86_64. The b5 kit is arm64 only — use the
  previously staged x64 admin build with `--dart-define=ADMIN=true`, or build
  a fresh b5 x64 admin. Confirm the app opens on Admin home, not join-shop.
- Physical device: **shopkeeper**, arm64, from the b5 kit. MIUI install may
  need "Install via USB" / "USB debugging (Security settings)".
- Admin app Sync settings: `http://127.0.0.1:8020` + the OWNER token
  (emulator loopback reaches host). Shopkeeper: no server config, stays offline.
- Server: `curl http://127.0.0.1:8020/v1/health` → 200. `hanoutihamid`
  registered at catalog_version 1; `h` v0 and `hamidyougo` v3 also present.

## A — Admin/founder on emulator

| ID | Test | Steps | Expected |
|---|---|---|---|
| A1 | Three-dot menu | Open the horizontal-dots menu on Admin home | Settings **and** Shop info entries present; report exact labels |
| A2 | Shop info — load | Menu → Shop info → type `hanoutihamid` → Load info | "Provisioned by" card with Signer ID / Name / Role / Catalog version, all read-only (em dashes for unset); Catalog version = 1; four editable contact fields below |
| A3 | Shop info — save | Edit City + Owner name → Save changes | "Shop info saved." snackbar; reopen + reload shows persisted values |
| A4 | Shop info — no-op | Save without edits | "Nothing to save — edit a contact field first." |
| A5 | Shop info — not found | Load `does-not-exist` | Not-found message naming that key |
| A6 | Shop info — auth | Clear/wrong token, load a shop | Authentication-failed message pointing to Sync settings |
| A7 | Catalog tab | Open Catalog tab, do not type in search | List opens populated (50-row pages); scroll loads more |
| A8 | Distribute catalog — controls | Catalog tab → Distribute catalog | Search hint "Search shops by name or key…"; version chips All / Never reported (v0) / v1 / v2+; group headers "Catalog version N"; "Showing X of Y shops"; Load more |
| A9 | Distribute catalog — search/filter | Search `hanouti`; then gibberish; then v1 chip | `hanouti*` rows; "No shops match this search."; only v1 shops |
| A10 | Shop count from server | Inspect list | At least h (v0), hamidyougo (v3), hanoutihamid (v1) — proves GET /v1/shops/search + paging |
| A11 | Distribution guard | With an active founder/admin signer, generate a delta for hanoutihamid (1→2) and share | No "no boutique registered" error; signed file produced |

## B — Shopkeeper on physical device

| ID | Test | Steps | Expected |
|---|---|---|---|
| B1 | Menu flavor gate (critical) | Open three-dot menu | Settings only — **no Shop info entry**. If present: blocking defect, stop |
| B2 | Offline | Airplane mode; open app, browse catalog, make a sale | No network/auth prompt; catalog and sale work |
| B3 | Seed catalog | Fresh install / first launch | Catalog list populated from APK seed, version 1 |
| B4 | Signed delta apply | Receive the A11 delta out-of-band, import in shopkeeper | Applied with signer attribution; version advances to 2; re-import is a no-op / already applied |
| B5 | Business name read-only | Settings | Business name shown read-only — no editable field, no Save button |

## Blocking rules
- If B1 fails, stop the session — the offline invariant is broken.
- If the x64 admin build is unavailable, skip A and run B only; report the gap.
- No vision/screenshots by the assistant; the user reads screens and reports text.
- logcat (`logInfo`) is acceptable evidence for release-build outcomes.

## Outcome
Record per test: PASS / FAIL + exact on-screen text + any unexpected behavior.
Update this file with results in the executing session; then tick the linked
backlog item GUI-2.
