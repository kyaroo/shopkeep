/// Renders a signers-directory envelope as an SVG QR the shopkeeper can scan.
///
/// The directory is the trust root, so it must be signed by the ROOT key — this
/// runs host-side, where the root seed lives. The shopkeeper scans the result
/// from the shop-entry screen ("Scanner le répertoire"); bulk data never
/// travels this way, only trust material.
///
/// Usage:
///   # render the baked directory as-is
///   dart run tool/make_signers_qr.dart --out scratch/directory.svg
///
///   # or rotate: build a new root-signed directory and render it
///   dart run tool/make_signers_qr.dart --out scratch/directory.svg \
///       --root-seed `base64url` --version 8 \
///       --signer `id:role:seed` --signer `id:role:seed`
///
/// The envelope is printed too, so the same value can be pasted into
/// `assets/signers.json` to bake it into the next build.
library;

// ignore_for_file: avoid_print
// Justification: host-side script; stdout IS the report. Do NOT add this
// ignore to lib/ or test/.

import 'dart:convert';
import 'dart:io';

import 'package:myhanout/data/signing.dart';
import 'package:qr/qr.dart';

Future<void> main(List<String> args) async {
  final out = _arg(args, '--out', 'signers_directory.svg');
  final envelopePath = _arg(args, '--envelope', '');
  final rootSeedB64 = _arg(args, '--root-seed', '');
  final signerArgs = _all(args, '--signer');

  final String envelope;
  if (envelopePath.isNotEmpty) {
    envelope = await File(envelopePath).readAsString();
  } else if (rootSeedB64.isNotEmpty && signerArgs.isNotEmpty) {
    final version = int.tryParse(_arg(args, '--version', '0')) ?? 0;
    envelope = await _buildDirectory(rootSeedB64, version, signerArgs);
  } else {
    envelope = await File('assets/signers.json').readAsString();
  }

  final dir = await Signing.verifyDirectory(envelope);
  await File(out).writeAsString(_svg(envelope));
  final who = dir.signers.map((s) => '${s.id}:${s.role.name}').join(', ');
  print('directory: version=${dir.version} signers=$who');
  print('svg: $out (${File(out).lengthSync()} B)');
  print('envelope (${envelope.length} B):');
  print(envelope);
}

Future<String> _buildDirectory(
    String rootSeedB64, int version, List<String> signerArgs) async {
  final rootSeed = base64Url.decode(base64Url.normalize(rootSeedB64));
  final signers = <Map<String, dynamic>>[];
  for (final spec in signerArgs) {
    final parts = spec.split(':');
    if (parts.length != 3 || parts.any((p) => p.isEmpty)) {
      stderr.writeln('bad --signer <id>:<role>:<seed>: $spec');
      exit(2);
    }
    final seed = base64Url.decode(base64Url.normalize(parts[2]));
    signers.add({
      'id': parts[0],
      'name': parts[0],
      'role': parts[1],
      'public_key': base64Url.encode(await Signing.publicKeyFromSeed(seed)),
    });
  }
  final now = DateTime.now().millisecondsSinceEpoch;
  return Signing.signPayload(<String, dynamic>{
    'format': ArtifactFormat.signers,
    'alg': Signing.algorithm,
    'version': version,
    'updated_at': now,
    'signers': signers,
  }, rootSeed);
}

/// Minimal SVG: white background, black modules, 4-module quiet zone.
String _svg(String data) {
  final qr = QrImage(QrCode.fromData(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.M,
  ));
  final n = qr.moduleCount;
  const scale = 8, quiet = 4;
  final size = (n + quiet * 2) * scale;
  final path = StringBuffer();
  for (var row = 0; row < n; row++) {
    for (var col = 0; col < n; col++) {
      if (qr.isDark(row, col)) {
        final x = (col + quiet) * scale;
        final y = (row + quiet) * scale;
        path.write('M$x ${y}h${scale}v${scale}h-${scale}z');
      }
    }
  }
  return '<svg xmlns="http://www.w3.org/2000/svg" width="$size" '
      'height="$size" viewBox="0 0 $size $size">'
      '<rect width="100%" height="100%" fill="white"/>'
      '<path d="$path" fill="black"/></svg>';
}

String _arg(List<String> args, String key, String fallback) {
  final i = args.indexOf(key);
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  return fallback;
}

List<String> _all(List<String> args, String key) {
  final out = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == key && i + 1 < args.length) out.add(args[i + 1]);
  }
  return out;
}
