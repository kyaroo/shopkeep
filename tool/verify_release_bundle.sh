#!/usr/bin/env bash
# Verify a myhanout release kit received human-to-human (no store, no manifest).
#
# Trust anchor: the APK signing certificate SHA-256 fingerprint, pinned below.
# A kit is accepted only if every APK is signature-valid, carries that exact
# certificate, matches its SHA256SUMS entry, and declares a known package.
# No secret value is ever printed.
#
# Usage: bash tool/verify_release_bundle.sh <kit-dir>
set -u
cd "$(dirname "$0")/.."

PINNED="67c4aaeb303c704c8ae6b6cd29a48c629b0977e3958b802072f2c3f8f695a690"
SDK="${ANDROID_HOME:-/home/hermes/android-sdk}"
APKSIGNER="$SDK/build-tools/36.0.0/apksigner"
AAPT="$SDK/build-tools/36.0.0/aapt"

KIT="${1:-}"
if [ -z "$KIT" ]; then
  echo "usage: bash tool/verify_release_bundle.sh <kit-dir>" >&2
  exit 2
fi
if [ ! -d "$KIT" ]; then
  echo "not a directory: $KIT" >&2
  exit 1
fi
if [ ! -x "$APKSIGNER" ] || [ ! -x "$AAPT" ]; then
  echo "build-tools 36.0.0 not found under $SDK" >&2
  exit 1
fi

fail=0

echo "== 1. integrity =="
if [ ! -f "$KIT/SHA256SUMS" ]; then
  echo "MISSING SHA256SUMS"
  fail=1
else
  (cd "$KIT" && sha256sum -c SHA256SUMS) || fail=1
fi

echo
echo "== 2. release notes =="
DECLARED_VC=""
DECLARED_CERT=""
if [ ! -f "$KIT/RELEASE.txt" ]; then
  echo "MISSING RELEASE.txt"
  fail=1
else
  DECLARED_VC=$(grep '^version_code:' "$KIT/RELEASE.txt" | awk '{print $2}')
  DECLARED_CERT=$(grep '^signer_cert_sha256:' "$KIT/RELEASE.txt" | awk '{print $2}')
  if [ "$DECLARED_CERT" != "$PINNED" ]; then
    echo "RELEASE.txt certificate does not match the pinned fingerprint"
    fail=1
  else
    echo "declared certificate matches pinned fingerprint"
  fi
fi

echo
echo "== 3. APKs =="
shopt -s nullglob
apks=("$KIT"/*.apk)
shopt -u nullglob
if [ ${#apks[@]} -eq 0 ]; then
  echo "no APK in kit"
  fail=1
fi

for apk in "${apks[@]}"; do
  name=$(basename "$apk")
  if ! "$APKSIGNER" verify "$apk" >/dev/null 2>&1; then
    echo "$name: signature verification FAILED"
    fail=1
    continue
  fi
  digest=$("$APKSIGNER" verify --print-certs "$apk" 2>/dev/null \
    | grep 'SHA-256 digest:' | awk '{print $NF}')
  if [ "$digest" != "$PINNED" ]; then
    echo "$name: certificate MISMATCH (got ${digest:-none})"
    fail=1
    continue
  fi
  line=$("$AAPT" dump badging "$apk" 2>/dev/null | grep -m1 '^package:')
  pkg=$(echo "$line" | grep -o "name='[^']*'" | head -1 | cut -d"'" -f2)
  vc=$(echo "$line" | grep -o "versionCode='[^']*'" | head -1 | cut -d"'" -f2)
  vn=$(echo "$line" | grep -o "versionName='[^']*'" | head -1 | cut -d"'" -f2)
  case "$pkg" in
    com.myhanout.myhanout|com.myhanout.admin) ;;
    *) echo "$name: unexpected package '$pkg'"; fail=1 ;;
  esac
  if [ -n "$DECLARED_VC" ] && [ "$vc" != "$DECLARED_VC" ]; then
    echo "$name: versionCode $vc != declared $DECLARED_VC"
    fail=1
  fi
  echo "  $name package=$pkg versionCode=$vc versionName=$vn cert=${digest:0:12}…${digest: -6}"
done

echo
if [ "$fail" -ne 0 ]; then
  echo "RESULT: FAIL — do not forward this kit"
  exit 1
fi
echo "RESULT: PASS — $(basename "$KIT") is genuine and complete"
