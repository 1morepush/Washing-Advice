/// "Check for updates", driven through the real [UpdateSection] widget.
///
/// [forceAppUpdate] itself talks to a service worker and Cache Storage that
/// only exist in a browser — `flutter test` runs on the VM, where the
/// conditional export resolves to the no-op stub, so what is actually under
/// test here is that a tap reaches it and leaves the button usable again,
/// not the browser-side clearing (there is nothing here to prove that
/// against).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/features/settings/update_section.dart';

void main() {
  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: UpdateSection())),
  );

  testWidgets('shows the explanation and a button', (tester) async {
    await pump(tester);

    expect(find.text('App updates'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
  });

  testWidgets('tapping it runs to completion and stays usable', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
