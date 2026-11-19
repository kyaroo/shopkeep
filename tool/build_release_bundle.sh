#!/usr/bin/env bash
# Build a human-to-human myhanout release kit: two signed release APKs,
# SHA256SUMS, RELEASE.txt and printable install cards (en/fr/ar).
#
# Decisions applied: 1b (cert fingerprint only — NO signed manifest, NO in-app
# verify screen), 2a (Nearby Share then WhatsApp document then USB handoff),
# 3a (tooling + SOP + cards), 4a (founder -> admin -> shopkeeper chain).
#
# Nothing here commits, pushes, or transfers the kit to another host.
# The two flavors are ALWAYS built in separate invocations (BUILD-1 flake).
#
# Usage: bash tool/build_release_bundle.sh <build-number> [version-name]
set -u
cd "$(dirname "$0")/.."

export ANDROID_HOME="${ANDROID_HOME:-/home/hermes/android-sdk}"
FLUTTER=/home/hermes/flutter-sdk/flutter/bin/flutter
SIGNER="$ANDROID_HOME/build-tools/36.0.0/apksigner"
PINNED="67c4aaeb303c704c8ae6b6cd29a48c629b0977e3958b802072f2c3f8f695a690"

N="${1:-}"
V="${2:-}"
if [ -z "$N" ] || ! [[ "$N" =~ ^[0-9]+$ ]]; then
  echo "usage: bash tool/build_release_bundle.sh <build-number> [version-name]" >&2
  exit 2
fi
if [ ! -x "$FLUTTER" ] || [ ! -x "$SIGNER" ]; then
  echo "Flutter SDK or build-tools not found" >&2
  exit 1
fi

PUB_V=$(grep '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | cut -d+ -f1)
if [ -z "$V" ]; then
  V="$PUB_V"
fi

# Monotone build number: a kit must never be mistaken for a downgrade.
mkdir -p release
LAST=release/LAST_BUILD_NUMBER
if [ -f "$LAST" ]; then
  prev=$(cat "$LAST")
  if [ "$N" -le "$prev" ]; then
    echo "build number $N must be greater than last recorded $prev" >&2
    exit 1
  fi
fi

echo "building versionName=$V versionCode=$N (separate invocations)"
"$FLUTTER" build apk --release --target-platform android-arm64 \
  --flavor shopkeeper --build-number "$N" --build-name "$V" || exit 1
"$FLUTTER" build apk --release --target-platform android-arm64 \
  --flavor admin --dart-define=ADMIN=true --build-number "$N" --build-name "$V" || exit 1

SRC=build/app/outputs/flutter-apk
SHOP_APK="myhanout-shopkeeper-v${V}-b${N}.apk"
ADMIN_APK="myhanout-admin-v${V}-b${N}.apk"
if [ ! -f "$SRC/app-shopkeeper-release.apk" ] || [ ! -f "$SRC/app-admin-release.apk" ]; then
  echo "one or both release APKs are missing after the build" >&2
  exit 1
fi

# kIsAdmin is compile-time, so tests cannot exercise it. Guard the routing
# invariant at source: admin must be checked before the empty-shopKey branch,
# otherwise creating a shop switches the admin into the POS app.
ROUTER=lib/app_router.dart
if ! grep -q 'if (kIsAdmin) return AdminHomeApp' "$ROUTER"; then
  echo "admin shell routing is missing in $ROUTER" >&2
  exit 1
fi
admin_line=$(grep -n 'if (kIsAdmin) return AdminHomeApp' "$ROUTER" | cut -d: -f1)
empty_line=$(grep -n 'if (state.shopKey.isEmpty)' "$ROUTER" | cut -d: -f1)
if [ -z "$admin_line" ] || [ -z "$empty_line" ] || [ "$admin_line" -gt "$empty_line" ]; then
  echo "admin shell must be selected before the empty-shopKey branch" >&2
  exit 1
fi
echo "routing gate: admin shell precedes the empty-shopKey branch"

# Compile-time guard: a missing --dart-define=ADMIN=true silently produces a
# shopkeeper build with the admin applicationId. The source-level export gate
# cannot catch that, so assert on the compiled AdminHome marker itself.
MARKER='Admin'
if ! unzip -p "$SRC/app-admin-release.apk" lib/arm64-v8a/libapp.so | grep -aq "$MARKER"; then
  echo "admin APK lacks the AdminHome marker — ADMIN=true was not applied" >&2
  exit 1
fi
if unzip -p "$SRC/app-shopkeeper-release.apk" lib/arm64-v8a/libapp.so | grep -aq "$MARKER"; then
  echo "shopkeeper APK contains admin-only code" >&2
  exit 1
fi
echo "flavor gate: admin has AdminHome, shopkeeper does not"

KIT="release/kits/myhanout-v${V}-b${N}"
mkdir -p "$KIT"
cp "$SRC/app-shopkeeper-release.apk" "$KIT/$SHOP_APK"
cp "$SRC/app-admin-release.apk" "$KIT/$ADMIN_APK"
(cd "$KIT" && sha256sum *.apk > SHA256SUMS)

# Refuse to assemble a kit signed by anything but the founder keystore.
d=$("$SIGNER" verify --print-certs "$KIT/$SHOP_APK" 2>/dev/null \
  | grep 'SHA-256 digest:' | awk '{print $NF}')
if [ "$d" != "$PINNED" ]; then
  echo "certificate mismatch: $KIT/$SHOP_APK is not signed by the founder keystore" >&2
  exit 1
fi

{
  echo "myhanout release kit"
  echo "product: myhanout"
  echo "version_name: $V"
  echo "version_code: $N"
  echo "built_utc: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "signer_cert_sha256: $PINNED"
  echo "trust_anchor: APK signing certificate fingerprint (decision 1b; no signed manifest, no in-app verify screen)"
  echo "flavor_shopkeeper: $SHOP_APK package com.myhanout.myhanout"
  echo "flavor_admin: $ADMIN_APK package com.myhanout.admin"
  echo "integrity: sha256sum -c SHA256SUMS"
  echo "verify: bash tool/verify_release_bundle.sh <this-dir>"
  echo "handoff: docs/peer-to-peer-distribution.md"
} > "$KIT/RELEASE.txt"

for LANG in en fr ar; do
  sed -e "s/{{VERSION}}/$V/g" \
      -e "s/{{BUILD}}/$N/g" \
      -e "s/{{FINGERPRINT}}/$PINNED/g" \
      -e "s/{{DATE}}/$(date -u '+%Y-%m-%d')/g" \
      "tool/release_cards/$LANG.html" > "$KIT/install-$LANG.html"
done

echo "$N" > "$LAST"
echo
echo "kit assembled at: $KIT"
bash tool/verify_release_bundle.sh "$KIT"
