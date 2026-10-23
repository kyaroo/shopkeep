# myhanout — offline inventory & checkout for small shops

A tiny, easy Flutter app so a shop manager can **inventory products** and **run a
checkout (POS)** from any Android phone. No server, no account, works offline.
Barcode scanning (camera) adds products and fills the cart fast.

## Features (v1)
- **Checkout tab** — scan or tap a product → cart with qty steppers → live total
  → "Complete sale" deducts stock.
- **Inventory tab** — list / search / add / edit / delete products, scan-to-fill
  barcode, out-of-stock indicator.
- **Offline-first** — data lives on the device (SQLite). No internet needed to sell.
- Money stored as integer cents (no rounding bugs).

## Out of scope for v1
Real card payment (sales are recorded manually), cloud sync, multi-device,
sales history/reports, user accounts, receipts printing. All are easy follow-ups.

## Requirements
- Flutter 3.47+ (tested on stable 3.47.1)
- Android SDK (build-tools 35.0.0, platform android-35, platform-tools)
- An Android phone to install the APK (debug build) — no Play Store needed.

## Run (development)
```
flutter pub get
flutter analyze
flutter test            # cart totals + stock-deduction logic
flutter run             # needs a device/emulator
```

## Build the installable APK
```
flutter build apk --debug        # app-debug.apk (install via adb or file share)
flutter build apk --release      # signed release APK (configure signing first)
```
Output: `build/app/outputs/flutter-apk/app-debug.apk`

Install on the phone:
```
adb install build/app/outputs/flutter-apk/app-debug.apk
```

## Project layout
```
lib/
  main.dart                 # app shell + bottom nav (Checkout / Inventory)
  models/product.dart       # Product entity (price in cents)
  models/cart.dart          # pure checkout logic (unit-tested)
  data/db.dart              # SQLite layer (sqflite)
  providers/cart_provider.dart
  screens/checkout_screen.dart
  screens/inventory_screen.dart
  utils/money.dart          # cents -> "12.34"
test/
  cart_test.dart
```

## Next steps (suggested)
1. Sales history + CSV export (share_plus).
2. Cloud backup / sync (Supabase or a small API) for multi-phone shops.
3. Real payment integration.
4. iOS build (requires a Mac + Xcode).
