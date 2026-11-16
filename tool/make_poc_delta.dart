// Generates a `.myhanout` catalog delta file.
//
// Usage:
//   dart run tool/make_poc_delta.dart \
//     --barcode 6111035001673 --name "Aïn Atlas 50cl" --category beverage \
//     --image test/poc/ain_atlas_off.jpg \
//     --base 1000 --target 1001 \
//     --signer-id founder-admin --private-seed <base64url> \
//     --out scratch/ain_atlas.myhanout
//
// Defaults reproduce the original Tabasco POC.
import 'dart:convert';
import 'dart:io';

import 'package:myhanout/data/catalog_delta.dart';
import 'package:myhanout/data/photo_processor.dart';
import 'package:myhanout/data/signing.dart';
import 'package:myhanout/models/catalog_entry.dart';

String _arg(List<String> args, String key, String fallback) {
  final i = args.indexOf(key);
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  return fallback;
}

Future<void> main(List<String> args) async {
  final barcode = _arg(args, '--barcode', '0011210006508');
  final name = _arg(args, '--name', 'Tabasco Habaneros hot');
  final nameEn = _arg(args, '--name-en', 'Tabasco Habanero Sauce');
  final category = _arg(args, '--category', 'grocery');
  final imagePath = _arg(args, '--image', 'test/poc/tabasco_off.jpg');
  final base = int.parse(_arg(args, '--base', '1000'));
  final target = int.parse(_arg(args, '--target', '1001'));
  final signerId = _arg(args, '--signer-id', 'founder-admin');
  final seedB64 = _arg(args, '--private-seed', '');
  if (seedB64.isEmpty) {
    stderr.writeln('missing --private-seed (the signer\'s 32-byte key, base64url)');
    exit(2);
  }
  final seed = base64Url.decode(base64Url.normalize(seedB64));
  final out = _arg(args, '--out', 'poc.myhanout');

  final photo = processPhoto(File(imagePath).readAsBytesSync());
  if (photo == null) {
    stderr.writeln('could not process image: $imagePath');
    exit(1);
  }

  final delta = CatalogDelta(
    signerId: signerId,
    baseVersion: base,
    targetVersion: target,
    generatedAt: target,
    upserts: [
      CatalogEntry(
        barcode: barcode,
        name: name,
        nameEn: nameEn.isEmpty ? null : nameEn,
        category: category,
        photo: photo,
        createdAt: base,
        updatedAt: target,
      ),
    ],
  );

  await File(out)
      .writeAsString(await Signing.signArtifactFile(delta.toPayload(), seed));
  stdout.writeln('wrote $out (${File(out).lengthSync()} B, '
      'photo ${photo.length} B, barcode $barcode, signer $signerId)');
}
