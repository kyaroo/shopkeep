// Builds a `.myhanout` catalog delta from a JSON export of catalog photos.
//
// The catalog is universal: no shop binding, so the same delta applies to any
// shop. Only the base/target catalog versions matter.
//
// Usage:
//   dart run tool/make_catalog_delta.dart <export.json> <out.myhanout> \
//       <baseVersion> <targetVersion>
import 'dart:convert';
import 'dart:io';

import 'package:myhanout/data/catalog_delta.dart';
import 'package:myhanout/models/catalog_entry.dart';

Future<void> main(List<String> args) async {
  if (args.length != 4) {
    stderr.writeln('usage: make_catalog_delta.dart <export> <out> '
        '<base> <target>');
    exit(2);
  }
  final exportPath = args[0];
  final outPath = args[1];
  final base = int.parse(args[2]);
  final target = int.parse(args[3]);

  final rows = jsonDecode(await File(exportPath).readAsString()) as List;
  final upserts = rows
      .map((r) {
        final m = r as Map<String, dynamic>;
        final b64 = m['photo_base64'] as String?;
        return CatalogEntry(
          barcode: m['barcode'] as String,
          name: (m['name'] as String?) ?? '',
          nameAr: m['name_ar'] as String?,
          nameEn: m['name_en'] as String?,
          category: m['category'] as String?,
          photo: (b64 == null || b64.isEmpty) ? null : base64Decode(b64),
          createdAt: base,
          updatedAt: target,
        );
      })
      .toList();

  final delta = CatalogDelta(
    baseVersion: base,
    targetVersion: target,
    generatedAt: target,
    upserts: upserts,
  );
  await File(outPath).writeAsString(delta.toFileJson());
  stdout.writeln('wrote $outPath (${upserts.length} products, '
      '${File(outPath).lengthSync()} B)');
}
