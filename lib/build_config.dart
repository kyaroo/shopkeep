/// Compile-time build flags.
///
/// [kIsAdmin] is true only when the app is built with
/// `--dart-define=ADMIN=true` (admin flavor). End-user (shopkeeper) builds
/// leave it false, so founder-only catalog tools stay out of the POS APK.
const bool kIsAdmin = bool.fromEnvironment('ADMIN', defaultValue: false);
