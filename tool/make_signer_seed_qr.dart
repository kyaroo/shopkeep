/// Renders ONE signer seed as a scannable QR for the in-app import screen.
///
/// Reads a single line from the founder's seeds file
/// (`~/.myhanout-keystore/signers-seeds.txt`, format
/// `  founder-admin  <base64url 32-byte seed>`), wraps it in a
/// `myhanout-signer-seed-v1` envelope and emits an SVG QR OUTSIDE the repo.
/// The matching `.myhanoutseed` text file (fallback for the file picker) is
/// written next to it.
///
/// SECRET HANDLING: the seed is NEVER printed, echoed in an error, copied into
/// the repo, or placed on stdout/stderr. Both the seeds path and the output path
/// are refused if they resolve inside the repository. stdout reports the signer
/// id only (a public value).
///
/// Usage:
///   dart run tool/make_signer_seed_qr.dart
///   dart run tool/make_signer_seed_qr.dart --signer admin-1 \
///       --seeds /path/outside/repo/seeds.txt --out /path/outside/qr.svg
library;

// ignore_for_file: avoid_print
// Justification: host-side ceremony tool; stdout IS the report, deliberately
// limited to PUBLIC values. Do NOT add this ignore to lib/ or test/.

import 'dart:convert';
import 'dart:io';

import 'package:myhanout/data/signing.dart';
import 'package:qr/qr.dart';

Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME'] ?? '';
  final seedsPath = _arg(args, '--seeds', '$home/.myhanout-keystore/signers-seeds.txt');
  final signerId = _arg(args, '--signer', 'founder-admin');
  var out = _arg(args, '--out', '');

  final repoRoot = Directory.current.path;
  if (_isInside(repoRoot, seedsPath)) {
    stderr.writeln('refusing a seeds path inside the repository');
    exit(2);
  }
  if (out.isNotEmpty && _isInside(repoRoot, out)) {
    stderr.writeln('refusing a QR output path inside the repository');
    exit(2);
  }
  if (out.isEmpty) {
    out = '$home/.myhanout-keystore/$signerId.qr.svg';
  }

  final seedsFile = File(seedsPath);
  if (!seedsFile.existsSync()) {
    stderr.writeln('seeds file not found (path withheld)');
    exit(2);
  }

  String? encoded;
  for (final line in seedsFile.readAsLinesSync()) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0] == signerId) {
      encoded = parts[1];
      break;
    }
  }
  if (encoded == null) {
    stderr.writeln('signer id not found in seeds file');
    exit(2);
  }

  final List<int> seed;
  try {
    seed = base64Url.decode(base64Url.normalize(encoded));
  } catch (_) {
    stderr.writeln('seed is not valid base64url');
    exit(2);
  }
  if (seed.length != 32) {
    stderr.writeln('seed is not 32 bytes');
    exit(2);
  }

  // The envelope holds the seed: it is written only to the OUTSIDE-repo files.
  final envelope = jsonEncode(<String, dynamic>{
    'format': ArtifactFormat.signerSeed,
    'signer_id': signerId,
    'seed': base64Url.encode(seed),
  });

  final qrFile = File(out);
  await qrFile.parent.create(recursive: true);
  await qrFile.writeAsString(_svg(envelope));

  final textPath = out.endsWith('.svg')
      ? '${out.substring(0, out.length - 4)}.myhanoutseed'
      : '$out.myhanoutseed';
  await File(textPath).writeAsString(envelope);

  // Only the PUBLIC signer id reaches stdout. Never echo the seed/path values.
  print('signer id: $signerId');
}

bool _isInside(String root, String path) {
  final rootAbs = File(root).absolute.path;
  final fileAbs = File(path).absolute.path;
  return fileAbs == rootAbs || fileAbs.startsWith('$rootAbs/');
}

String _arg(List<String> args, String key, String fallback) {
  final i = args.indexOf(key);
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  return fallback;
}

/// Minimal SVG QR: white background, black modules, 4-module quiet zone.
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
