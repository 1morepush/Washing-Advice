/// The details of a listing: what is typed, picked and added, and what it does
/// to the description.
///
/// The description is the evidence. Every field here exists to end up in it or
/// beside it, so a field is tested by what the pasted text says after it has
/// been changed, and by what is stored when the person leaves — which is when
/// a debounced save would lose a word, if it were going to.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/features/sell/editor/description_section.dart';
import 'package:washing_advice/features/sell/editor/word_lists.dart';
import 'package:washing_advice/features/sell/sell_screen.dart';

import '../../support/fixtures.dart';
import 'listing_editor_harness.dart';

void main() {
  Finder field(String label) => find.widgetWithText(TextField, label);

  /// The description as it is shown now.
  String pasted(WidgetTester tester) => tester
      .widget<SelectableText>(
        find.descendant(
          of: find.byType(DescriptionSection),
          matching: find.byType(SelectableText),
        ),
      )
      .data!;

  /// The Add button of one of the two lists that have one.
  Finder addIn(Type editor) => find.descendant(
    of: find.byType(editor),
    matching: find.widgetWithText(FilledButton, 'Add'),
  );

  /// Types [text] into the box called [label], as a person does.
  Future<void> type(WidgetTester tester, String label, String text) async {
    await tester.enterText(field(label), text);
    await tester.pump();
  }

  group('the title', () {
    testWidgets('is the first line of the description, as it is typed', (
      tester,
    ) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);
      expect(pasted(tester), startsWith('Nike vintage crewneck sweatshirt'));

      await type(tester, 'Title', 'Nike 90s embroidered crewneck grey');

      expect(pasted(tester), startsWith('Nike 90s embroidered crewneck grey'));
      // Stored by the pause, with nobody leaving.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('suggests what to write, and what it is for', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(title: ''),
        size: tallScreen,
      );

      // The prompt is gentle: it is a hint in an empty box, and a line under it.
      expect(
        find.text(
          'Brand, item, style words — e.g. Nike vintage crewneck sweatshirt '
          'grey',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining("it's the first line of the description"),
        findsOneWidget,
      );
    });

    testWidgets('stops prompting once there is one', (tester) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      expect(
        find.textContaining("it's the first line of the description"),
        findsNothing,
      );
    });

    testWidgets('survives Back by the arrow of a screen opened directly', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      // Typed, and gone before the pause is up: the case a debounce loses.
      await type(tester, 'Title', 'Typed and left at once');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.byType(SellScreen), findsOneWidget);
      expect((await app.stored('draft-1'))!.title, 'Typed and left at once');
    });

    testWidgets('survives Back from a screen opened over Sell, and the system '
        'gesture', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        location: '/sell',
        size: tallScreen,
      );
      GoRouter.of(
        tester.element(find.byType(SellScreen)),
      ).push('/listing/draft-1');
      await tester.pumpAndSettle();

      await type(tester, 'Title', 'Typed, then the arrow');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(SellScreen), findsOneWidget);
      expect((await app.stored('draft-1'))!.title, 'Typed, then the arrow');

      // And the gesture, which does not go through the arrow at all.
      GoRouter.of(
        tester.element(find.byType(SellScreen)),
      ).push('/listing/draft-1');
      await tester.pumpAndSettle();
      await type(tester, 'Title', 'Typed, then the gesture');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(SellScreen), findsOneWidget);
      expect((await app.stored('draft-1'))!.title, 'Typed, then the gesture');
    });

    testWidgets('is there when the listing is opened again', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(),
        location: '/sell',
        size: tallScreen,
      );
      final router = GoRouter.of(tester.element(find.byType(SellScreen)));
      router.push('/listing/draft-1');
      await tester.pumpAndSettle();
      await type(tester, 'Title', 'Kept for next time');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      router.push('/listing/draft-1');
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(field('Title')).controller!.text,
        'Kept for next time',
      );
      expect(pasted(tester), startsWith('Kept for next time'));
    });

    testWidgets('is stored a moment after it is typed, without leaving', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await type(tester, 'Title', 'Stored by the pause');
      expect(
        (await app.stored('draft-1'))!.title,
        isNot('Stored by the pause'),
      );

      await tester.pump(const Duration(seconds: 1));

      expect((await app.stored('draft-1'))!.title, 'Stored by the pause');
    });

    testWidgets('keeps the cursor where it is while it is being stored', (
      tester,
    ) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);
      await tester.showKeyboard(field('Title'));

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Nike X vintage crewneck sweatshirt grey',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      // Past the pause, so it has been stored and the listing has come back
      // round to the box.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      final controller = tester.widget<TextField>(field('Title')).controller!;
      expect(controller.text, 'Nike X vintage crewneck sweatshirt grey');
      expect(controller.selection.baseOffset, 6);
    });

    testWidgets('typed just before a delete does not come back', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await type(tester, 'Title', 'Typed, then deleted');
      await tester.tap(find.text('Delete listing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(await app.stored('draft-1'), isNull);
    });
  });

  group('the category', () {
    testWidgets('is where the core would file it, as text to copy', (
      tester,
    ) async {
      final clipboard = ClipboardSpy(tester);
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      expect(find.text('Tops › Sweatshirts'), findsOneWidget);
      expect(
        find.textContaining("Depop's own list may word it"),
        findsOneWidget,
      );

      await tester.tap(find.text('Copy category'));
      await tester.pump();

      expect(clipboard.text, 'Tops › Sweatshirts');
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('follows the department where the department matters', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(
          itemType: ItemType.blouse,
          department: DepopDepartment.women,
        ),
        size: tallScreen,
      );
      expect(find.text('Tops › Blouses'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Men'));
      await tester.pump();

      expect(find.text('Tops › Shirts'), findsOneWidget);
      expect(find.text('Tops › Blouses'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('asks for a department only when the answer depends on it', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(itemType: ItemType.blouse, department: null),
        size: tallScreen,
      );

      expect(
        find.text('Pick Men or Women to see where Depop files this.'),
        findsOneWidget,
      );
      expect(find.text('Copy category'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Women'));
      await tester.pump();

      expect(find.text('Tops › Blouses'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('is the same for both where it does not depend on it', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(department: null),
        size: tallScreen,
      );

      expect(find.text('Tops › Sweatshirts'), findsOneWidget);
    });

    testWidgets('takes a department back when it is tapped again', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Men'));
      await tester.pump(const Duration(seconds: 1));

      expect((await app.stored('draft-1'))!.department, isNull);
    });

    testWidgets('follows the item type', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await tester.tap(find.byType(DropdownButtonFormField<ItemType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jeans').last);
      await tester.pumpAndSettle();

      expect(find.text('Bottoms › Jeans'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect((await app.stored('draft-1'))!.itemType, ItemType.jeans);
    });
  });

  group('brand, size, material, era and notes', () {
    testWidgets('go into the description as they are typed', (tester) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      await type(tester, 'Brand', 'Adidas');
      await type(tester, 'Size', 'L');
      await type(tester, 'Material', '100% cotton');
      await type(tester, 'Notes', 'Smoke-free home.');

      final text = pasted(tester);
      expect(text, contains('Brand: Adidas'));
      expect(text, contains('Size: L'));
      expect(text, contains('Material: 100% cotton'));
      expect(text, contains('Smoke-free home.'));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('are taken out of it when they are emptied', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await type(tester, 'Brand', '');
      await type(tester, 'Size', '');
      await type(tester, 'Material', '');
      await tester.pump(const Duration(seconds: 1));

      final text = pasted(tester);
      expect(text, isNot(contains('Brand:')));
      expect(text, isNot(contains('Size:')));
      expect(text, isNot(contains('Material:')));
      final stored = (await app.stored('draft-1'))!;
      expect(stored.brand, isNull);
      expect(stored.sizeLabel, isNull);
      expect(stored.material, isNull);
    });

    testWidgets('are stored as they were typed', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await type(tester, 'Era', 'Y2K');
      await type(tester, 'Notes', 'Ships Monday.');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      final stored = (await app.stored('draft-1'))!;
      expect(stored.era, 'Y2K');
      expect(stored.notes, 'Ships Monday.');
    });
  });

  group('the condition', () {
    testWidgets('is one of Depop\'s five, with what it means', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      for (final condition in DepopCondition.values) {
        expect(
          find.widgetWithText(ChoiceChip, condition.label),
          findsOneWidget,
        );
      }
      expect(
        find.text('Used - Excellent: Minimal signs of wear.'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Like new'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Like new: Worn, no signs of wear.'), findsOneWidget);
      expect(pasted(tester), contains('Condition: Like new.'));
      expect((await app.stored('draft-1'))!.condition, DepopCondition.likeNew);
    });

    testWidgets('can be taken back, and is never filled in by itself', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(condition: null, flaws: const []),
        size: tallScreen,
      );

      expect(
        find.text('Pick the one that fits. It goes in the description.'),
        findsOneWidget,
      );
      expect(pasted(tester), isNot(contains('Condition')));

      await tester.tap(find.widgetWithText(ChoiceChip, 'Used - Good'));
      await tester.pump();
      expect(pasted(tester), contains('Condition: Used - Good.'));

      await tester.tap(find.widgetWithText(ChoiceChip, 'Used - Good'));
      await tester.pump(const Duration(seconds: 1));
      expect(pasted(tester), isNot(contains('Condition')));
      expect((await app.stored('draft-1'))!.condition, isNull);
    });

    testWidgets('has all five meanings in a sheet', (tester) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      await tester.tap(find.text('What do these mean?'));
      await tester.pumpAndSettle();

      for (final condition in DepopCondition.values) {
        expect(find.text(condition.meaning), findsOneWidget);
      }
    });

    testWidgets('is suggested, with the reason, for a listing from a garment', (
      tester,
    ) async {
      final garment = confidentItem(
        id: 'sweat',
        name: 'Grey crewneck',
        type: ItemType.sweatshirt,
        usage: const UsageStats(timesWorn: 4),
      );
      await openEditor(
        tester,
        listing: sampleListing(itemId: garment.id, condition: null),
        garments: [garment],
        size: tallScreen,
      );

      expect(
        find.text(
          'Suggested: Used - Excellent — worn 4 times, no wear reported',
        ),
        findsOneWidget,
      );
      // Offered, and not applied.
      expect(pasted(tester), isNot(contains('Condition: Used - Excellent')));

      await tester.tap(find.text('Use Used - Excellent'));
      await tester.pump(const Duration(seconds: 1));

      expect(pasted(tester), contains('Condition: Used - Excellent.'));
      expect(find.text('Use Used - Excellent'), findsNothing);
    });

    testWidgets('is not suggested for a listing with no garment', (
      tester,
    ) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      expect(find.textContaining('Suggested:'), findsNothing);
    });
  });

  group('the colors', () {
    testWidgets('are picked from Depop\'s list, two at most', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(colours: const []),
        size: tallScreen,
      );

      await tester.tap(find.widgetWithText(FilterChip, 'Grey'));
      await tester.tap(find.widgetWithText(FilterChip, 'White'));
      await tester.pump();
      expect(pasted(tester), contains('Color: Grey, White'));

      await tester.tap(find.widgetWithText(FilterChip, 'Navy'));
      await tester.pump();

      // Said, and not silently ignored; and the two are still the two.
      expect(find.textContaining('Depop allows 2'), findsOneWidget);
      expect(pasted(tester), contains('Color: Grey, White'));
      expect(pasted(tester), isNot(contains('Navy')));
      await tester.pump(const Duration(seconds: 1));
      expect((await app.stored('draft-1'))!.colours, [
        DepopColour.grey,
        DepopColour.white,
      ]);
    });

    testWidgets('make room when one is taken off', (tester) async {
      await openEditor(
        tester,
        listing: sampleListing(
          colours: const [DepopColour.grey, DepopColour.white],
        ),
        size: tallScreen,
      );
      await tester.tap(find.widgetWithText(FilterChip, 'Navy'));
      await tester.pump();
      expect(find.textContaining('Depop allows 2'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'White'));
      await tester.pump();
      expect(find.textContaining('Depop allows 2'), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'Navy'));
      await tester.pump();

      expect(pasted(tester), contains('Color: Grey, Navy'));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('start as the listing has them', (tester) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Grey'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Red'))
            .selected,
        isFalse,
      );
    });
  });

  group('the style words', () {
    testWidgets('are added, as many as are typed, and become hashtags', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing().copyWith(styleWords: const []),
        size: tallScreen,
      );
      expect(pasted(tester), isNot(contains('#boxy')));

      await tester.enterText(field('Add a style word'), 'boxy, streetwear');
      await tester.tap(addIn(StyleWordsEditor));
      await tester.pump();

      expect(find.widgetWithText(InputChip, 'boxy'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'streetwear'), findsOneWidget);
      expect(pasted(tester), contains('#boxy'));
      // And the box is ready for the next.
      expect(
        tester.widget<TextField>(field('Add a style word')).controller!.text,
        isEmpty,
      );
      await tester.pump(const Duration(seconds: 1));
      expect((await app.stored('draft-1'))!.styleWords, ['boxy', 'streetwear']);
    });

    testWidgets('are not added twice', (tester) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      await tester.enterText(field('Add a style word'), 'Vintage, crewneck');
      await tester.tap(addIn(StyleWordsEditor));
      await tester.pump();

      expect(find.widgetWithText(InputChip, 'vintage'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Vintage'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('are taken off by their chip', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await tester.tap(find.byTooltip('Remove vintage'));
      await tester.pump(const Duration(seconds: 1));

      expect(find.widgetWithText(InputChip, 'vintage'), findsNothing);
      expect((await app.stored('draft-1'))!.styleWords, ['crewneck', '90s']);
    });

    testWidgets('are added from the keyboard, too', (tester) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      await tester.enterText(field('Add a style word'), 'oversized');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.widgetWithText(InputChip, 'oversized'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('ignore a box with nothing in it', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await tester.enterText(field('Add a style word'), ' , ,');
      await tester.tap(addIn(StyleWordsEditor));
      await tester.pump(const Duration(seconds: 1));

      expect((await app.stored('draft-1'))!.styleWords, hasLength(3));
    });
  });

  group('the flaws', () {
    testWidgets('are listed in the description, and added and removed', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );
      expect(find.text('small mark on the left cuff'), findsOneWidget);
      expect(pasted(tester), contains('Flaws: small mark on the left cuff'));

      await tester.enterText(
        field('Add a flaw'),
        'light pilling, mostly under the arms',
      );
      await tester.tap(addIn(FlawsEditor));
      await tester.pump();

      // One flaw, comma and all: it is a sentence, not a list of words.
      expect(find.text('light pilling, mostly under the arms'), findsOneWidget);
      expect(
        pasted(tester),
        contains(
          'Flaws: small mark on the left cuff; light pilling, mostly under '
          'the arms',
        ),
      );

      await tester.tap(
        find
            .descendant(
              of: find.byType(FlawsEditor),
              matching: find.widgetWithText(TextButton, 'Remove'),
            )
            .first,
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('small mark on the left cuff'), findsNothing);
      expect((await app.stored('draft-1'))!.flaws, [
        'light pilling, mostly under the arms',
      ]);
    });

    testWidgets('are never turned into a claim that there are none', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(flaws: const []),
        size: tallScreen,
      );

      expect(
        find.text('None listed. The description lists only what you add.'),
        findsOneWidget,
      );
      final noFlaws = RegExp('no flaws|flawless|perfect', caseSensitive: false);
      expect(pasted(tester), isNot(matches(noFlaws)));
      expect(find.textContaining(noFlaws), findsNothing);
      expect(pasted(tester), isNot(contains('Flaws')));
    });

    testWidgets('say a photograph is to be taken of each', (tester) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      expect(find.textContaining('Photograph each one'), findsOneWidget);
    });
  });

  group('the measurements', () {
    testWidgets('always ask for pit to pit and length, in inches', (
      tester,
    ) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      expect(field('Pit to pit'), findsOneWidget);
      expect(field('Length'), findsOneWidget);
      expect(
        tester.widget<TextField>(field('Pit to pit')).controller!.text,
        '22',
      );
      expect(tester.widget<TextField>(field('Length')).controller!.text, '27');
      expect(field('Waist'), findsNothing);
      expect(field('Inseam'), findsNothing);
    });

    testWidgets('add waist and inseam for something worn on the legs', (
      tester,
    ) async {
      await openEditor(
        tester,
        listing: sampleListing(
          itemType: ItemType.jeans,
          measurements: const Measurements(waistIn: 32, inseamIn: 30),
        ),
        size: tallScreen,
      );

      expect(field('Waist'), findsOneWidget);
      expect(field('Inseam'), findsOneWidget);
      expect(tester.widget<TextField>(field('Waist')).controller!.text, '32');
    });

    testWidgets('keep a waist that is already there, whatever it is', (
      tester,
    ) async {
      // It is in the description, so it is on screen to be changed.
      await openEditor(
        tester,
        listing: sampleListing(measurements: const Measurements(waistIn: 30)),
        size: tallScreen,
      );

      expect(field('Waist'), findsOneWidget);
    });

    testWidgets('appear when the item type changes to a bottom', (
      tester,
    ) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);
      expect(field('Waist'), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<ItemType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jeans').last);
      await tester.pumpAndSettle();

      expect(field('Waist'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('go into the description in inches', (tester) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      await type(tester, 'Pit to pit', '23.5');
      await type(tester, 'Length', '28');

      expect(
        pasted(tester),
        contains('Measurements: pit to pit 23.5", length 28"'),
      );
      await tester.pump(const Duration(seconds: 1));
      final stored = (await app.stored('draft-1'))!;
      expect(stored.measurements.pitToPitIn, 23.5);
      expect(stored.measurements.lengthIn, 28);
    });

    testWidgets('are taken out when the box is emptied', (tester) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      await type(tester, 'Pit to pit', '');
      await type(tester, 'Length', '');

      expect(pasted(tester), isNot(contains('Measurements')));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('ignore what is not a measurement, and do not crash', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      for (final bad in ['0', '.', '..', '1.2.3', '9999', '0.0', '301']) {
        await type(tester, 'Pit to pit', bad);
      }
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      // The last measurement that made sense is the one that stands.
      expect((await app.stored('draft-1'))!.measurements.pitToPitIn, 22);
      expect(pasted(tester), contains('pit to pit 22"'));
    });

    testWidgets('drop the marks a measurement is not written with', (
      tester,
    ) async {
      await openEditor(tester, listing: sampleListing(), size: tallScreen);

      await type(tester, 'Length', '2a8 in');

      expect(tester.widget<TextField>(field('Length')).controller!.text, '28 ');
      expect(pasted(tester), contains('length 28"'));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('are emptied by a box that is left with nothing in it', (
      tester,
    ) async {
      final app = await openEditor(
        tester,
        listing: sampleListing(),
        size: tallScreen,
      );

      // Nothing a measurement is written with: the box ends up empty, and an
      // empty box is a measurement taken back.
      await type(tester, 'Length', 'abc');
      await tester.pump(const Duration(seconds: 1));

      expect((await app.stored('draft-1'))!.measurements.lengthIn, isNull);
    });
  });
}
