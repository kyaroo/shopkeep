// BUG C — the photo budget inside a `.myhanout` delta.
//
// CatalogDeltaBuilder must never emit a photo over kMaxDeltaPhotoBytes: the
// server refuses >64 KB, so an unbounded delta breaks at the push boundary.
// Oversized photos are re-encoded; if that still does not fit they are
// dropped from the entry (name/category survive).
//
// Run: flutter test test/services/catalog_delta_builder_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myhanout/data/photo_processor.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/services/catalog_delta_service.dart';

/// Encodes a noisy JPEG. Noise compresses poorly, so a big canvas at a high
/// quality reliably exceeds the budget — while still being decodable.
Uint8List _rawJpeg(int w, int h, int quality) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgba(x, y, (x * 7 + y * 3) % 256, (x * 3 + y * 11) % 256,
          (x + y * 5) % 256, 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

/// A valid, decodable JPEG over the budget (processPhoto will shrink it).
final Uint8List _bigPhoto = _rawJpeg(1400, 1400, 95);

/// An in-budget photo, already through processPhoto.
final Uint8List _smallPhoto = processPhoto(_bigPhoto)!;

/// Over budget AND not a decodable image → must be dropped.
final Uint8List _oversizedJunk = Uint8List.fromList(
  List<int>.generate(kMaxDeltaPhotoBytes + 1024, (i) => 65 + (i % 26)),
);

void main() {
  test('builds a signed delta with base/target versions', () {
    final result = CatalogDeltaBuilder.build(
      baseVersion: 1000,
      targetVersion: 1001,
      generatedAt: 1001,
      entries: [
        CatalogEntry(
          barcode: '0011210006508',
          name: 'Tabasco Habaneros hot',
          nameEn: 'Tabasco Habanero Sauce',
          category: 'grocery',
          photo: null,
          createdAt: 1000,
          updatedAt: 1001,
        ),
      ],
      deletes: [],
    );

    expect(() => jsonDecode(result.json), returnsNormally);

    final map = jsonDecode(result.json) as Map<String, dynamic>;
    expect(map['format'], 'myhanout-catalog-delta');
    expect(map['base_version'], 1000);
    expect(map['target_version'], 1001);
    expect(map['generated_at'], 1001);
    expect(map['upserts'], isA<List>());
    expect(map['deletes'], isA<List>());
    expect(map['signature'], isA<String>());

    expect(result.upserts, 1);
    expect(result.deletes, 0);
    expect(result.photosUntouched, isTrue);
  });

  test('applies updatedAt to upserts', () {
    final result = CatalogDeltaBuilder.build(
      baseVersion: 1000,
      targetVersion: 1001,
      generatedAt: 1001,
      entries: [
        CatalogEntry(
          barcode: '0011210006508',
          name: 'Tabasco',
          category: 'grocery',
          photo: null,
          createdAt: 1000,
          updatedAt: 1000,
        ),
      ],
      deletes: [],
    );
    final map = jsonDecode(result.json) as Map<String, dynamic>;
    final upsert = map['upserts'] as List;
    expect(upsert.length, 1);
    expect(upsert.first['updated_at'], 1001);
  });

  test('a photo at or under the budget passes through untouched', () {
    expect(_smallPhoto.length, lessThanOrEqualTo(kMaxDeltaPhotoBytes));

    final result = CatalogDeltaBuilder.build(
      baseVersion: 1,
      targetVersion: 2,
      generatedAt: 2,
      entries: [
        CatalogEntry(
          barcode: 'A',
          name: 'A',
          photo: _smallPhoto,
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
    );

    expect(result.photosUntouched, isTrue);
    final map = jsonDecode(result.json) as Map<String, dynamic>;
    expect((map['upserts'] as List).first['photo_base64'], isNotNull);
  });

  test('an oversized decodable photo is resized under the budget', () {
    expect(_bigPhoto.length, greaterThan(kMaxDeltaPhotoBytes),
        reason: 'fixture must exceed the budget to exercise the resize path');

    final result = CatalogDeltaBuilder.build(
      baseVersion: 1,
      targetVersion: 2,
      generatedAt: 2,
      entries: [
        CatalogEntry(
          barcode: 'B',
          name: 'B',
          photo: _bigPhoto,
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
    );

    expect(result.photosTrimmed, 1);
    expect(result.photosDropped, 0);
    final map = jsonDecode(result.json) as Map<String, dynamic>;
    final b64 = (map['upserts'] as List).first['photo_base64'] as String;
    expect(b64, isNotEmpty);
    expect(base64Decode(b64).length, lessThanOrEqualTo(kMaxDeltaPhotoBytes));
  });

  test('an oversized photo that cannot be re-encoded is dropped', () {
    final result = CatalogDeltaBuilder.build(
      baseVersion: 1,
      targetVersion: 2,
      generatedAt: 2,
      entries: [
        CatalogEntry(
          barcode: 'C',
          name: 'C',
          photo: _oversizedJunk,
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
    );

    expect(result.photosDropped, 1);
    expect(result.photosTrimmed, 0);
    final map = jsonDecode(result.json) as Map<String, dynamic>;
    final upsert = (map['upserts'] as List).first;
    // The entry survives; only the photo goes.
    expect(upsert['barcode'], 'C');
    expect(upsert['name'], 'C');
    expect(upsert['photo_base64'], isNull);
  });

  test('mixed batch reports both counters', () {
    final result = CatalogDeltaBuilder.build(
      baseVersion: 1,
      targetVersion: 2,
      generatedAt: 2,
      entries: [
        CatalogEntry(
            barcode: 'ok', name: 'ok', photo: _smallPhoto, createdAt: 1, updatedAt: 1),
        CatalogEntry(
            barcode: 'trim', name: 'trim', photo: _bigPhoto, createdAt: 1, updatedAt: 1),
        CatalogEntry(
            barcode: 'drop', name: 'drop', photo: _oversizedJunk, createdAt: 1, updatedAt: 1),
      ],
    );

    expect(result.upserts, 3);
    expect(result.photosTrimmed, 1);
    expect(result.photosDropped, 1);
    expect(result.photosUntouched, isFalse);
  });
}
