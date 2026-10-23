import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:myhanout/models/catalog_entry.dart';
import 'package:myhanout/data/catalog_db.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('upsert then get round-trips barcode/name/category', () async {
    final repo = CatalogDb.instance;
    await repo.init();
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = CatalogEntry(
      barcode: '6111234567890',
      name: 'Aïn Soltani Eau 1.5L',
      category: 'beverage',
      createdAt: now,
      updatedAt: now,
    );
    await repo.upsert(entry);

    final got = await repo.get('6111234567890');
    expect(got, isNotNull);
    expect(got!.name, 'Aïn Soltani Eau 1.5L');
    expect(got.category, 'beverage');
  });

  test('upsert same barcode updates in place (PK), not duplicate', () async {
    final repo = CatalogDb.instance;
    await repo.init();
    final t = DateTime.now().millisecondsSinceEpoch;
    await repo.upsert(CatalogEntry(
        barcode: 'UPDATE1', name: 'Old', createdAt: t, updatedAt: t));
    await repo.upsert(CatalogEntry(
        barcode: 'UPDATE1', name: 'New', createdAt: t, updatedAt: t + 1));

    final all = await repo.all();
    final matches = all.where((e) => e.barcode == 'UPDATE1').toList();
    expect(matches.length, 1);
    expect(matches.first.name, 'New');
  });

  test('photo BLOB survives round-trip', () async {
    final repo = CatalogDb.instance;
    await repo.init();
    final t = DateTime.now().millisecondsSinceEpoch;
    final bytes = Uint8List.fromList(List.filled(64, 7));
    await repo.upsert(CatalogEntry(
      barcode: 'PHOTO1',
      name: 'Has photo',
      photo: bytes,
      createdAt: t,
      updatedAt: t,
    ));
    final got = await repo.get('PHOTO1');
    expect(got!.photo, isNotNull);
    expect(got.photo!.length, 64);
  });

  test('search matches name, barcode, and category', () async {
    final repo = CatalogDb.instance;
    await repo.init();
    final t = DateTime.now().millisecondsSinceEpoch;
    // Unique terms so the shared singleton DB from other tests can't collide.
    await repo.upsert(CatalogEntry(
        barcode: 'SEARCHQ1', name: 'Qzx Tea', category: 'qzxcat',
        createdAt: t, updatedAt: t));
    expect((await repo.all(search: 'Qzx')).length, 1);
    expect((await repo.all(search: 'qzxcat')).length, 1);
    expect((await repo.all(search: 'SEARCHQ1')).length, 1);
    expect((await repo.all(search: 'zzznomatch')).length, 0);
  });

  test('delete removes the entry', () async {
    final repo = CatalogDb.instance;
    await repo.init();
    final t = DateTime.now().millisecondsSinceEpoch;
    await repo.upsert(CatalogEntry(
        barcode: 'DEL1', name: 'To delete', createdAt: t, updatedAt: t));
    await repo.delete('DEL1');
    expect(await repo.get('DEL1'), isNull);
  });

  test('name_ar / name_en round-trip through the DB', () async {
    final repo = CatalogDb.instance;
    await repo.init();
    final t = DateTime.now().millisecondsSinceEpoch;
    await repo.upsert(CatalogEntry(
      barcode: 'MULTI1',
      name: 'Ain Soltani Eau',
      nameAr: 'مياه العين السلطانية',
      nameEn: 'Soltani Water',
      createdAt: t,
      updatedAt: t,
    ));
    final got = await repo.get('MULTI1');
    expect(got!.nameAr, 'مياه العين السلطانية');
    expect(got.nameEn, 'Soltani Water');
  });

  test('search matches the Arabic name too', () async {
    final repo = CatalogDb.instance;
    await repo.init();
    final t = DateTime.now().millisecondsSinceEpoch;
    await repo.upsert(CatalogEntry(
      barcode: 'ARSEARCH1',
      name: 'Couscous Dari',
      nameAr: 'كسكسداري',
      createdAt: t,
      updatedAt: t,
    ));
    expect((await repo.all(search: 'كسكس')).length, 1);
  });

  test('displayName falls back to the French primary', () {
    final t = DateTime.now().millisecondsSinceEpoch;
    final frenchOnly = CatalogEntry(
        barcode: 'D1', name: 'Dari', createdAt: t, updatedAt: t);
    // No Arabic/English stored -> both locales show the French primary.
    expect(frenchOnly.displayName('ar'), 'Dari');
    expect(frenchOnly.displayName('en'), 'Dari');
    expect(frenchOnly.displayName('fr'), 'Dari');

    final withAr = frenchOnly.copyWith(nameAr: 'داري');
    expect(withAr.displayName('ar'), 'داري');
    expect(withAr.displayName('fr'), 'Dari'); // fr stays primary
    expect(withAr.displayName('en'), 'Dari'); // en falls back to fr
  });
}
