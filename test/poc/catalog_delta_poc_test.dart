/// POC 2 — `.myhanout` catalog delta: sign → verify → apply, offline.
///
/// Subject: barcode 0011210006508 (Tabasco Habanero Sauce) + its real OFF image
/// downscaled to 128px by the app's own [processPhoto].
///
/// The catalog is universal: a delta carries no shop binding, so any device
/// may apply any validly signed delta.
///
/// Run: flutter test test/poc/catalog_delta_poc_test.dart
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myhanout/data/catalog_delta.dart';
import 'package:myhanout/data/photo_processor.dart';
import 'package:myhanout/models/catalog_entry.dart';

const _barcode = '0011210006508';
const _offUrl =
    'https://images.openfoodfacts.org/images/products/001/121/000/6508/front_en.61.200.jpg';

Future<Uint8List> _sourceImage() async {
  final fixture = File('test/poc/tabasco_off.jpg');
  if (fixture.existsSync()) return fixture.readAsBytesSync();
  try {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    final req = await client.getUrl(Uri.parse(_offUrl));
    final resp = await req.close();
    if (resp.statusCode == 200) {
      final builder = BytesBuilder();
      await for (final chunk in resp) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    }
  } catch (_) {}
  final image = img.Image(width: 200, height: 183);
  img.fill(image, color: img.ColorRgb8(180, 40, 30));
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}

/// Minimal in-memory [CatalogRepository] so the delta logic runs without SQLite.
class _MemoryRepo implements CatalogRepository {
  final Map<String, CatalogEntry> _rows = {};
  int deletes = 0;

  @override
  Future<void> init() async {}

  @override
  Future<CatalogEntry?> get(String barcode) async => _rows[barcode];

  @override
  Future<List<CatalogEntry>> all({String? search, int? limit, int? offset}) async =>
      _rows.values.toList();

  @override
  Future<void> upsert(CatalogEntry entry) async => _rows[entry.barcode] = entry;

  @override
  Future<void> delete(String barcode) async {
    _rows.remove(barcode);
    deletes++;
  }

  @override
  Future<int> count({String? search}) async => _rows.length;
}

CatalogDelta _delta(Uint8List photo, {int base = 1000, int target = 1001}) =>
    CatalogDelta(
      baseVersion: base,
      targetVersion: target,
      generatedAt: target,
      upserts: [
        CatalogEntry(
          barcode: _barcode,
          name: 'Tabasco Habaneros hot',
          nameEn: 'Tabasco Habanero Sauce',
          category: 'grocery',
          photo: photo,
          createdAt: 1000,
          updatedAt: target,
        ),
      ],
    );

void main() {
  test('1. build + verify + apply, photo bytes survive', () async {
    final photo = processPhoto(await _sourceImage())!;
    final repo = _MemoryRepo();

    final file = _delta(photo).toFileJson();
    final v = CatalogDelta.verify(file);
    expect(v.ok, isTrue, reason: v.error);
    expect(v.delta!.baseVersion, 1000);
    expect(v.delta!.targetVersion, 1001);

    await v.delta!.apply(repo);
    final stored = await repo.get(_barcode);
    expect(stored, isNotNull);
    expect(stored!.name, 'Tabasco Habaneros hot');
    expect(stored.category, 'grocery');
    expect(stored.photo, equals(photo));

    // ignore: avoid_print
    print('POC2 photo=${photo.length}B  file=${file.length}B  '
        'applied=1 entry, photo identical');
  });

  test('2. tampered payload is rejected', () async {
    final photo = processPhoto(await _sourceImage())!;
    final file = _delta(photo).toFileJson();
    final map = jsonDecode(file) as Map<String, dynamic>;
    (map['upserts'] as List).first['name'] = 'Fake Product';
    final v = CatalogDelta.verify(jsonEncode(map));
    expect(v.ok, isFalse);
    expect(v.error, 'bad signature');
  });

  test('3. unsigned file is rejected', () async {
    final photo = processPhoto(await _sourceImage())!;
    final file = _delta(photo).toFileJson();
    final map = (jsonDecode(file) as Map<String, dynamic>)..remove('signature');
    final v = CatalogDelta.verify(jsonEncode(map));
    expect(v.ok, isFalse);
    expect(v.error, 'missing signature');
  });

  test('4. apply is idempotent', () async {
    final photo = processPhoto(await _sourceImage())!;
    final repo = _MemoryRepo();
    final v = CatalogDelta.verify(_delta(photo).toFileJson());
    await v.delta!.apply(repo);
    final first = await repo.get(_barcode);
    await v.delta!.apply(repo);
    final second = await repo.get(_barcode);
    expect(await repo.count(), 1);
    expect(second!.updatedAt, first!.updatedAt);
    expect(second.photo, equals(first.photo));
  });
}
