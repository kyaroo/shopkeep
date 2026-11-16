// Rotates the baked signers directory: generates a fresh ROOT keypair and the
// signer keypairs, writes `assets/signers.json`, and renders the directory QR.
//
// The ROOT key signs the directory ONLY; the founder-admin / admin-N keys sign
// artifacts; salesman keys may provision but never push.
//
// SECRET HANDLING: private seeds are written to `--seeds-out` (default
// `~/.myhanout-keystore/signers-seeds.txt`, outside the repo) and are NEVER
// printed. The tool refuses a seeds path inside the repository. Only the public
// root key is echoed, because it must replace `kRootPublicKeyB64` in
// `lib/data/signing.dart`.
//
// Usage:
//   dart run tool/gen_signer_keys.dart
//   dart run tool/gen_signer_keys.dart --seeds-out /path/outside/repo.txt \
//       --qr-out scratch/signers_directory.svg
//
// Re-running rotates every key: re-issue QRs and re-bake the directory. Existing
// artifacts signed by the old keys stop verifying — that is the point.
library;

// ignore_for_file: avoid_print
// Justification: host-side key ceremony script; stdout IS the report, and it is
// deliberately limited to PUBLIC values. Do NOT add this ignore to lib/ or test/.

import 'dart:convert';
import 'dart:io';

import 'package:myhanout/data/signing.dart';
import 'package:qr/qr.dart';

const signers = [
  ('founder-admin', 'Fondateur', SignerRole.founder),
  ('admin-1', 'Admin', SignerRole.admin),
  ('salesman-1', 'Omar', SignerRole.salesman),
];

Future<void> main(List<String> args) async {
  final seedsOut = _arg(args, '--seeds-out',
      '${Platform.environment['HOME']}/.myhanout-keystore/signers-seeds.txt');
  final qrOut = _arg(args, '--qr-out', '');

  final repoRoot = Directory.current.path;
  final seedsFile = File(seedsOut);
  if (_isInside(repoRoot, seedsFile.path)) {
    stderr.writeln('refusing to write private seeds inside the repository: '
        '$seedsOut');
    exit(2);
  }

  final rootPrivate = await Signing.generateSigner();
  final rootPublic = await Signing.publicKeyFromSeed(rootPrivate);

  final entries = <Map<String, dynamic>>[];
  final seedLines = <String>[
    '# myhanout signers directory - PRIVATE SEEDS. Keep offline; never commit.',
    '# generated ${DateTime.now().toUtc()}',
    'root           ${base64Url.encode(rootPrivate)}',
  ];
  for (final (id, name, role) in signers) {
    final seed = await Signing.generateSigner();
    seedLines.add('  $id  ${base64Url.encode(seed)}');
    entries.add({
      'id': id,
      'name': name,
      'role': role.name,
      'public_key': base64Url.encode(await Signing.publicKeyFromSeed(seed)),
    });
  }

  final payload = <String, dynamic>{
    'format': ArtifactFormat.signers,
    'alg': Signing.algorithm,
    'version': await _currentVersion() + 1,
    'updated_at': DateTime.now().millisecondsSinceEpoch,
    'signers': entries,
  };
  final envelope = await Signing.signPayload(payload, rootPrivate);
  await File('assets/signers.json').writeAsString(envelope); // exact bytes

  final baked = await Signing.verifyDirectoryWith(envelope, rootPublic);
  await seedsFile.parent.create(recursive: true);
  await seedsFile.writeAsString('${seedLines.join('\n')}\n');

  print('wrote assets/signers.json '
      '(${baked.signers.length} signers, version ${baked.version})');
  print('private seeds -> ${seedsFile.path} '
      '(${seedsFile.lengthSync()} B, NOT printed)');
  print('');
  print('replace kRootPublicKeyB64 in lib/data/signing.dart with:');
  print("  const String kRootPublicKeyB64 = '${base64Url.encode(rootPublic)}';");

  if (qrOut.isNotEmpty) {
    await File(qrOut).writeAsString(_svg(envelope));
    print('directory QR -> $qrOut (${File(qrOut).lengthSync()} B)');
  }
}

bool _isInside(String root, String path) {
  final rootAbs = File(root).absolute.path;
  final fileAbs = File(path).absolute.path;
  return fileAbs == rootAbs || fileAbs.startsWith('$rootAbs/');
}

/// The baked directory's version, so a rotation is always +1 and the number
/// stays meaningful to a human reading the UI.
///
/// Read from the envelope's payload WITHOUT verifying it: a rotation is exactly
/// the case where the baked root key no longer matches the file on disk.
Future<int> _currentVersion() async {
  final f = File('assets/signers.json');
  if (!f.existsSync()) return 0;
  try {
    final parts = (await f.readAsString()).trim().split('.');
    if (parts.length != 2) return 0;
    final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))));
    final version = (payload as Map)['version'];
    return version is int ? version : 0;
  } catch (_) {
    return 0; // corrupt/absent directory: start from 1
  }
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
