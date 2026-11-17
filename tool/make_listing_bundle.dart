// Builds a signed `.myhanoutlisting` on the host, for testing the delivery
// channel without walking the admin UI.
//
// The signer seed is read from the key ceremony file written by
// `tool/gen_signer_keys.dart`; it is never printed.
//
// Usage:
//   dart run tool/make_listing_bundle.dart \
//       --shop-key hanouti --catalog-version 7 \
//       --signer-id admin-1 \
//       --rows '[{"barcode":"0011210006508","price_cents":890,"stock_qty":12}]' \
//       --out scratch/listing_hanouti.myhanoutlisting
//
// Omit `--rows` to export an empty listing (useful for the rejection tests).
library;

// ignore_for_file: avoid_print
// Justification: host-side script; stdout IS the report, and it never prints a
// seed. Do NOT add this ignore to lib/ or test/.

import 'dart:convert';
import 'dart:io';

import 'package:myhanout/data/listing_bundle.dart';
import 'package:myhanout/data/signing.dart';
import 'package:myhanout/models/listing_row.dart';

Future<void> main(List<String> args) async {
  final shopKey = _arg(args, '--shop-key', '');
  final catalogVersion = int.tryParse(_arg(args, '--catalog-version', '0')) ?? 0;
  final signerId = _arg(args, '--signer-id', '');
  final rowsJson = _arg(args, '--rows', '');
  final seedsFile = _arg(args, '--seeds-file',
      '${Platform.environment['HOME']}/.myhanout-keystore/signers-seeds.txt');
  final out = _arg(args, '--out', '');

  if (shopKey.isEmpty || signerId.isEmpty || out.isEmpty) {
    stderr.writeln('usage: make_listing_bundle.dart --shop-key <key> '
        '--catalog-version <n> --signer-id <id> --rows <json> '
        '--out <file> [--seeds-file <path>]');
    exit(2);
  }

  final seed = await _seedFor(signerId, seedsFile);

  final rows = <ListingRow>[];
  if (rowsJson.isNotEmpty) {
    final list = jsonDecode(rowsJson);
    if (list is! List) {
      stderr.writeln('--rows must be a JSON array');
      exit(2);
    }
    for (final raw in list) {
      if (raw is! Map) {
        stderr.writeln('bad row: $raw');
        exit(2);
      }
      rows.add(ListingRow(
        barcode: raw['barcode'] as String,
        priceCents: (raw['price_cents'] as num).toInt(),
        stockQty: (raw['stock_qty'] as num?)?.toInt() ?? 0,
      ));
    }
  }

  final bundle = ListingBundle(
    signerId: signerId,
    shopKey: shopKey,
    catalogVersion: catalogVersion,
    generatedAt: DateTime.now().millisecondsSinceEpoch,
    rows: rows,
  );
  final json = await Signing.signArtifactFile(bundle.toPayload(), seed);
  await File(out).writeAsString(json);

  print('wrote $out (${rows.length} row(s), shop $shopKey, '
      'signer $signerId, ${File(out).lengthSync()} B)');
}

/// Finds `signerId` in the ceremony file. Format: `<id><spaces><seed>` per line.
Future<List<int>> _seedFor(String signerId, String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('seeds file not found: $path '
        '(run tool/gen_signer_keys.dart first)');
    exit(2);
  }
  for (final line in await file.readAsLines()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts.first == signerId) {
      return base64Url.decode(base64Url.normalize(parts.last));
    }
  }
  stderr.writeln('no seed for "$signerId" in $path');
  exit(2);
}

String _arg(List<String> args, String key, String fallback) {
  final i = args.indexOf(key);
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  return fallback;
}
