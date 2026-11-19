# Peer-to-peer app delivery — myhanout

Human-to-human distribution of the signed APKs. No store, no download link, no
server, no auto-update. A new version is announced by a person and handed from
one device to another.

Status: strategy locked 2026-11-18. Decisions: **1b** cert fingerprint only
(no signed manifest, no in-app verify screen) · **2a** Nearby Share → WhatsApp
document → USB seed kit · **3a** tooling + SOP + cards · **4a** founder → admin
→ shopkeeper chain.

> Decision 1b is more specific than the "verify screen" item inside 3a, so the
> in-app screen was dropped. Verification is out-of-band, by the pinned APK
> signing certificate fingerprint and `sha256sum`. This is deliberate and should
> not be "restored" without reopening decision 1.

## Trust model

- The identity of a genuine app is its **APK signing certificate SHA-256
  fingerprint**: `67c4aaeb303c704c8ae6b6cd29a48c629b0977e3958b802072f2c3f8f695a690`.
  It is pinned in `tool/verify_release_bundle.sh` and printed on the install
  cards. A filename, a chat sender, or a checksum typed in a message proves
  nothing.
- Android enforces the strongest part of this for us: an APK signed by a
  different certificate **cannot** update an installed app. The phone will ask
  to uninstall first — that prompt means "stop", not "confirm".
- `RELEASE.txt` and `SHA256SUMS` are plain integrity records, not trust anchors.
  The founder keystore and signer seeds never leave the build host and are
  never given to distribution nodes.
- No signed release manifest and no in-app fingerprint screen by decision 1b.

## Admin app on a fresh install (decision 1a)

The admin APK no longer starts on a create-shop gate. It opens a non-blocking
AdminHome shell with four always-available tabs: Catalog, Shops, Security,
Settings. Catalog browsing (paged, local), catalog management, catalog push and
listing export all live in the Catalog tab — there is no separate Distribution
tab and no catalog shortcut in the Shops tab. Shop creation/join lives in the
Shops tab and is never a gate; the missing-signer banner is informational and
never blocks a surface. Shop-bound data says "No shop selected" instead of
crashing. The universal catalog export, server shop list, signers directory and
settings are reachable with no shop and no signer. The shopkeeper flavor is unchanged: an
empty shopKey still opens its shop-entry screen.

## Installing a signer key on an admin device (decisions 2a, 3a, 4a)

Catalog and listing pushes need an active founder/admin seed on the admin
device. There is no UI that generates one — the founder hands it over:

```bash
cd /home/hermes/perso/shopkeeper
dart run tool/make_signer_seed_qr.dart --signer founder-admin
```

The tool reads the founder's seeds file outside the repo and writes a QR plus a
`.myhanoutseed` fallback file outside the repo. It prints only the public signer
id — never the seed. Hand the QR or the file to the admin human-to-human; do not
send it through a chat that logs content. In the admin app: Security → Import
signer key, or the Import action on the AdminHome banner. A QR scan or the file
picker both work.

Import verification: the seed must decode to 32 bytes, derive a public key that
matches the id in the root-signed signers directory, and carry a known format.
Any role may be stored, but only founder/admin may be activated as the push
signer; a salesman seed is stored and reported but never activated, and the
role is re-read from the trusted directory at push time so edited preferences
cannot turn a salesman into a distributor. No seed is logged, displayed or
placed on the clipboard, and the input buffer is cleared after import.

## Kit contents

| File | Purpose |
|---|---|
| `myhanout-shopkeeper-v<name>-b<code>.apk` | release, arm64, `com.myhanout.myhanout` |
| `myhanout-admin-v<name>-b<code>.apk` | release, arm64, `com.myhanout.admin` |
| `RELEASE.txt` | version, build number, UTC date, pinned fingerprint, package names |
| `SHA256SUMS` | integrity of both APKs |
| `install-en.html` / `install-fr.html` / `install-ar.html` | printable cards |

Only release APKs are ever distributed. Debug builds are for development and
are never handed to a shop.

## Build — founder only

Prerequisites: Flutter 3.47.1, build-tools 36.0.0, `ANDROID_HOME` set.

```bash
cd /home/hermes/perso/shopkeeper
bash tool/build_release_bundle.sh <build-number> [version-name]
```

The admin build MUST carry `--dart-define=ADMIN=true`; `kIsAdmin` is a compile-time
const defaulting to false, so a flavor-only build silently produces a shopkeeper
app with the admin applicationId. The build script applies the define and asserts
on a compiled AdminHome marker in both APKs.

The script: refuses a build number not greater than `release/LAST_BUILD_NUMBER`,
builds the two flavors in **separate invocations**, copies the APKs into
`release/kits/myhanout-v<name>-b<code>/`, writes the checksums, notes and cards,
then verifies the kit. It never commits, pushes or transfers anything.

The version code is monotone: a kit can never be mistaken for a downgrade.
`versionName` defaults to the `pubspec.yaml` version.

## Verify — every human, before forwarding

```bash
bash tool/verify_release_bundle.sh <kit-folder>
```

It checks, in order: `sha256sum -c SHA256SUMS`; `RELEASE.txt` certificate and
version code; `apksigner verify` on every APK; exact certificate fingerprint;
package name in `{com.myhanout.myhanout, com.myhanout.admin}`; APK version code
against the declared one. Expected close: `RESULT: PASS — … is genuine and
complete`. A `FAIL` kit is discarded, never forwarded, never installed.

The same two checks can be run by hand from an install card:
`sha256sum -c SHA256SUMS` and `apksigner verify --print-certs <apk>`.

## Distribution chain (4a)

1. **Founder** builds and verifies the kit, hands it to administrators in person
   (USB seed kit) or over a verified channel.
2. **Administrator / salesman** verifies the kit, then forwards it to shops.
   Distribution nodes never hold the keystore or signer seeds.
3. **Shopkeeper** receives the APK, installs it, and stops if the phone asks to
   uninstall an existing myhanout.

A lost phone holding cached kits is harmless: stale copies only, no signing
capability. Recovery is "a new version exists", announced by a person.

## Handoff channels (2a), in order

1. **Nearby Share / Quick Share** — Bluetooth + Wi-Fi Direct. True peer-to-peer,
   no internet, no server. Preferred. Send the kit folder (or each file) from
   one phone to another, then verify the SHA-256 on the receiving device.
2. **WhatsApp / Telegram** — send the APK as **document**, never renamed. Chat
   clients can recompress or alter bytes, so the receiving human must run
   `sha256sum -c SHA256SUMS` before installing.
3. **USB stick / SD card** — the seed kit for administrators, handed
   person-to-person; also the fallback when no radio channel is available.

Plain Bluetooth is a last resort: ~86 MB is slow, so prefer Wi-Fi Direct.
If a channel blocks `.apk`, **change channel** — never rename the file to dodge
a filter, because that teaches people to skip the verification habit.

## Hard rules

- Never forward a kit you have not verified.
- Never rename an `.apk`; never send a debug build.
- Never install on an "uninstall existing app first" prompt.
- Never trust a checksum typed into a chat message — compare against `SHA256SUMS`.
- Full release arm64 only; build numbers monotone.
- No download links, no public hosting, no automatic updates. No new network
  exposure is introduced by this process.
- Getting a kit onto the Windows staging host still uses the existing
  tailnet-only transfer; changing that needs explicit approval. If the link
  stalls above ~260 MB, chunk at 15 MB and verify sha256 on both ends.

## Troubleshooting

| Symptom | Action |
|---|---|
| `sha256sum -c` reports FAILED | Transfer was altered or truncated. Discard and re-request; do not install. |
| Certificate mismatch / `RESULT: FAIL` | Not a myhanout build. Stop; do not forward or install. |
| Phone asks to uninstall myhanout first | Different certificate. Stop. |
| "Install from unknown sources" blocked | Allow it for the file manager you are using, then retry. |
| Large transfer stalls | Switch to Nearby Share Wi-Fi Direct; for the staging host, chunk at 15 MB. |
| Version code lower than installed | Wrong kit. Do not install; request the current build. |

## Gates and evidence

1. `bash tool/verify_release_bundle.sh <kit>` → PASS on a freshly built kit.
2. Pilot handoff: a second human receives a kit over Nearby Share, verifies the
   fingerprint before install, and reports the matched digest.
3. Scale-out: an administrator who did not build the kit verifies and forwards
   it unaided.

Each gate's output (kit path, version, fingerprint, PASS line) belongs in the
session record. No secret values are ever printed or stored in the kit.
