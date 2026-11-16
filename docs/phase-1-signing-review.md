# Security Review — Phase 1 Per-Admin Signing Spec

**Date:** 2026-11-16 · **Reviewer:** Application Security Engineer
**Subject:** `docs/phase-1-signing-spec.md` (status: written spec, no code)
**Parent:** `docs/per-admin-keys-strategy.md` (D1–D10, option (i))
**Code baseline:** `/home/hermes/perso/shopkeeper` @ `b0245bd`, clean tree.
`lib/data/signing.dart`, `lib/data/signers_directory.dart`, `tool/gen_signer_keys.dart`
and `assets/signers.json` do **not** exist yet; the only signing code is the HMAC
implementation and the Ed25519 POC (`test/poc/ed25519_poc_test.dart`).
**Method:** spec walked against the real code it will modify; every finding cites
the spec line and the code line that carries the risk. Pre-existing findings from
`docs/security-risk-analysis.md` are re-stated only where Phase 1 claims to close
them or inherits them.

---

## 1. Executive summary

The design direction is right: asymmetric per-admin keys, a root-signed directory,
offline verification, hard reject on unknown signers, and no secret on the
shopkeeper device. The POC proves the primitive. But as written the spec has two
**Critical** flaws that would leave the scheme bypassable or ineffective, and
several **High** gaps that are migration/enforceability failures rather than
crypto failures.

| # | Sev | Finding |
|---|---|---|
| CR-01 | **Critical** | The persisted directory override is trusted without re-verification on load |
| CR-02 | **Critical** | The delta stays universal and unbound; `target_version == base_version + 1` is not enforced (C2-03 not fixed) |
| CR-03 | High | Release APKs are debug-signed, so the baked root key is replaceable (C2-08) |
| CR-04 | High | Hard cutover does not reach installed APKs; the compromised HMAC remains valid there |
| CR-05 | High | Directory QR and provisioning QR share one untyped envelope; no `format`/`alg` |
| CR-06 | High | Key-generation model contradicts "generated on the admin's device"; no key-transport path |
| CR-07 | High | No canonical serialization is defined; sign/verify is producer-dependent |
| CR-08 | Medium | Private keys in `shared_preferences`; no secure-storage dependency |
| CR-09 | Medium | Receiver robustness (C2-04) unaddressed: unchecked casts, unbounded photo decode, no try/catch |
| CR-10 | Medium | Provisioning QR replay (C2-07) unaddressed; `nonce` generated but never checked |
| CR-11 | Medium | `signer_log` is not tenant-bound and needs a `CatalogDb` schema migration |
| CR-12 | Medium | `signer_id` is a mutable label; no uniqueness / key-fingerprint binding |
| CR-13 | Medium | `provisioned_by` collides with the existing `shop_names` map; no `SettingsService` accessor |
| CR-14 | Medium | Directory staleness is unbounded; `updated_at` is signed but unused |
| CR-15 | Medium | The "in-person QR" trust claim is procedural, not technical |
| CR-16 | Medium | `newUri` warm-start delta path is still unhandled (pre-existing) |
| CR-17 | Medium | Silent auto-apply of `VIEW` intents remains (pre-existing C2-06) |
| CR-18…25 | Low | Error enum, payload `format`/`alg`, asset registration, asset shape, role semantics, QR capacity, field validation, POC coverage |

**Verdict:** do not implement from this spec as-is. Fix CR-01/CR-02 and the High
items, and add the missing acceptance tests in §6 before the 8 h gate starts.

---

## 2. Critical findings

### CR-01 — The persisted directory override is trusted without re-verification on load
**Severity:** Critical
**Spec:** `docs/phase-1-signing-spec.md:48` (`loadDirectory()` — "baked asset, then the
scanned override"), `:94` (§6 — replace only if `version` is higher).
**Code:** `lib/data/config.dart:23-25` (`Config.init` → `SharedPreferences`),
`lib/data/config.dart:70-80` (current-shop persistence pattern the directory would
follow), `lib/data/myhanout_file.dart:46-63` (the only verify-then-apply path that
exists today).

**Finding.** The spec verifies the scanned directory against the baked root key at
scan time and then persists the override. It never says the override is re-verified
when it is loaded on a later cold start. `loadDirectory()` is specified as "baked
asset, then the scanned override" — i.e. the override wins unconditionally.

**Impact.** The offline chain's root of trust is only enforced once, at scan time.
Anything that can write the app's private store afterwards — a rooted device, an
`adb backup`/auto-backup restore, a malicious app on a shared device, or a corrupted
 prefs file — can replace the directory with one that lists an attacker key, and the
app will trust it. That defeats the entire point of the root key. The spec already
accepts `shared_preferences` for private keys (`:54-55`, `:147-148`); the directory
is *more* security-sensitive than a private key because it is the trust anchor.

**Fix.** `loadDirectory()` must re-verify the override against the baked root public
key on every load and fall back to the baked asset (or fail closed) on any mismatch.
Persist the exact signed envelope, not a decoded/re-encoded payload. Add a test:
write a tampered override into prefs, assert the loaded directory is the baked one.

---

### CR-02 — The delta stays universal and unbound; `target_version == base_version + 1` is not enforced
**Severity:** Critical
**Spec:** `docs/phase-1-signing-spec.md:74-87` (§5 — only `signer_id` and the
algorithm change; no recipient binding, no target rule), `:125-126` (Phase 2/3 out
of scope). Parent `docs/per-admin-keys-strategy.md:395-413` (C2-03) and
`docs/security-risk-analysis.md:395-413`.
**Code:** `lib/data/myhanout_file.dart:56-60` (guard is `baseVersion != installed`
only), `lib/data/catalog_delta.dart:89-95` (`targetVersion` is read but never
validated against `baseVersion`), `lib/services/catalog_push_service.dart:37`
(`target = shopVersion + 1` is enforced on the **build** side only).

**Finding.** Phase 1 replaces the HMAC key but does not fix the two properties that
made C2-03 High: the delta is still universal (not bound to a recipient) and the
receiver still accepts any `target_version` as long as `base_version` matches. The
spec's own parent strategy lists C2-03 as a trigger and its remediation is
"bind deltas to a recipient … and validate `target_version == base_version + 1` on
receive" (`docs/security-risk-analysis.md:410-413`). Neither is in the Phase 1 spec.

**Impact.** One compromised *admin* key (not even the root) is enough to forge a
delta with `base_version = <victim's installed version>` and `target_version =
999999`. Every shop that receives it jumps its catalog version and permanently
rejects the legitimate next delta — the same desync DoS as C1-02/C2-03. Per-admin
keys give attribution, not containment: the blast radius is still every device.

**Fix.** In `MyhanoutFile.applyJson`, reject unless `d.targetVersion == d.baseVersion + 1`
(defence in depth; the build side already does this). Decide and document the
recipient-binding question (a `shop_key`/catalog-epoch field in the signed payload)
in Phase 1 or explicitly defer it with a written residual risk. Add a version-jump
rejection test; `test/poc/catalog_version_guard_poc_test.dart:55-76` currently tests
base mismatch only.

---

## 3. High findings

### CR-03 — Release APKs are debug-signed, so the baked root key is replaceable
**Severity:** High
**Spec:** `docs/phase-1-signing-spec.md:16` ("baked into both APKs"), `:42-43`,
`:142-150` (§10 risks — APK signing is not listed).
**Code:** `android/app/build.gradle.kts:42-43`
(`signingConfig = signingConfigs.getByName("debug")` inside `buildTypes.release`).

**Finding.** The whole scheme trusts a root public key compiled into the APK. The
release build is signed with the public debug keystore, so anyone can produce an
APK with the same application id, their own root key, and their own directory. The
spec does not list APK authenticity as a risk or an acceptance criterion.

**Impact.** A sideloaded "update" replaces the trust anchor and can mint valid
directories and artifacts. The offline chain is only as strong as APK integrity.

**Fix.** Create a dedicated release keystore (backed up offline, referenced from a
non-committed properties file), rebuild both flavors, and add an acceptance criterion
that the release APK is signed with it (C2-08, `docs/security-risk-analysis.md:516-529`).

---

### CR-04 — Hard cutover does not reach installed APKs; the compromised HMAC remains valid there
**Severity:** High
**Spec:** `docs/phase-1-signing-spec.md:98-106` (§7 — delete the secret, rebuild both
flavors), `:138` (criterion 6 — tree + APK grep only).
**Code:** `lib/data/provisioning.dart:7` (`_provisioningSecret`), `:24-31` and
`:81-88` (the two HMAC paths), `lib/data/catalog_delta.dart:66,84` (delta sign/verify),
`lib/data/shop_provisioning_service.dart:71` (QR sign).

**Finding.** The secret is in git history and in shipped APKs, so it is compromised.
Deleting it from the tree and from new builds does not invalidate it for devices that
already have an old APK — those still contain the HMAC verify path and will keep
accepting forged deltas. There is no server-side delta registry to revoke against
(the catalog server has no signer concept; `barcode-mapper/server` has no
`/v1/signers`). The spec's criterion 6 greps the tree and the new APKs, which says
nothing about the installed base.

**Impact.** The P0 credential remains usable against every device that has not
updated. "Hard cutover" is only hard for new installs.

**Fix.** State the residual risk explicitly and pick a control: forced update /
version gate, a short dual-scheme window with a server-side reject, or written
acceptance that old APKs are untrusted. Extend criterion 6 with `git log -S
"myhanout-provisioning-secret-change-me"` and a check that no *old* release APK is
still distributed. Re-issue pending deltas (spec §7.6) is not sufficient.

---

### CR-05 — Directory QR and provisioning QR share one untyped envelope; no `format`/`alg`
**Severity:** High
**Spec:** `docs/phase-1-signing-spec.md:40-43` (§2 — "same shape as the existing QR
token"), `:59-68` (§4 — provisioning payload has no `format`/`alg`), `:27-38`
(directory payload has no `format`/`alg`).
**Code:** `lib/screens/qr_scan_page.dart:19-27` (returns the raw string, no type),
`lib/screens/shop_entry_screen.dart:40` (`Provisioning.verify(token)` is the only
consumer), `lib/data/provisioning.dart:41-63` (dotted-envelope parser).

**Finding.** Both QR payloads are `base64url(json).base64url(sig)` and are scanned by
the same `QrScanPage`. Neither payload carries a `format`/`type`/`alg` field. The
spec says the shop_entry screen gains "directory-QR scan" (`:119`) but does not define
how a scanned string is routed to the directory verifier instead of the provisioning
verifier.

**Impact.** The implementer must either try both verifiers (ambiguous errors, UI
confusion, risk of a future cross-accept) or invent a discriminator the spec does not
name. A provisioning QR shown to a fresh install and a directory QR look identical to
the code. This is a design flaw, not just ergonomics: the directory is trust material
and must be distinguishable from a bearer token at the envelope level.

**Fix.** Add `format` (e.g. `myhanout-signers-v1`, `myhanout-provision-v1`) and `alg`
to both payloads, route on `format` before any signature work, and add a test that a
directory envelope is never accepted by the provisioning verifier and vice versa.

---

### CR-06 — Key-generation model contradicts "generated on the admin's device"; no key-transport path
**Severity:** High
**Spec:** `docs/phase-1-signing-spec.md:14-18` (§1 — private key lives in the holder's
device), `:53-55` (§3 — `generateSigner()` on device), `:130-131` (§9.1 — the tool
generates a keypair and prints the public half).
**Code:** `tool/gen_signer_keys.dart` (absent), `lib/data/shop_provisioning_service.dart:68`
(`Provisioning.generateShopKey` is the only on-device generator today),
`pubspec.yaml:9-29` (no secure-storage package).

**Finding.** The strategy is explicit that an admin keypair is "generated **on that
admin's device**" (`docs/per-admin-keys-strategy.md:80`) and D1 says private keys never
leave the owner's device. Phase 1 defines a host-side tool that generates keypairs and
prints the public half — but says nothing about where the private half goes or how it
reaches the admin's device. There are therefore two contradictory generation paths
(`generateSigner()` vs the tool) and an unspecified private-key transport.

**Impact.** In practice the tool-generated private key must travel by QR/file/clipboard
to the admin device — exactly the exposure D1 was meant to prevent — or the admin key
is generated on the founder's machine and shared. Neither is stated, so the
implementation will silently pick one.

**Fix.** Pick one: generate admin keypairs on-device with `generateSigner()` (matches
D1/strategy), and use `tool/gen_signer_keys.dart` only for the root/founder keypair,
with an explicit, one-way import of the root private key into the founder device (or
generate the root on-device and export only the public half). Document the private-key
handling of the tool (never printed, never written into the tree).

---

### CR-07 — No canonical serialization is defined; sign/verify is producer-dependent
**Severity:** High
**Spec:** `docs/phase-1-signing-spec.md:77` ("same canonical pattern: append
`signature` last, strip first"), `:41` (directory envelope).
**Code:** `lib/data/catalog_delta.dart:64-68` (signs compact `jsonEncode(payload)`,
writes **pretty** JSON with `JsonEncoder.withIndent`), `:72-98` (verify decodes the
file and re-encodes the map), `:100-111` (`_entryFromMap` re-parses fields).

**Finding.** "Append signature last, strip first" is not a canonical form. Ed25519
signs bytes; the sign side and verify side must produce byte-identical JSON. Today
that works only because both sides are Dart and `jsonDecode` preserves key order. The
spec does not define key ordering, whitespace, number formatting, duplicate-key
handling, or UTF-8 normalization. The server registry (phase 3) and any Python/JS
tooling will produce different bytes.

**Impact.** A legitimate artifact from a non-Dart producer fails verification and is
reported as `bad-signature`/`tampered` — a false rejection that looks like an attack.
Conversely, a sign/verify mismatch that is "fixed" by loosening the comparison is a
forgery primitive. This is the classic canonicalization trap (recorded as X-05 in
`docs/security-risk-analysis.md:677`).

**Fix.** Specify canonical JSON: UTF-8, sorted keys, no whitespace, integers only for
versions/timestamps, reject duplicate keys, and sign the exact bytes that are
transmitted (for the QR envelope, sign `payloadJson` itself, not a re-encoding). Add
a cross-language test vector (a signed fixture produced by Python and verified by
Dart, and vice versa).

---

## 4. Medium findings

### CR-08 — Private keys in `shared_preferences`; no secure-storage dependency
**Severity:** Medium (accepted in spec §10, but under-priced)
**Spec:** `docs/phase-1-signing-spec.md:53-55`, `:147-148`.
**Code:** `pubspec.yaml:9-29` (no `flutter_secure_storage`), `lib/data/config.dart:23-25`
(`SharedPreferences`).

**Finding.** The spec accepts plaintext `shared_preferences` for Ed25519 private keys
as a phase-2 hardening. On Android these are an XML file readable via root, backup
extraction, or a malicious app with device access. The scheme's value proposition is
per-admin non-repudiation; a key that can be extracted from the device destroys that.

**Fix.** Use `flutter_secure_storage` (Android Keystore / iOS Keychain) for private
keys now; it is a small dependency and the key is the asset. If phase 1 truly ships
plaintext, record it as a written residual risk with an accountable owner and a date.

---

### CR-09 — Receiver robustness (C2-04) unaddressed
**Severity:** Medium
**Spec:** `docs/phase-1-signing-spec.md:49-50` (error enum has no `malformed`/`too-large`),
`:116` (`catalog_delta.dart` touched).
**Code:** `lib/data/catalog_delta.dart:89-95` (`as int`, `as List`), `:100-111`
(`m['barcode'] as String`, `base64Decode(photoB64)` at `:108` with no size cap),
`lib/data/myhanout_file.dart:46-78` (no try/catch; a throw propagates to
`lib/main.dart:233-240`).

**Finding.** Changing the signature algorithm does not fix the receiver's lack of
defence: unchecked casts, unbounded photo decode, and an unhandled-exception path.
The new `verifyArtifact` error enum does not include `malformed-field`,
`too-many-rows`, or `photo-too-large`.

**Impact.** A malformed delta (even one that fails signature) can crash the app or
OOM it. The 50 KB photo budget exists only on the build side
(`lib/services/catalog_delta_service.dart:12`), not on receive.

**Fix.** Type-check every field, cap decoded photo length before decoding, wrap
`applyJson` in try/catch, and extend the error enum. Add a fuzz test (wrong types,
huge `photo_base64`, bad version jump → `failed`, never throws). The security test
plan already calls for this (`docs/security-risk-analysis.md:778`).

---

### CR-10 — Provisioning QR replay (C2-07) unaddressed
**Severity:** Medium
**Spec:** `docs/phase-1-signing-spec.md:59-68` (nonce is in the payload), `:128-140`
(acceptance criteria have no replay test).
**Code:** `lib/data/shop_provisioning_service.dart:68` (generates `nonce`),
`lib/data/provisioning.dart:41-63` (`verify` never reads `nonce`),
`lib/screens/shop_entry_screen.dart:38-77` (no spent-nonce store).

**Finding.** `nonce` is generated and signed but nothing tracks it, so a QR remains
usable within its TTL (up to 7 days, `provisioningTtlChoices` at
`lib/data/shop_provisioning_service.dart:80-85`). Adding `signer_id` gives attribution
but not single-use.

**Fix.** Decide: track spent nonces on-device (prefs/SQLite) and reject replays, or
shorten the default TTL and document the residual risk. Add a replay-rejection test.

---

### CR-11 — `signer_log` is not tenant-bound and needs a `CatalogDb` migration
**Severity:** Medium
**Spec:** `docs/phase-1-signing-spec.md:87` (`catalog.db` gains
`signer_log(id, version, signed_by, applied_at, entry_count)`).
**Code:** `lib/data/catalog_db.dart:26-72` (schema `version: 3`, `onUpgrade` handles
`<2`, `<3` only; no `signer_log`), `lib/data/db.dart:13-19` (the file-per-shop tenancy
principle).

**Finding.** Two gaps. (a) `catalog.db` is the **universal** catalog, shared by every
shop on a device; `signer_log` has no `shop_key`, so on a multi-shop admin device the
log cannot answer "which shop applied this delta". (b) Adding a table requires
 bumping `CatalogDb` to version 4 with an `onUpgrade` branch; the spec lists the
table but not the migration.

**Fix.** Add `shop_key` to `signer_log` (or write the row to the per-shop DB), bump
`CatalogDb` to version 4, and add the `onUpgrade` branch. State that the log is
attribution data, not a security control.

---

### CR-12 — `signer_id` is a mutable label; no uniqueness / key-fingerprint binding
**Severity:** Medium
**Spec:** `docs/phase-1-signing-spec.md:27-38` (directory entries), `:81` (lookup by
`signer_id`).
**Code:** no directory model yet; the lookup would replace the current keyless verify
at `lib/data/catalog_delta.dart:82-95`.

**Finding.** Artifacts bind to a `signer_id` string, not to a key. If a directory has
duplicate ids the lookup is ambiguous; if a revoked id is reused for a new key, old
artifacts verify under the new key and attribution is wrong. Nothing in the spec
forbids id reuse.

**Fix.** Enforce unique ids within a directory, forbid reuse after revocation (or
include the public-key fingerprint in the artifact), and reject duplicate ids at load.

---

### CR-13 — `provisioned_by` collides with the existing `shop_names` map; no accessor
**Severity:** Medium
**Spec:** `docs/phase-1-signing-spec.md:71` (`provisioned_by = <signer display name>`),
`:118` (`config.dart` change).
**Code:** `lib/data/config.dart:96` (`_shopNames`), `:132-175` (`getShopNames` /
`saveShopBusinessName` — a `shop_key → business_name` map), `lib/data/settings_service.dart:10-31`
(the `SettingsService` interface that must expose the new value).

**Finding.** There is already a per-shop `shop_names` map storing the business name.
The spec's `provisioned_by` map (`shop_key → signer name`) is a different attribute
but the naming and storage are close enough that an implementer may overload
`shop_names` or store the signer name as the business name. The spec does not add a
`SettingsService` accessor, so screens cannot read it through the injected seam.

**Fix.** Define a distinct prefs key (`provisioned_by`), add
`getProvisionedBy(shopKey)` / `setProvisionedBy(shopKey, name)` to `SettingsService`
and `ConfigSettingsService`, and update the test mocks (`test/helpers/mock_providers.dart`).

---

### CR-14 — Directory staleness is unbounded; `updated_at` is signed but unused
**Severity:** Medium
**Spec:** `docs/phase-1-signing-spec.md:30` (`updated_at`), `:89-96` (§6 — version is
the only guard), `:144-145` (staleness accepted).
**Code:** no directory code; the pattern to copy is `lib/data/config.dart:123-130`
(`getCatalogVersion`/`setCatalogVersion`).

**Finding.** A device that never scans a new directory keeps trusting revoked signers
forever. `updated_at` is carried and signed but never compared to anything. The spec
acknowledges staleness as a risk but defines no freshness bound and no UI surface for
directory age/version.

**Impact.** Acceptance criterion 5 ("after a signer is removed, their QR/delta is
rejected") is only true after the new directory has travelled — the criterion omits
that precondition (see §6). Revocation is effectively "eventual".

**Fix.** State the precondition explicitly. Optionally add a max directory age or an
operator-acknowledged "directory last updated …" surface, and reject artifacts when
the directory is older than a configured bound.

---

### CR-15 — The "in-person QR" trust claim is procedural, not technical
**Severity:** Medium
**Spec:** `docs/phase-1-signing-spec.md:93-96` ("trust root changes only by scanning an
admin's screen in person"), `:129-134` (option (i) vs (iii)).
**Code:** `lib/screens/qr_scan_page.dart:19-27` (a camera scan; no attestation, no
one-time use).

**Finding.** A QR is just a carrier. A screenshot or photo of the directory QR is a
file and can be forwarded over WhatsApp exactly like option (iii). Nothing technical
distinguishes "scanned in person" from "received as an image"; the security difference
is human attention. The spec presents option (i) as strictly stronger than (iii)
without stating that the difference is procedural.

**Impact.** The threat model overstates the channel. A compromised/fooled admin (or a
screenshot of their screen) distributes a malicious directory as easily as a delta
file.

**Fix.** Say so in the threat model. Add a tap-to-confirm dialog that shows the
directory version, signer count and signer names before replacement, and consider a
short-lived one-time directory QR for high-value updates.

---

### CR-16 — `newUri` warm-start delta path is still unhandled
**Severity:** Medium
**Spec:** `docs/phase-1-signing-spec.md:117` (`myhanout_file.dart` is in scope).
**Code:** `android/app/src/main/kotlin/com/myhanout/MainActivity.kt:44`
(`channel?.invokeMethod("newUri", it)`), `lib/data/myhanout_file.dart:19-28` (only
`getInitialUri` is implemented; no `newUri` handler).

**Finding.** The native side invokes a `newUri` method channel on warm start; no Dart
code handles it, so a `.myhanout` file opened while the app is running is silently
dropped. Pre-existing (C2-06, `docs/security-risk-analysis.md:480-499`), but the spec
touches this file and does not fix it.

**Fix.** Handle `newUri` (route it through `applyUri`) or remove the call. Add a test.

---

### CR-17 — Silent auto-apply of `VIEW` intents remains
**Severity:** Medium
**Spec:** `docs/phase-1-signing-spec.md:117` (receiver in scope), `:125-126` (phase 2/3
out of scope, but no residual-risk note).
**Code:** `lib/main.dart:233-240` (`_applyPendingFile` auto-applies on launch),
`android/app/src/main/AndroidManifest.xml:28-41` (exported `VIEW` filters for
`content`/`file`),
`android/app/src/main/kotlin/com/myhanout/MainActivity.kt:47-52` (`readUri`).

**Finding.** Any installed app can send `ACTION_VIEW` and the shopkeeper applies the
file with only a snackbar. With per-admin signatures the *signature* still gates it,
so this is no longer a forgery path, but the UX/authorisation gap (no confirmation,
no caller check) is unchanged and unlisted in §10.

**Fix.** Add a confirmation dialog (shop, base→target, upsert/delete counts, sender
package) or record it as an accepted residual risk. The risk analysis already requires
it (`docs/security-risk-analysis.md:497-499`).

---

## 5. Low / informational findings

| ID | Finding | Spec | Code |
|---|---|---|---|
| CR-18 | `verifyArtifact` error enum is inconsistent with the existing code and incomplete (`tampered` vs `bad-signature`; missing `unknown-format`, `missing-signature`, `malformed-field`, `stale-version`, `too-many-rows`) | `:50` | `lib/data/catalog_delta.dart:77,80,83,85` |
| CR-19 | Delta payload keeps `format`/`version: 1`; a v1 HMAC and a v1 Ed25519 delta are indistinguishable. Add `alg` or bump `fileVersion` | `:76` | `lib/data/catalog_delta.dart:21-23,43-51` |
| CR-20 | `assets/signers.json` is not registered in `pubspec.yaml`; the baked asset will not ship | `:120` | `pubspec.yaml:39-41` |
| CR-21 | Baked asset shape is ambiguous: the JSONC block shows the payload, but §2 says the envelope is signed. Specify whether the asset holds the envelope or payload+signature, and that `loadDirectory` verifies it | `:25-43` | — |
| CR-22 | `role` is carried in the directory but no authorization semantics are defined; today all admins sign the same artifacts | `:14-18,31-36` | — |
| CR-23 | Directory QR capacity/chunking is unaddressed; a large directory may not fit one QR | `:89-96` | `lib/screens/qr_scan_page.dart:19-27` |
| CR-24 | Directory field types/ranges (`version`, `updated_at`, key length, base64url) are unspecified; malformed entries could throw or be accepted | `:27-38` | — |
| CR-25 | The POC does not exercise the spec's API or canonicalization: it hand-builds a payload string and calls `Ed25519()` directly; `lib/data/signing.dart` does not exist | `:6-8` | `test/poc/ed25519_poc_test.dart:18-52` |
| CR-26 | `tool/gen_signer_keys.dart` does not exist and no workflow signs `assets/signers.json` with the root key | `:92,121,130` | `tool/` (absent) |
| CR-27 | `business_name` is still taken verbatim from the signed payload; with `provisioned_by` the operator can see who provisioned, but the display name remains spoofable | `:59-68` | `lib/screens/shop_entry_screen.dart:50,66` |

---

## 6. Acceptance criteria — testability assessment

| # | Criterion (spec §9) | Testable as written? | Gap / suggested test |
|---|---|---|---|
| 1 | Tool generates a keypair; public half printed; `git grep` finds no private key | **Partially** | Tool absent. "No private-key material" is grep-able but does not cover git history or the tool's runtime output. Add: `git log -S` for the secret and key patterns; a unit test that the tool's public half matches the generated private half; assert the private half is never printed/written. |
| 2 | Baked directory verifies against the root key; one-byte tamper rejected | **Yes, once the asset exists** | Define the asset shape (envelope vs payload+signature) and the tamper target (payload byte vs signature byte). Add a test that loads `assets/signers.json` and verifies it. |
| 3 | Listed admin verifies; unknown key hard-rejected with the exact message and nothing applied | **Yes** | Pin the message string; assert DB/prefs state is unchanged after rejection, not just the return value. |
| 4 | Scanned directory QR replaces and bumps `version`; lower version ignored | **Partially** | The camera path is not unit-testable. Test the `replaceDirectory` function directly with a persisted-store seam; assert the persisted envelope and that a lower/equal version is a no-op. |
| 5 | After a signer is removed, their QR/delta is rejected | **Conditionally** | True only after the device receives the new directory. Add the precondition to the criterion and a unit test with a directory that omits the signer. |
| 6 | HMAC secret gone from the tree; both release APKs grep-clean | **Partially** | Building both release APKs in CI is heavy; grep-clean is meaningful only if the APK is release-signed (currently debug, CR-03). Add `git log -S`; add a test that an HMAC-signed delta is rejected after cutover. |
| 7 | Shopkeeper makes zero API calls (APK grep + existing guardrail test) | **Partially** | The existing guardrail test (`test/security_regression_test.dart:89-104`) covers `resolveFromServer`/`browseServer`/`syncNow`, not the new directory/verify path. Specify the APK grep markers; extend the guardrail test to pump the new code under an `HttpOverrides` that fails on any request. |
| 8 | `provisioned_by` recorded and readable from the shop screen | **No** | No screen or accessor is named. Define `SettingsService.getProvisionedBy(shopKey)`, name the screen/widget, and add a widget test. |

**Additional acceptance criteria the spec should add:**

1. A tampered persisted directory override is rejected on load; the baked directory is used (CR-01).
2. `target_version != base_version + 1` is rejected; a version-jump delta leaves the catalog version unchanged (CR-02).
3. Malformed deltas (wrong types, duplicate keys, oversized `photo_base64`, too many rows) return a rejection and never throw (CR-09).
4. A provisioning QR whose `nonce` was already used is rejected (CR-10).
5. A directory with duplicate `signer_id`s is rejected at load (CR-12).
6. `signer_log` rows carry `shop_key`, `signed_by`, `version`, `applied_at`, `entry_count`, and are queryable (CR-11).
7. A directory signed by the wrong root key is rejected and the previous directory is retained (CR-05).
8. A signed fixture produced by a non-Dart producer verifies in Dart, and vice versa (CR-07).
9. The release APK is signed with the dedicated release keystore; the root key fingerprint in the APK matches the one in `lib/data/signing.dart` (CR-03).
10. `assets/signers.json` is registered in `pubspec.yaml` and ships in both APKs (CR-20).
11. No private-key material in git history (`git log -S`), not just the working tree (CR-04).

---

## 7. Migration checklist (beyond §7 of the spec)

The spec's §7 covers the HMAC secret but not the code surface that must change:

- **HMAC removal touches:** `lib/data/provisioning.dart:24-31,81-88`,
  `lib/data/catalog_delta.dart:66,84`, `lib/data/shop_provisioning_service.dart:71`.
  Keep `Provisioning.generateShopKey` (used for the nonce at
  `lib/data/shop_provisioning_service.dart:68`).
- **Ripple of changing `CatalogDelta` / `Provisioning`:** `lib/services/catalog_delta_service.dart:104-117`,
  `lib/services/catalog_push_service.dart:38-44`, `tool/make_catalog_delta.dart:44-50`,
  `test/poc/catalog_delta_poc_test.dart`, `test/services/catalog_delta_builder_test.dart`,
  `test/services/catalog_push_builder_test.dart`,
  `test/poc/catalog_version_guard_poc_test.dart`, `test/unit/provisioning_test.dart`.
  None of these are in the spec's §8 file list.
- **New `Config`/`SettingsService` accessors** for `provisioned_by` ripple into
  `lib/data/settings_service.dart:10-31` and `test/helpers/mock_providers.dart`.
- **`CatalogDb` schema** must bump to version 4 with an `onUpgrade` branch
  (`lib/data/catalog_db.dart:30-70`).
- **`pubspec.yaml`** must add `assets/signers.json` (`:39-41`).
- **Old deltas in the wild:** devices with a pending `.myhanout` file will reject it
  after the update (HMAC path deleted) — re-issue is correct, but say so.
- **Old QRs:** TTL-bound; the spec's re-issue note (`:106`) is adequate, but the
  `nonce`/TTL tests in `test/unit/provisioning_test.dart` must be re-pointed at the
  new signing path.

---

## 8. Controls that work (keep)

- The existing canonical "sign payload-minus-signature, append `signature` last"
  pattern is the right shape (`lib/data/catalog_delta.dart:43-51,64-69`); the problem
  is the missing canonical-form definition, not the pattern.
- Hard reject on unknown signer is the correct decision (D9) and matches the existing
  verify-before-apply ordering (`lib/data/myhanout_file.dart:49-50`).
- `shop_key` validation is already enforced on both the QR and typed paths
  (`lib/screens/shop_entry_screen.dart:53-64,83-91`) and again in
  `lib/data/db.dart:81-92` — preserve it when adding `signer_id`.
- The base-version guard (`lib/data/myhanout_file.dart:56-60`) is a real control; it
  just needs the `target == base + 1` complement.
- The shopkeeper network gates are real (`lib/providers/catalog_provider.dart:72,130,255`;
  `lib/main.dart:102-104`) and the existing guardrail test pins them
  (`test/security_regression_test.dart:89-104`).
- Separate `applicationId` per flavor keeps `shared_preferences` namespaces isolated.

---

## 9. Appendix — re-runnable evidence

```bash
cd /home/hermes/perso/shopkeeper

# Compromised HMAC secret in the tree
grep -n "myhanout-provisioning-secret-change-me" lib/data/provisioning.dart
git log --oneline -S "myhanout-provisioning-secret-change-me" -- lib/

# Delta receiver has no target-version rule and no try/catch
sed -n '46,78p' lib/data/myhanout_file.dart
sed -n '89,111p' lib/data/catalog_delta.dart

# Sign/verify is producer-dependent (compact sign vs pretty file)
sed -n '64,98p' lib/data/catalog_delta.dart

# Release APK is debug-signed
sed -n '42,43p' android/app/build.gradle.kts

# newUri is invoked natively but not handled in Dart
grep -n "newUri" android/app/src/main/kotlin/com/myhanout/MainActivity.kt
grep -n "getInitialUri\|newUri" lib/data/myhanout_file.dart

# assets/signers.json is not registered
sed -n '39,41p' pubspec.yaml

# CatalogDb schema version and absence of signer_log
grep -n "version:\|signer_log" lib/data/catalog_db.dart

# POC is a raw-primitive test, not the spec API
sed -n '18,52p' test/poc/ed25519_poc_test.dart
```

**Bottom line:** the crypto primitive and the trust model are sound; the spec's
gaps are in persistence re-verification (CR-01), delta containment (CR-02), APK
integrity (CR-03), key generation/transport (CR-06), and canonicalization (CR-07).
Fix those and the acceptance criteria in §6, and the 8 h phase is implementable.
