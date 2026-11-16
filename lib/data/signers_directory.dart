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
  static Future<SignersDirectory> load({SettingsService? settings}) async {
    final store = settings ?? const ConfigSettingsService();
    final override = await store.getSignersEnvelope();
    if (override != null && override.isNotEmpty) {
      try {
        return await Signing.verifyDirectory(override);
      } catch (_) {
        // Tampered / corrupt / wrong-root override: fall back to the baked
        // directory. Fail closed for the override, never for the app.
      }
    }
    return Signing.verifyDirectory(await rootBundle.loadString(assetPath));
  }

  /// Adopts [envelope] if it verifies against the root key **and** its version
  /// is strictly higher. Returns the adopted directory, or null if refused.
  static Future<SignersDirectory?> replace(
    String envelope, {
    SettingsService? settings,
  }) async {
    final store = settings ?? const ConfigSettingsService();
    final SignersDirectory candidate;
    try {
      candidate = await Signing.verifyDirectory(envelope);
    } catch (_) {
      return null; // bad signature / wrong root / malformed
    }
    final current = await load(settings: store);
    if (candidate.version <= current.version) return null;
    await store.saveSignersEnvelope(envelope);
    return candidate;
  }
}
