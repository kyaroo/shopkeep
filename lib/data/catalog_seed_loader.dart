import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../utils/app_log.dart';
import 'config.dart';

/// Best-effort copy of the bundled `assets/catalog_seed.db` to [dbPath] on
/// first launch. Never overwrites an existing DB (so refreshes/updates are
/// preserved) and never throws — failures fall back to an empty DB.
class CatalogSeedLoader {
  CatalogSeedLoader._();

  static const assetPath = 'assets/catalog_seed.db';

  /// Version of the bundled catalog snapshot.
  ///
  /// Bump this whenever `assets/catalog_seed.db` is rebuilt from a newer
  /// catalog generation: a `.myhanout` delta built against a different
  /// generation is then rejected by the base-version guard instead of
  /// half-applying. [CatalogDb] adopts it on first seed.
  static const int seedCatalogVersion = 1;

  /// Returns true if a seed was copied.
  static Future<bool> ensureSeeded(String dbPath) async {
    final file = File(dbPath);
    if (file.existsSync()) return false;

    Uint8List? bytes;
    try {
      final data = await rootBundle.load(assetPath);
      bytes = data.buffer.asUint8List();
    } catch (e) {
      logWarning('catalog seed asset failed to load', error: e);
      return false;
    }
    if (bytes.isEmpty) return false;

    final tmp = File('$dbPath.tmp');
    try {
      await tmp.writeAsBytes(bytes, flush: true);
      // Validate before promoting.
      final check = await _quickCheck(tmp.path);
      if (check != 'ok') {
        await _safeDelete(tmp);
        return false;
      }
      if (file.existsSync()) {
        // Race: another caller seeded first.
        await _safeDelete(tmp);
        return false;
      }
      await tmp.rename(dbPath);
      // Adopt the snapshot's catalog version so the first delta must be built
      // against it (base-version guard).
      try {
        await Config.setCatalogVersion(seedCatalogVersion);
      } catch (e) {
        logWarning('catalog seed version not recorded', error: e);
      }
      return true;
    } catch (_) {
      await _safeDelete(tmp);
      return false;
    }
  }

  static Future<String> _quickCheck(String path) async {
    // Lightweight validation without opening via sqflite (which may not be
    // initialised in every context). Just check the SQLite header magic.
    try {
      final f = File(path);
      final head = await f.openRead(0, 16).first;
      // SQLite database file header starts with "SQLite format 3\0".
      const magic = [0x53, 0x51, 0x4c, 0x69, 0x74, 0x65, 0x20, 0x66, 0x6f, 0x72, 0x6d, 0x61, 0x74, 0x20, 0x33, 0x00];
      if (head.length < 16) return 'bad';
      for (var i = 0; i < 16; i++) {
        if (head[i] != magic[i]) return 'bad';
      }
      return 'ok';
    } catch (_) {
      return 'bad';
    }
  }

  static Future<void> _safeDelete(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
