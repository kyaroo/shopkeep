#!/usr/bin/env bash
# The universal-catalog export must be admin-only.
#
# The gate is a compile-time `kIsAdmin` (from `--dart-define=ADMIN=true`), so no
# test can flip it — which is exactly why it needs a source-level guard. It has
# already regressed once: the Backup card sat *outside* the `if (kIsAdmin)`
# spread that wraps the shop-management card, and the catalog action rendered in
# the shopkeeper flavor too.
#
# Run: bash tool/verify_catalog_export_gate.sh
set -euo pipefail
cd "$(dirname "$0")/.."

screen=lib/screens/settings_screen.dart

awk '
  {
    lines[NR] = $0
    if ($0 ~ /if \(kIsAdmin\)/) { lastGuard = NR }
    guardAt[NR] = lastGuard
  }
  END {
    for (i = 1; i <= NR; i++) {
      # Only the localised menu title — not the private _exportCatalog method,
      # which legitimately lives outside the guard.
      if (lines[i] ~ /exportCatalog.*\.tr\(\)/) {
        g = guardAt[i]
        if (g == 0) {
          printf "FAIL %s:%d — exportCatalog is not inside an `if (kIsAdmin)` guard\n", FILENAME, i
          exit 1
        }
        if (i - g > 15) {
          printf "FAIL %s:%d — exportCatalog is %d lines below the guard at line %d; the guard probably closed early\n", FILENAME, i, i - g, g
          exit 1
        }
        printf "ok: exportCatalog entry at line %d is guarded (if (kIsAdmin) at line %d)\n", i, g
        found = 1
      }
    }
    if (!found) {
      printf "FAIL %s — no exportCatalog menu entry found; is the action missing?\n", FILENAME
      exit 1
    }
  }
' "$screen"

# The catalog export must have exactly one call site: the guarded settings entry.
calls=$(grep -rn "catalogJson(" lib --include=*.dart | grep -v "shop_export_service.dart" | wc -l)
if [ "$calls" -ne 1 ]; then
  echo "FAIL: expected exactly one catalogJson() call site, found $calls"
  grep -rn "catalogJson(" lib --include=*.dart
  exit 1
fi
echo "ok: catalogJson() has exactly one call site (the guarded settings entry)"
