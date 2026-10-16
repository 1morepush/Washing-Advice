/// The pieces the scan screens share: a photograph on its well, the badge over
/// it, and the care symbols on a review. They must lay out in all three
/// appearances, at a narrow width and at large text.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/features/scan/scan_controller.dart';
import 'package:washing_advice/features/scan/scan_parts.dart';
import 'package:washing_advice/features/scan/shot_tile.dart';
import 'package:washing_advice/widgets/care_symbol.dart';

void main() {
  final themes = {
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
    'amoled': AppTheme.amoled(),
  };

  // Not a decodable picture, which is the case the fallback is for.
  const broken = ScanImage(bytes: [1, 2, 3]);

  Widget host(ThemeData theme, Widget child, double scale) => MaterialApp(
    theme: theme,
    builder: (context, app) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: app!,
    ),
    home: Scaffold(
      body: SizedBox(width: 320, child: SingleChildScrollView(child: child)),
    ),
  );

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('scan parts lay out in $name at ${scale}x text', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            theme,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ScanHeading('3 read', body: 'Everything is ticked.'),
                const ScanThumb(image: broken, size: 60),
                const Stack(
                  children: [
                    ScanThumb(image: broken, size: 96),
                    Positioned(
                      left: 3,
                      right: 3,
                      bottom: 3,
                      child: Center(child: PhotoBadge(text: 'Label')),
                    ),
                  ],
                ),
                ShotTile(
                  shot: ScanShot(image: broken, role: PhotoRole.careTag),
                  onRole: (_) {},
                  onCrop: () {},
                ),
                const CareSymbolRow(care: CareInstructions.conservative()),
                ScanActionBar(
                  children: [
                    FilledButton(onPressed: () {}, child: const Text('Go')),
                  ],
                ),
              ],
            ),
            scale,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Label'), findsWidgets);
        expect(find.byIcon(Icons.crop), findsOneWidget);
      });
    }
  }

  testWidgets('the care symbols are drawn for what the label says', (
    tester,
  ) async {
    const care = CareInstructions.conservative();
    await tester.pumpWidget(
      host(AppTheme.light(), const CareSymbolRow(care: care), 1),
    );

    expect(find.byType(CareSymbol), findsNWidgets(careSymbolsFor(care).length));
  });

  testWidgets('a photograph that will not decode is still a tile', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(AppTheme.amoled(), const ScanThumb(image: broken, size: 60), 1),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
  });
}
