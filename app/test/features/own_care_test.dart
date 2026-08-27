/// Telling the app how a garment should be washed.
///
/// For the gap neither scanning nor inference reaches: a label worn illegible,
/// cut out because it itched, or never sewn in. The app could guess from the
/// fabric and it could read a tag; the one thing it could not do was be told.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/features/wardrobe/own_care_sheet.dart';

import '../support/fixtures.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late WardrobeRecorder recorder;

  setUp(() {
    repository = InMemoryWardrobeRepository();
    recorder = WardrobeRecorder(items: repository, events: InMemoryEventLog());
  });

  /// A garment whose care is a guess, which is when the app asks for a label.
  Future<WardrobeItem> guessed() async {
    final item = guessedItem(id: 'jumper', name: 'Charcoal jumper');
    final resolved = item.copyWith(
      care: const CareResolver().forItem(item).profile,
    );
    await repository.save(resolved);
    return resolved;
  }

  group('recording it', () {
    test('what the user says drives how the garment is washed', () async {
      final saved = await recorder.setOwnCare(
        item: await guessed(),
        care: const CareConstraint(maxTempC: 20, tumbleDryAllowed: false),
      );

      expect(saved.effectiveCare.wash.maxTempC, 20);
      expect(saved.effectiveCare.dry.tumbleDryAllowed, isFalse);
      expect(saved.care.source, Provenance.userEdited);
    });

    test(
      'the care stored on the item matches what it was derived from',
      () async {
        // The failure that damages clothes: a row whose `care` disagrees with
        // the facts it came from. Writing and re-deriving are one step for
        // exactly this reason.
        final saved = await recorder.setOwnCare(
          item: await guessed(),
          care: const CareConstraint(maxTempC: 20),
        );

        final read = await repository.byId(saved.id);
        expect(read!.care.instructions.wash.maxTempC, 20);
        expect(read.care.source, Provenance.userEdited);
      },
    );

    test('it stops asking for a label once it has been told', () async {
      // The prompt exists because the belief is weak, and being told is
      // exactly what makes it strong. Continuing to nag would be the app
      // ignoring an answer it asked for.
      final told = await recorder.setOwnCare(
        item: await guessed(),
        care: const CareConstraint(maxTempC: 20),
      );

      expect(told.needsCareTagScan, isFalse);
      expect(told.care.shouldPromptForTagScan, isFalse);
    });

    test('clearing it hands the garment back to the rule table', () async {
      final told = await recorder.setOwnCare(
        item: await guessed(),
        care: const CareConstraint(maxTempC: 20),
      );

      final cleared = await recorder.setOwnCare(
        item: told,
        care: const CareConstraint(),
      );

      expect(cleared.ownCare, isNull);
      expect(cleared.care.source, isNot(Provenance.userEdited));
    });
  });

  group('the sheet', () {
    Future<CareConstraint?> open(WidgetTester tester, WardrobeItem item) async {
      CareConstraint? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [wardrobeRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async =>
                      result = await showOwnCareSheet(context, item: item),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('nothing is asserted until something is chosen', (
      tester,
    ) async {
      // Every field has to be leavable alone, or the sheet would invite
      // somebody to invent the symbols they are unsure of.
      final item = await guessed();
      await open(tester, item);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Nothing chosen, so nothing stated — the rule table keeps the garment.
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('it says what will happen before the button is pressed', (
      tester,
    ) async {
      final item = await guessed();
      await open(tester, item);

      expect(find.textContaining('worked out from its fabric'), findsOneWidget);

      await tester.tap(find.text('30°C'));
      await tester.pumpAndSettle();

      expect(find.textContaining('instead of the label'), findsOneWidget);
    });

    testWidgets('a choice can be taken back', (tester) async {
      // Otherwise the sheet is a one-way door and a mis-tap is permanent.
      final item = await guessed();
      await open(tester, item);

      await tester.tap(find.text('30°C'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('30°C'));
      await tester.pumpAndSettle();

      expect(find.textContaining('worked out from its fabric'), findsOneWidget);
    });
  });
}
