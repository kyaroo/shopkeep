#!/usr/bin/env bash
# Source guard for the two SettingsScreen flavor gates.
#
# `kIsAdmin` is a compile-time const, so no test can flip it inside one
# isolate. The shopkeeper view is asserted by
# test/screens/settings_flavor_gate_test.dart; this guard pins the SOURCE so an
# accidental move outside a compile-time branch is caught without rebuilding
# an APK:
#   1. the Security card / "Import signer key" entry is inside `if (kIsAdmin)`;
#   2. the editable business-name TextField and Save button are behind
#      `if (kIsAdmin)`, with the shopkeeper branch rendering the stored value
#      as read-only text.
#
# Run: bash tool/verify_flavor_gates.sh
set -euo pipefail
cd "$(dirname "$0")/.."

screen=lib/screens/settings_screen.dart
[ -f "$screen" ] || { echo "FAIL: $screen not found"; exit 1; }

echo "-- Security card (no signing surface on shopkeeper) --"
awk -v guard="if (kIsAdmin)" \
    -v title="Text('Security'" \
    -v entry="Text('Import signer key')" '
  {
    text[NR] = $0
    if (index($0, guard) > 0) lastGuard = NR
    guardAt[NR] = lastGuard
  }
  END {
    bad = 0; seenTitle = 0; seenEntry = 0
    for (i = 1; i <= NR; i++) {
      if (index(text[i], title) > 0) {
        seenTitle = 1; g = guardAt[i]; d = i - g
        if (g == 0 || d > 10) {
          printf "FAIL: Security card at line %d is NOT inside a kIsAdmin branch (nearest guard line %d, distance %d)\n", i, g, d
          bad = 1
        } else {
          printf "ok: Security card at line %d is guarded (if (kIsAdmin) at line %d, distance %d)\n", i, g, d
        }
      }
      if (index(text[i], entry) > 0) {
        seenEntry = 1; g = guardAt[i]; d = i - g
        if (g == 0 || d > 20) {
          printf "FAIL: Import signer key at line %d is NOT inside a kIsAdmin branch (nearest guard line %d, distance %d)\n", i, g, d
          bad = 1
        } else {
          printf "ok: Import signer key at line %d is guarded (if (kIsAdmin) at line %d, distance %d)\n", i, g, d
        }
      }
    }
    if (!seenTitle) { print "FAIL: Security card title not found"; bad = 1 }
    if (!seenEntry) { print "FAIL: Import signer key entry not found"; bad = 1 }
    exit bad ? 1 : 0
  }
' "$screen"

echo "-- Business name (read-only on shopkeeper) --"
awk -v guard="if (kIsAdmin)" \
    -v ctrl="controller: _nameController," \
    -v save="onPressed: _saveBusinessName," \
    -v ro="ValueListenableBuilder<TextEditingValue>" '
  {
    text[NR] = $0
    if (index($0, guard) > 0) lastGuard = NR
    guardAt[NR] = lastGuard
  }
  END {
    bad = 0; seenCtrl = 0; seenSave = 0; seenRo = 0
    for (i = 1; i <= NR; i++) {
      if (index(text[i], ctrl) > 0) {
        seenCtrl = 1; g = guardAt[i]; d = i - g
        if (g == 0 || d > 6) {
          printf "FAIL: editable business-name TextField at line %d is NOT behind a kIsAdmin branch (nearest guard line %d, distance %d)\n", i, g, d
          bad = 1
        } else {
          printf "ok: editable business-name TextField at line %d is behind kIsAdmin (guard line %d, distance %d)\n", i, g, d
        }
      }
      if (index(text[i], save) > 0) {
        seenSave = 1; g = guardAt[i]; d = i - g
        if (g == 0 || d > 12) {
          printf "FAIL: Save button at line %d is NOT behind a kIsAdmin branch (nearest guard line %d, distance %d)\n", i, g, d
          bad = 1
        } else {
          printf "ok: Save button at line %d is behind kIsAdmin (guard line %d, distance %d)\n", i, g, d
        }
      }
      if (index(text[i], ro) > 0) seenRo = 1
    }
    if (!seenCtrl) { print "FAIL: editable business-name TextField not found"; bad = 1 }
    if (!seenSave) { print "FAIL: Save button not found"; bad = 1 }
    if (!seenRo) {
      print "FAIL: shopkeeper read-only text branch (ValueListenableBuilder) not found; stored name would not be displayed"
      bad = 1
    } else {
      print "ok: shopkeeper branch renders the stored business name as read-only text"
    }
    exit bad ? 1 : 0
  }
' "$screen"

echo "PASS: both SettingsScreen flavor gates are intact in $screen"
