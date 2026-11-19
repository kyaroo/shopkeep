#!/usr/bin/env bash
# Migration proof for the retired shared HMAC secret and the retired baked sync
# token, plus the offline lock on the shopkeeper release APK.
#
# Prints COUNTS and LENGTHS only — never a secret value. The retired values are
# re-extracted from git history on every run, so they are never pasted here.
#
# Usage: bash tool/verify_retired_secrets.sh
set -u
cd "$(dirname "$0")/.."

HMAC=$(git show cf706d5:lib/data/provisioning.dart \
  | grep -oP "[Ss]ecret\s*=\s*'\K[^']+" -z | tr -d '\0')
TOKEN=$(git show 29d3f36:lib/data/sync_config.dart \
  | grep -oP "defaultToken\s*=\s*\n?\s*'\K[a-f0-9]+" -z | tr -d '\0')

if [ -z "$HMAC" ] || [ -z "$TOKEN" ]; then
  echo "could not extract a retired secret from git history" >&2
  exit 1
fi
echo "retired secrets re-extracted from history: hmac=${#HMAC}B token=${#TOKEN}B"

echo
echo "== 1. working tree (lib/ assets/ tool/ test/) =="
printf 'hmac    hits: %s\n' \
  "$(grep -aoc "$HMAC" -r lib assets tool test 2>/dev/null | awk -F: '{t+=$2} END{print t+0}')"
printf 'token   hits: %s\n' \
  "$(grep -aoc "$TOKEN" -r lib assets tool test 2>/dev/null | awk -F: '{t+=$2} END{print t+0}')"
printf 'root private key in lib/: %s\n' \
  "$(grep -aoc 'kRootPrivateKey\|rootPrivateSeed' -r lib 2>/dev/null | awk -F: '{t+=$2} END{print t+0}')"

echo
echo "== 2. git history (all revisions) =="
printf 'hmac    commits: %s\n' "$(git log --all -S "$HMAC" --oneline | wc -l)"
printf 'token   commits: %s\n' "$(git log --all -S "$TOKEN" --oneline | wc -l)"

echo
echo "== 3. release APKs =="
for apk in build/app/outputs/flutter-apk/*.apk; do
  [ -e "$apk" ] || continue
  printf '%-34s hmac=%s token=%s\n' "$(basename "$apk")" \
    "$(grep -aoc "$HMAC" "$apk" || true)" \
    "$(grep -aoc "$TOKEN" "$apk" || true)"
done

echo
echo "== 3b. release kits =="
for apk in release/kits/*/*.apk; do
  [ -e "$apk" ] || continue
  printf '%-44s hmac=%s token=%s\n' "${apk#release/kits/}" \
    "$(grep -aoc "$HMAC" "$apk" || true)" \
    "$(grep -aoc "$TOKEN" "$apk" || true)"
done

SHOP=$(ls build/app/outputs/flutter-apk/app-shopkeeper-release.apk 2>/dev/null || true)
KITSHOP=$(ls release/kits/*/myhanout-shopkeeper-*.apk 2>/dev/null | tail -n1 || true)
if [ -n "$SHOP" ] || [ -n "$KITSHOP" ]; then
  echo
  echo "== 4. shopkeeper release APK: forbidden hosts =="
  for target in "$SHOP" "$KITSHOP"; do
    [ -e "$target" ] || continue
    echo "-- $target"
    for needle in openfoodfacts.org upcitemdb mymemory catalog.myhanout.ma; do
      printf '  %-24s hits: %s\n' "$needle" "$(grep -aoc "$needle" "$target" || true)"
    done
  done
else
  echo
  echo "== 4. shopkeeper release APK not found - build it first =="
fi
