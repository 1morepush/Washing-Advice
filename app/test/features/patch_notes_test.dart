/// The release notes on the settings screen.
///
/// Half of what is checked here is the *list*, not the widget. Notes are
/// hand-maintained prose in a Dart file, so the realistic failures are editing
/// mistakes — an entry appended to the bottom out of habit, a release added
/// with no bullets under it — and those are silent: the screen still renders,
/// it just shows the wrong thing or nothing at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/features/settings/patch_notes.dart';

void main() {
  group('the notes themselves', () {
    test('are newest first', () {
      // The screen shows `patchNotes.first` and folds the rest away, so an
      // entry added to the end would be filed under "Earlier changes" while
      // last month's news sat at the top.
      final dates = patchNotes.map((r) => r.date).toList();
      final sorted = [...dates]..sort((a, b) => b.compareTo(a));

      expect(dates, sorted);
    });

    test('every entry says something', () {
      for (final release in patchNotes) {
        expect(release.headline, isNotEmpty, reason: '${release.date}');
        expect(release.changes, isNotEmpty, reason: release.headline);
      }
    });

    test('a date reads as a date a person would write', () {
      expect(
        Release(
          date: DateTime.utc(2026, 8, 11),
          headline: 'x',
          changes: const ['y'],
        ).formattedDate,
        '11 August 2026',
      );
    });
  });

  group('on screen', () {
    Future<void> pump(WidgetTester tester) => tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: PatchNotes())),
      ),
    );

    testWidgets('the newest release is shown without opening anything', (
      tester,
    ) async {
      await pump(tester);

      final latest = patchNotes.first;
      expect(find.text(latest.headline), findsOneWidget);
      expect(find.text(latest.formattedDate), findsOneWidget);
      expect(find.text(latest.changes.first), findsOneWidget);
    });

    testWidgets('older releases are there but folded away', (tester) async {
      // Both halves matter: a wall of every change ever made is not what
      // someone opening Settings wants, and history that cannot be reached at
      // all may as well not be shipped.
      await pump(tester);

      final earlier = patchNotes[1];
      expect(find.text(earlier.headline), findsNothing);

      await tester.tap(find.text('Earlier changes'));
      await tester.pumpAndSettle();

      expect(find.text(earlier.headline), findsOneWidget);
      expect(find.text(earlier.changes.first), findsOneWidget);
    });

    testWidgets('it says why the newest date is the version you have', (
      tester,
    ) async {
      // The one sentence that makes this useful beside the update button: if
      // the date looks old, the update has not arrived, and the button is the
      // fix.
      await pump(tester);

      expect(find.textContaining('come with the app'), findsOneWidget);
    });
  });
}
