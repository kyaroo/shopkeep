import 'package:flutter/services.dart' show rootBundle;

import 'settings_service.dart';
import 'signing.dart';

/// Loads and replaces the signers directory.
///
/// The baked asset is the fallback. A scanned override is persisted **verbatim**
/// and re-verified against the baked root key on **every** load, so a tampered
/// or restored prefs store can never swap the trust anchor (review CR-01).
class SignersDirectoryLoader {
  SignersDirectoryLoader._();

  static const String assetPath = 'assets/signers.json';

  /// The active directory: the persisted override if it verifies, else baked.
  ///
  /// [rootPublicKey] defaults to the baked root; tests substitute their own.
  static Future<SignersDirectory> load({
    SettingsService? settings,
    List<int>? rootPublicKey,
  }) async {
    final store = settings ?? const ConfigSettingsService();
    final root = rootPublicKey ?? Signing.bakedRootPublicKey;
    final override = await store.getSignersEnvelope();
    if (override != null && override.isNotEmpty) {
      try {
        return await Signing.verifyDirectoryWith(override, root);
      } catch (_) {
        // Tampered / corrupt / wrong-root override: fall back to the baked
        // directory. Fail closed for the override, never for the app.
      }
    }
    return Signing.verifyDirectoryWith(
        await rootBundle.loadString(assetPath), root);
  }

  /// Adopts [envelope] if it verifies against the root key **and** its version
  /// is strictly higher. Returns the adopted directory, or null if refused.
  static Future<SignersDirectory?> replace(
    String envelope, {
    SettingsService? settings,
    List<int>? rootPublicKey,
  }) async {
    final store = settings ?? const ConfigSettingsService();
    final root = rootPublicKey ?? Signing.bakedRootPublicKey;
    final SignersDirectory candidate;
    try {
      candidate = await Signing.verifyDirectoryWith(envelope, root);
    } catch (_) {
      return null; // bad signature / wrong root / malformed
    }
    SignersDirectory? current;
    try {
      current = await load(settings: store, rootPublicKey: root);
    } catch (_) {
      current = null; // no usable directory yet — the candidate becomes the first
    }
    if (current != null && candidate.version <= current.version) return null;
    await store.saveSignersEnvelope(envelope);
    return candidate;
  }
}
