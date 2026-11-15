/// POC 1 — product photo pipeline (format · storage · display · transfer).
///
/// One real product (Nutella, barcode 3017620422003) exercises the exact code
/// paths the shop bundle will use:
///   OFF image  →  processPhoto()  →  SQLite BLOB  →  Image.memory  →  base64 JSON
///
/// Run: flutter test test/poc/photo_pipeline_poc_test.dart
library photo_pipeline_poc_test;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myhanout/data/photo_processor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _barcode = '3017620422003';
const _offUrl =
    'https://images.openfoodfacts.org/images/products/301/762/042/2003/front_en.879.200.jpg';

/// Real OFF image if the fixture is present, else fetched, else synthetic.
Future<Uint8List> _sourceImage() async {
  final fixture = File('test/poc/nutella_off.jpg');
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
  // Deterministic fallback so the POC always runs offline.
  final image = img.Image(width: 200, height: 183);
  img.fill(image, color: img.ColorRgb8(198, 120, 40));
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}

/// Mirrors catalog_home_page._productLeading (44x44 thumbnail).
class _Tile extends StatelessWidget {
  const _Tile({this.photo});
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    if (photo != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(photo!, width: 44, height: 44, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 44,
      height: 44,
      color: Theme.of(context).colorScheme.secondary,
      child: const Icon(Icons.store, color: Colors.white, size: 20),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('1. processPhoto: real image -> <=128px JPEG, measured size', () async {
    final src = await _sourceImage();
    final out = processPhoto(src);
    expect(out, isNotNull, reason: 'processPhoto rejected the image');
    final decoded = img.decodeImage(out!);
    expect(decoded, isNotNull, reason: 'output is not a decodable image');
    expect(decoded!.width, lessThanOrEqualTo(128));
    // ignore: avoid_print
    print('POC1 source=${src.length}B  processed=${out.length}B  '
        'dimensions=${decoded.width}x${decoded.height}');
  });

  test('2. SQLite BLOB round-trip (real products schema)', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) => db.execute('''
        CREATE TABLE products (
          barcode TEXT PRIMARY KEY, name TEXT NOT NULL, name_ar TEXT,
          name_en TEXT, category TEXT, photo BLOB,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)
      '''),
      ),
    );
    final photo = processPhoto(await _sourceImage())!;
    await db.insert('products', {
      'barcode': _barcode,
      'name': 'Nutella',
      'photo': photo,
      'created_at': 1,
      'updated_at': 1,
    });
    final rows =
        await db.query('products', where: 'barcode = ?', whereArgs: [_barcode]);
    final stored = rows.first['photo'] as Uint8List;
    expect(stored, equals(photo));
    // ignore: avoid_print
    print('POC1 blob round-trip OK (${stored.length}B identical)');
    await db.close();
  });

  test('3. Bundle format: photo -> base64 -> JSON -> decode -> identical', () async {
    final photo = processPhoto(await _sourceImage())!;
    final b64 = base64Encode(photo);
    final json = jsonEncode({
      'format': 'myhanout-shop-bundle',
      'version': 1,
      'shop_key': 'hanouti',
      'products': [
        {'barcode': _barcode, 'name': 'Nutella', 'photo_base64': b64}
      ],
    });
    final back = jsonDecode(json) as Map<String, Object?>;
    final p = (back['products'] as List).first as Map<String, Object?>;
    final decoded = base64Decode(p['photo_base64'] as String);
    expect(decoded, equals(photo));
    // ignore: avoid_print
    print('POC1 base64=${b64.length} chars  json=${json.length}B  '
        'overhead=${(b64.length / photo.length).toStringAsFixed(2)}x');
  });

  testWidgets('4. Display: tile renders the photo as a MemoryImage',
      (tester) async {
    final photo = processPhoto(await _sourceImage())!;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Center(child: _Tile(photo: null)))),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: _Tile(photo: photo)))),
    );
    final finder = find.byType(Image);
    expect(finder, findsOneWidget);
    final widget = tester.widget<Image>(finder);
    expect(widget.image, isA<MemoryImage>());
    expect((widget.image as MemoryImage).bytes, equals(photo));
    // ignore: avoid_print
    print('POC1 display OK (Image.memory, ${photo.length}B)');
  });
}
