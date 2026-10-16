/// The shared Rinse pieces: they build in all three modes, at a narrow width
/// and at large text, and take their colours from the theme.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/widgets/notice.dart';
import 'package:washing_advice/widgets/rinse_kit.dart';

void main() {
  final themes = {
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
    'amoled': AppTheme.amoled(),
  };

  Widget host(ThemeData theme, Widget child, {double textScale = 1}) =>
      MaterialApp(
        theme: theme,
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: SingleChildScrollView(child: child),
          ),
        ),
      );

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('the kit lays out in $name at ${scale}x text', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(
            theme,
            Column(
              children: [
                const SectionLabel('Washing and drying'),
                GroupCard(
                  title: 'Appearance',
                  children: const [
                    ListTile(title: Text('Theme')),
                    ListTile(title: Text('Text size')),
                  ],
                ),
                const RinseCard(child: Text('A card')),
                const Row(
                  children: [
                    Expanded(child: IconBadge(Icons.inbox)),
                    CountBadge('×3'),
                  ],
                ),
                const Notice(icon: Icons.info_outline, text: 'A note'),
                const Notice(
                  icon: Icons.warning_amber,
                  text: 'A warning',
                  warning: true,
                ),
                Row(
                  children: [
                    for (final selected in [true, false])
                      Expanded(
                        child: StagePill(
                          label: 'Basket',
                          count: 3,
                          color: theme.extension<LaundryStageColors>()!.basket,
                          onColor: theme
                              .extension<LaundryStageColors>()!
                              .onBasket,
                          selected: selected,
                        ),
                      ),
                  ],
                ),
                const SizedBox(
                  height: 100,
                  child: GarmentWell(selected: true, child: Placeholder()),
                ),
              ],
            ),
            textScale: scale,
          ),
        );

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a selected well draws an accent ring, an idle one none', (
    tester,
  ) async {
    Future<int> rings(bool selected) async {
      await tester.pumpWidget(
        host(
          AppTheme.light(),
          SizedBox(
            height: 80,
            child: GarmentWell(selected: selected, child: const SizedBox()),
          ),
        ),
      );
      return find
          .descendant(
            of: find.byType(GarmentWell),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is DecoratedBox &&
                  (w.decoration as BoxDecoration).border != null,
            ),
          )
          .evaluate()
          .length;
    }

    expect(await rings(true), 1);
    expect(await rings(false), 0);
  });

  testWidgets('a group puts a hairline between its rows and not above the '
      'first when it has no title', (tester) async {
    await tester.pumpWidget(
      host(
        AppTheme.light(),
        const GroupCard(children: [Text('a'), Text('b'), Text('c')]),
      ),
    );

    expect(find.byType(Divider), findsNWidgets(2));
  });

  testWidgets('the selected stage is filled with its colour', (tester) async {
    final stages = AppTheme.light().extension<LaundryStageColors>()!;
    await tester.pumpWidget(
      host(
        AppTheme.light(),
        StagePill(
          label: 'Drying',
          color: stages.dry,
          onColor: stages.onDry,
          selected: true,
        ),
      ),
    );

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(StagePill),
        matching: find.byType(Material),
      ),
    );
    expect(material.color, stages.dry);
  });

  testWidgets('a warning notice is amber, a plain one is neutral', (
    tester,
  ) async {
    final theme = AppTheme.light();
    Color? panel() => tester
        .widget<Container>(
          find.descendant(
            of: find.byType(NoticePanel),
            matching: find.byType(Container),
          ),
        )
        .decoration
        ?.let((d) => (d as BoxDecoration).color);

    await tester.pumpWidget(
      host(theme, const Notice(icon: Icons.info, text: 'x', warning: true)),
    );
    expect(panel(), theme.colorScheme.tertiaryContainer);

    await tester.pumpWidget(
      host(theme, const Notice(icon: Icons.info, text: 'x')),
    );
    expect(panel(), theme.colorScheme.surfaceContainerHighest);
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
