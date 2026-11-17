// Regression guard for the truncated inventory name.
//
// The row's `leading` used to be an intrinsically-sized stock pill when a
// product had no photo. ListTile reserves the leading's intrinsic width, so
// photo-less rows reserved 87px (French "En stock") instead of the photo's
// 44px and the name's column collapsed from 311px to 53px — the name was cut
// off, and the damage varied by locale.
//
// Run: flutter test test/widgets/inventory_thumb_test.dart

import 'dart:convert';
import 'dart:ui' as ui show TextDirection;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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

  Future<(Size, Size)> rowSizes(WidgetTester tester,
      {required bool withPhoto, String lang = 'fr'}) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('fr'), Locale('en'), Locale('ar')],
        path: 'assets/lang',
        fallbackLocale: const Locale('fr'),
        startLocale: Locale(lang),
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
                    subtitle: Row(
                      children: [
                        Flexible(
                          child: Text(
                            '12,50 MAD • ${'stockQty'.tr()}: 10',
                            key: const Key('sub'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const StockBadge(
                          isOutOfStock: false,
                          isLowStock: false,
                          showLabel: false,
                        ),
                      ],
                    ),
                    // The real row's trailing actions are 48px each; they are
                    // what squeezes the subtitle's budget.
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () {},
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert),
                          onPressed: () {},
                        ),
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
    return (
      tester.renderObject<RenderBox>(find.text(name)).size,
      tester.renderObject<RenderBox>(find.byKey(const Key('sub'))).size,
    );
  }

  testWidgets('name and subtitle keep their layout regardless of photo',
      (tester) async {
    final (withPhotoName, withPhotoSub) =
        await rowSizes(tester, withPhoto: true);
    final (noPhotoName, noPhotoSub) =
        await rowSizes(tester, withPhoto: false);

    // ignore: avoid_print
    print('GUARD name=${noPhotoName.width.toStringAsFixed(1)}'
        'x${noPhotoName.height.toStringAsFixed(1)} '
        'sub=${noPhotoSub.width.toStringAsFixed(1)}'
        'x${noPhotoSub.height.toStringAsFixed(1)}');

    // The slot itself is the invariant: 44x44 either way.
    expect(
      tester.renderObject<RenderBox>(find.byType(InventoryThumb)).size,
      const Size(44, 44),
    );

    // 1. The name must not narrow.
    expect(noPhotoName.width, withPhotoName.width,
        reason: 'a photo-less row must not narrow the product name '
            '(was 311px vs 53px)');
    expect(noPhotoName.width, greaterThan(150),
        reason: 'the name must have room to render on one line');

    // 2. The subtitle must stay on one line, and a photo must not change it.
    //    A wrapped line is taller than a single line, so height is the signal.
    expect(noPhotoSub.height, withPhotoSub.height,
        reason: 'a photo-less row must not change the subtitle layout');

    // 3. The badge is icon-only precisely so this line stops depending on the
    //    label. Resolve the row's own text style, then measure the real labels
    //    from the asset bundles: text + gap + 28px chip must fit the 199px the
    //    row leaves the subtitle.
    final paragraph =
        tester.renderObject<RenderParagraph>(find.byKey(const Key('sub')));
    final style = (paragraph.text as TextSpan).style;
    for (final lang in ['fr', 'en', 'ar']) {
      final bundle =
          jsonDecode(await rootBundle.loadString('assets/lang/$lang.json'))
              as Map<String, dynamic>;
      final label = bundle['stockQty'] as String;
      final painter = TextPainter(
        text: TextSpan(
          text: '12,50 MAD • $label: 10',
          style: style,
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final total = painter.width + 8 + 28;
      // ignore: avoid_print
      print('LOCALE $lang "$label" text=${painter.width.toStringAsFixed(1)} '
          'total=${total.toStringAsFixed(1)}');
      expect(total, lessThan(199),
          reason: '$lang subtitle ($label) needs ${total.toStringAsFixed(1)}px '
              'but the row leaves 199px');
    }
  });
}
