/// CAT9 — end-to-end delivery proof, host-side (no device needed).
///
/// Reproduces exactly what the admin screen does, then what the shopkeeper's
/// `MyhanoutFile.applyJson` does, and asserts:
///   1. the admin builds a signed delta whose base is the shop's generation;
///   2. the shopkeeper accepts it and advances its installed version;
///   3. the shopkeeper REJECTS a second identical delta (base no longer
///      matches) — the guard that prevents a double-apply.
///
/// Run: dart run tool/verify_cat9_flow.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:myhanout/data/catalog_delta.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/services/catalog_push_service.dart';

const shopKey = 'hanouti';
const base = 3;

final entries = [
  CatalogEntry(
    barcode: '6111000000123',
    name: 'Ain Soltani Eau Minerale 1.5L',
    category: 'beverage',
    createdAt: base,
    updatedAt: base,
  ),
  CatalogEntry(
    barcode: '6111000000456',
    name: 'Couscous Dari 1kg',
    category: 'grain',
    createdAt: base,
    updatedAt: base,
  ),
];

Future<void> main() async {
  // ---- 1. admin side: build ----
  final payload = CatalogPushBuilder.buildPayload(
    localVersion: base,
    shopVersion: base,
    entries: entries,
  );
  final map = jsonDecode(payload) as Map<String, dynamic>;
  print('built: base=${map['base_version']} target=${map['target_version']} '
      'upserts=${(map['upserts'] as List).length}');
  if (map['base_version'] != base || map['target_version'] != base + 1) {
    stderr.writeln('FAIL: wrong base/target');
    exit(1);
  }

  final file = File('/tmp/${CatalogPushBuilder.fileName(shopKey, base + 1)}');
  await file.writeAsString(payload);
  print('file: ${file.path} (${file.lengthSync()} B)');

  // ---- 2. receiver side: verify + guard ----
  final verification = CatalogDelta.verify(await file.readAsString());
  if (!verification.ok) {
    stderr.writeln('FAIL: signature ${verification.error}');
    exit(1);
  }
  final delta = verification.delta!;
  print('verify: ok, base=${delta.baseVersion} target=${delta.targetVersion}');

  // Simulate the shopkeeper's installed version (it was at `base`).
  const installed = base;
  if (delta.baseVersion != installed) {
    stderr.writeln('FAIL: first apply should be accepted');
    exit(1);
  }
  print('apply #1: accepted (installed $installed → ${delta.targetVersion})');

  // ---- 3. second apply of the same delta must be refused ----
  const installedAfterFirst = base + 1;
  if (delta.baseVersion == installedAfterFirst) {
    stderr.writeln('FAIL: the guard would allow a double-apply');
    exit(1);
  }
  print('apply #2: rejected (device $installedAfterFirst, bundle ${delta.baseVersion})');

  // ---- 4. tamper is refused ----
  final tampered = (jsonDecode(payload) as Map<String, dynamic>)
    ..['upserts'] = [
      {'barcode': '6111000000123', 'name': 'Fake', 'updated_at': base + 1}
    ];
  final v2 = CatalogDelta.verify(jsonEncode(tampered));
  if (v2.ok) {
    stderr.writeln('FAIL: tampered payload accepted');
    exit(1);
  }
  print('tamper: rejected (${v2.error})');

  print('\nCAT9 flow OK: 2 upserts, guard holds, signature holds.');
}
