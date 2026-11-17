#!/usr/bin/env bash
# A3 — prod `catalog_version` round-trip.
#
# The one number the whole catalog-delivery channel gates on: the admin refuses
# to build a delta unless its local catalog equals the shop's registered
# generation, and the shopkeeper refuses a delta whose base_version differs from
# its installed one. If the stored value is wrong, nothing crashes — the
# delivery is just silently rejected at the far end.
#
# SECRET HANDLING: the bearer token is read from MYHANOUT_PROD_TOKEN and is
# never a positional argument, never written to a file, never echoed, and never
# logged — so it cannot leak into shell history, a process listing or a log.
# Only the shop's catalog_version is printed.
#
# Usage:
#   MYHANOUT_PROD_TOKEN=... bash tool/verify_prod_catalog_version.sh [shop_key] [base_url]
#
# Defaults: shop_key=hanouti, base_url=http://127.0.0.1:8020
set -u

SHOP_KEY="${1:-hanouti}"
BASE_URL="${2:-http://127.0.0.1:8020}"
TOKEN="${MYHANOUT_PROD_TOKEN:?set MYHANOUT_PROD_TOKEN to the prod bearer token (it is never printed)}"

# The version field of GET /v1/shops/{key}, or empty if the shop is missing.
get_version() {
  curl -sS -H "Authorization: Bearer $TOKEN" "$BASE_URL/v1/shops/$SHOP_KEY" \
    | grep -o '"catalog_version":[ ]*[0-9]*' \
    | grep -o '[0-9]*$' \
    | head -1
}

before="$(get_version)"
if [ -z "$before" ]; then
  echo "could not read catalog_version for '$SHOP_KEY' at $BASE_URL" >&2
  echo "(a 401 here means the token is wrong or expired)" >&2
  exit 1
fi
echo "before: $SHOP_KEY catalog_version=$before"

target=$((before + 1))
code="$(curl -sS -o /dev/null -w '%{http_code}' \
  -X POST "$BASE_URL/v1/shops/$SHOP_KEY/catalog-version" \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"catalog_version\": $target}")"

after="$(get_version)"
echo "after:  $SHOP_KEY catalog_version=${after:-<none>}  (POST -> HTTP $code, target $target)"

if [ "$code" = "200" ] && [ "$after" = "$target" ]; then
  echo "A3 OK: catalog_version round-tripped $before -> $target"
  exit 0
fi

echo "A3 FAIL: the value did not round-trip." >&2
echo "  The admin's version guard compares against this number, so a stale value" >&2
echo "  makes every generated delta be rejected by the shopkeeper." >&2
exit 1
