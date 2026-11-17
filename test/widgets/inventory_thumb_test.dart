// Regression guard for the truncated inventory name.
//
// The row's `leading` used to be an intrinsically-sized stock pill when a
// product had no photo. ListTile reserves the leading's intrinsic width, so
// photo-less rows reserved 87px (French "En stock") instead of the photo's
// 44px and the name's column collapsed from 311px to 53px — the name was cut
// off, and the damage varied by locale.
//
// Run: flutter test test/widgets/inventory_thumb_test.dart

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myhanout/theme.dart';
import 'package:myhanout/widgets/inventory_thumb.dart';
import 'package:myhanout/widgets/stock_badge.dart';

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The real face: the harness fallback font inflates every text measurement.
  final loader = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/Inter-400.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Inter-500.ttf'));
  await loader.load();

  const name = 'Tabasco Habaneros hot';
  // A 1x1 opaque PNG, enough to exercise the photo branch.
  final photo = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x62, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  // Device logical width: 1080px at 420dpi.
  const rowWidth = 411.0;

  Future<double> titleWidth(WidgetTester tester, {required bool withPhoto}) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
        path: 'assets/lang',
        fallbackLocale: const Locale('fr'),
        startLocale: const Locale('fr'),
        child: Builder(
          builder: (context) => MaterialApp(
            theme: AppPalette.theme(fontFamily: 'Inter'),
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: rowWidth,
                  child: ListTile(
                    leading: InventoryThumb(photo: withPhoto ? photo : null),
                    title: const Text(name),
                    // Mirrors the row: the badge sits on the subtitle line, so
                    // it cannot take width from the name.
                    subtitle: const Row(
                      children: [
                        Flexible(child: Text('12,50 MAD  •  Stock: 10')),
                        SizedBox(width: 8),
                        StockBadge(isOutOfStock: false, isLowStock: false),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.renderObject<RenderBox>(find.text(name)).size.width;
  }

  testWidgets('the name keeps the same width with and without a photo',
      (tester) async {
    final withPhoto = await titleWidth(tester, withPhoto: true);
    final withoutPhoto = await titleWidth(tester, withPhoto: false);

    // The slot itself is the invariant: 44x44 either way.
    expect(
      tester.renderObject<RenderBox>(find.byType(InventoryThumb)).size,
      const Size(44, 44),
    );

    expect(withoutPhoto, withPhoto,
        reason: 'a photo-less row must not narrow the product name '
            '(was 311px vs 53px)');
    expect(withoutPhoto, greaterThan(200),
        reason: 'the name must have room to render on one line');
  });
}
