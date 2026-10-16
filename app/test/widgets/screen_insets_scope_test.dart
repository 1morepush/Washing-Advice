/// The scope that tells the app's own widgets about the phone's edges.
///
/// What is asserted is the thing that went wrong: where the bottom bar's labels
/// are, measured against the bottom of the screen. Asserting on the
/// `MediaQuery` alone would pass while the bar ignored it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/core/screen_insets_policy.dart';
import 'package:washing_advice/widgets/screen_insets_scope.dart';

Widget _app({
  required ScreenInsets Function() read,
  Widget? body,
  bool bar = true,
}) => MaterialApp(
  builder: (context, child) => ScreenInsetsScope(read: read, child: child!),
  home: Scaffold(
    body: body ?? const SizedBox.expand(),
    bottomNavigationBar: bar
        ? NavigationBar(
            selectedIndex: 0,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Wardrobe'),
              NavigationDestination(icon: Icon(Icons.chat), label: 'More'),
            ],
          )
        : null,
  ),
);

void main() {
  setUp(() {});

  testWidgets('the bottom bar sits clear of the screen\'s bottom edge', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(read: () => const ScreenInsets(bottom: homeIndicatorHeight)),
    );

    final label = tester.getRect(find.text('Wardrobe'));
    expect(
      852 - label.bottom,
      greaterThanOrEqualTo(homeIndicatorHeight),
      reason: 'the label must be above the home indicator',
    );

    // The bar's own background still runs to the very bottom: only what is
    // drawn on it moves.
    final bar = tester.getRect(find.byType(NavigationBar));
    expect(bar.bottom, 852);
  });

  testWidgets('with nothing to reserve the bar is exactly where it was', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(read: () => ScreenInsets.zero));
    final plain = tester.getRect(find.text('Wardrobe'));

    await tester.pumpWidget(
      _app(read: () => const ScreenInsets(bottom: homeIndicatorHeight)),
    );
    final lifted = tester.getRect(find.text('Wardrobe'));

    expect(plain.bottom - lifted.bottom, closeTo(homeIndicatorHeight, 0.5));
  });

  testWidgets('what the platform already reports is never reduced', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(bottom: 50)
      ..viewPadding = const FakeViewPadding(bottom: 50);
    addTearDown(tester.view.reset);

    late EdgeInsets seen;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ScreenInsetsScope(
          read: () => const ScreenInsets(bottom: homeIndicatorHeight),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            seen = MediaQuery.paddingOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen.bottom, 50);
  });

  testWidgets('the room is given up while the keyboard is on screen', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late EdgeInsets seen;
    Widget build() => MaterialApp(
      builder: (context, child) => ScreenInsetsScope(
        read: () => const ScreenInsets(bottom: homeIndicatorHeight),
        child: child!,
      ),
      home: Builder(
        builder: (context) {
          seen = MediaQuery.paddingOf(context);
          return const SizedBox();
        },
      ),
    );

    await tester.pumpWidget(build());
    expect(seen.bottom, homeIndicatorHeight);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpWidget(build());
    expect(seen.bottom, 0, reason: 'the keys cover the home indicator');

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpWidget(build());
    expect(seen.bottom, homeIndicatorHeight);
  });

  testWidgets('turning the phone re-reads the insets', (tester) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var insets = const ScreenInsets(bottom: homeIndicatorHeight);
    late EdgeInsets seen;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            ScreenInsetsScope(read: () => insets, child: child!),
        home: Builder(
          builder: (context) {
            seen = MediaQuery.paddingOf(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen.bottom, homeIndicatorHeight);

    insets = const ScreenInsets(bottom: 21, left: 47, right: 47);
    tester.binding.handleMetricsChanged();
    await tester.pump();
    expect(seen, const EdgeInsets.fromLTRB(47, 0, 47, 21));
  });
}
