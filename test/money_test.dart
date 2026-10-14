import 'package:flutter_test/flutter_test.dart';
import 'package:shopkeeper/utils/money.dart';

void main() {
  group('parseDirhamsToCents', () {
    test('parses dot-decimal dirham string to cents', () {
      expect(parseDirhamsToCents('19.90'), 1990);
      expect(parseDirhamsToCents('1250'), 125000);
      expect(parseDirhamsToCents('0.05'), 5);
    });
    test('accepts comma as decimal separator', () {
      expect(parseDirhamsToCents('19,90'), 1990);
      expect(parseDirhamsToCents('1 250,50'), 125050);
    });
    test('accepts space as thousands separator', () {
      expect(parseDirhamsToCents('1 250'), 125000);
    });
    test('rejects garbage and empty', () {
      expect(() => parseDirhamsToCents('abc'), throwsA(isA<FormatException>()));
      expect(() => parseDirhamsToCents(''), throwsA(isA<FormatException>()));
      expect(() => parseDirhamsToCents('-5'), throwsA(isA<FormatException>()));
    });
  });

  group('formatMoney', () {
    test('formats cents as MAD with space thousands + comma decimal', () {
      expect(formatMoney(1990), '19,90 MAD');
      expect(formatMoney(125050), '1 250,50 MAD');
      expect(formatMoney(5), '0,05 MAD');
      expect(formatMoney(0), '0,00 MAD');
    });
    test('whole dirhams show two decimals', () {
      expect(formatMoney(2000), '20,00 MAD');
    });
  });

  group('formatDirhamsInput', () {
    test('formats cents as editable dirham string', () {
      expect(formatDirhamsInput(1990), '19.90');
      expect(formatDirhamsInput(2000), '20.00');
      expect(formatDirhamsInput(5), '0.05');
    });
    test('round-trips through parseDirhamsToCents', () {
      for (final c in [5, 1990, 2000, 125050]) {
        expect(parseDirhamsToCents(formatDirhamsInput(c)), c);
      }
    });
  });
}
