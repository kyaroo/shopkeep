#!/usr/bin/env bash
# Source guard for the admin Settings tab + the AdminHome shell IA.
#
# `kIsAdmin` is a compile-time const, so no test can flip it inside one
# isolate. The shopkeeper view is asserted by
# test/screens/settings_flavor_gate_test.dart; this guard pins the SOURCE so an
# accidental move outside a compile-time branch is caught without rebuilding an
# APK:
#   1. the Settings body keeps the signers directory + import, and BOTH are
#      behind `if (kIsAdmin)` — nothing else signing/provisioning-related
#      (provisioning service, join shop, popup menu, business-name editing)
#      may be reachable from the admin Settings tab;
#   2. the AdminHome AppBar has no three-dot menu — the per-shop menu belongs
#      to the Shops tab list;
#   3. the admin landing tab is Shops, and there are exactly three tabs;
#   4. the admin POS detour is opt-in (AppState.posMode) and session-only, with
#      the shell as the default and an explicit « Back to admin » in the POS.
#
# Run: bash tool/verify_flavor_gates.sh
set -euo pipefail
cd "$(dirname "$0")/.."

screen=lib/screens/settings_screen.dart
home=lib/screens/admin_home_screen.dart
for f in "$screen" "$home"; do
  [ -f "$f" ] || { echo "FAIL: $f not found"; exit 1; }
done

echo "-- Settings: signer material present, and only behind kIsAdmin --"
for pat in 'SignersDirectoryLoader' 'Import signer key'; do
  if ! grep -q "$pat" "$screen"; then
    echo "FAIL: $screen lost '$pat' — the signers directory + import must live here"
    exit 1
  fi
done
echo "ok: $screen still hosts the signers directory + import"

awk -v guard="if (kIsAdmin)" '
  {
    lines[NR] = $0
    if (index($0, guard) > 0) lastGuard = NR
    guardAt[NR] = lastGuard
  }
  END {
    bad = 0; seenDir = 0; seenKey = 0
    for (i = 1; i <= NR; i++) {
      if (lines[i] ~ /_SignersDirectoryCard\($/ || lines[i] ~ /_SignerKeyCard\($/) {
        g = guardAt[i]; d = i - g
        if (lines[i] ~ /_SignersDirectoryCard\($/) seenDir = 1
        if (lines[i] ~ /_SignerKeyCard\($/) seenKey = 1
        if (g == 0 || d > 8) {
          printf "FAIL: %s:%d — admin-only card call is NOT behind `if (kIsAdmin)` (guard line %d, distance %d)\n", FILENAME, i, g, d
          bad = 1
        } else {
          printf "ok: %s:%d is behind kIsAdmin (guard line %d, distance %d)\n", FILENAME, i, g, d
        }
      }
    }
    if (!seenDir) { print "FAIL: _SignersDirectoryCard call site not found"; bad = 1 }
    if (!seenKey) { print "FAIL: _SignerKeyCard call site not found"; bad = 1 }
    exit bad ? 1 : 0
  }
' "$screen"

echo "-- Settings: no provisioning / popup / business-name editing surface --"
hits="$(grep -n 'ShopProvisioningService\|createShop\|ShopEntryScreen\|joinShop\|PopupMenuButton\|more_vert\|_useShop\|AttributionService' "$screen" || true)"
if [ -n "$hits" ]; then
  printf 'FAIL: %s still exposes a provisioning/popup surface:\n%s\n' "$screen" "$hits"
  exit 1
fi
echo "ok: $screen exposes no provisioning / popup surface"

# The business name may only ever render read-only here (shopkeeper branch);
# an editable field would mean the admin renamed a shop from Settings.
if grep -q 'controller: _nameController' "$screen"; then
  echo "FAIL: $screen renders an editable business-name TextField"
  grep -n 'controller: _nameController' "$screen"
  exit 1
fi
echo "ok: $screen has no editable business-name field"

echo "-- AdminHome: no three-dot app-bar menu --"
hits="$(grep -n 'PopupMenuButton\|Icons\.more_vert' "$home" || true)"
if [ -n "$hits" ]; then
  printf 'FAIL: %s has a popup (three-dot) menu; the per-shop menu belongs to the Shops tab list:\n%s\n' "$home" "$hits"
  exit 1
fi
echo "ok: $home has no three-dot menu"

echo "-- AdminHome: landing tab is Shops, exactly three destinations --"
mapfile -t labels < <(grep -o "label: '[^']*'" "$home")
if [ "${#labels[@]}" -ne 3 ]; then
  printf 'FAIL: expected 3 NavigationDestination labels, found %d\n' "${#labels[@]}"
  printf '%s\n' "${labels[@]}"
  exit 1
fi
landing="${labels[0]#label: \'}"
landing="${landing%\'}"
printf 'ok: 3 destinations, landing tab = %s\n' "$landing"
if [ "$landing" != "Shops" ]; then
  echo "FAIL: landing tab is '$landing', expected 'Shops'"
  exit 1
fi
if [ "${labels[1]}" != "label: 'Catalog'" ] || [ "${labels[2]}" != "label: 'Settings'" ]; then
  printf 'FAIL: tabs are %s / %s / %s, expected Shops / Catalog / Settings\n' \
    "${labels[0]}" "${labels[1]}" "${labels[2]}"
  exit 1
fi
if grep -q 'Icons.security\|Security' "$home"; then
  echo "FAIL: $home still references a Security tab"
  grep -n 'Security' "$home"
  exit 1
fi
echo "ok: no Security tab"
if ! grep -qE 'int _tab = 0;' "$home"; then
  echo "FAIL: $home does not start on tab 0 (Shops)"
  exit 1
fi
echo "ok: $home starts on the Shops tab"

echo "-- Admin router: the POS detour is opt-in and session-only --"
router=lib/app_router.dart
[ -f "$router" ] || { echo "FAIL: $router not found"; exit 1; }
if ! grep -q 'state\.posMode' "$router"; then
  echo "FAIL: $router no longer gates the POS on AppState.posMode"
  exit 1
fi
if ! grep -q 'AdminHomeApp(settings: settings)' "$router"; then
  echo "FAIL: $router no longer falls back to the admin shell"
  exit 1
fi
awk '
  /state\.posMode/ { p = NR }
  /AdminHomeApp\(settings: settings\)/ { a = NR }
  END {
    if (p == 0 || a == 0 || a < p) {
      print "FAIL: posMode must guard the POS branch, with the shell as the default"
      exit 1
    }
  }
' "$router"
echo "ok: the POS is behind posMode; the admin shell is the default"
if ! grep -q 'backToAdmin' lib/main.dart; then
  echo "FAIL: lib/main.dart has no « Back to admin » action in the POS app bar"
  exit 1
fi
echo "ok: the POS has a « Back to admin » action"

echo "PASS: the admin Settings / AdminHome flavor gates are intact"
