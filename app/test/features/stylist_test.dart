/// Asking a model what goes with what.
///
/// This is the one flow where a model's opinion is the thing being asked for,
/// so the tests are not about whether the outfits are good — that is the part
/// being delegated, and second-guessing it in code would defeat the point.
/// They are about the facts underneath the opinion: every garment shown must
/// be one the user owns and could actually put on this morning, and the
/// reasoning must reach the screen in the model's own words rather than be
/// summarised into something that reads as the app's own judgement.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/outfits/outfits_screen.dart';

import '../support/fixtures.dart';

/// A gateway whose stylist answers with whatever the test decided.
class _Stylist extends AiGateway {
  _Stylist({this.proposals, this.fails = false})
    : super(baseUrl: Uri.parse('http://test.invalid/'));

  final List<StyleProposal>? proposals;
  final bool fails;

  /// The ids the wardrobe was described with, so a test can check what the
  /// model was offered rather than only what it sent back.
  List<String> offered = const [];
  String? sentOccasion;
  String? sentNote;

  @override
  Future<List<StyleProposal>> proposeOutfits({
    required List<WardrobeItem> wardrobe,
    required String occasion,
    String? season,
    int count = 4,
    String? note,
  }) async {
    if (fails) throw const ScanFailure('The server is having a moment.');

    offered = [for (final item in wardrobe) item.id.value];
    sentOccasion = occasion;
    sentNote = note;

    return proposals ??
        [
          const StyleProposal(
            itemIds: [ItemId('shirt'), ItemId('chinos')],
            rationale:
                'The stone chinos soften the oxford into something weekday.',
          ),
        ];
  }
}

void main() {
  late InMemoryWardrobeRepository repository;
  late InMemoryOutfitRepository outfits;
  late InMemoryEventLog events;
  late _Stylist stylist;

  setUp(() {
    repository = InMemoryWardrobeRepository();
    outfits = InMemoryOutfitRepository();
    events = InMemoryEventLog();
    stylist = _Stylist();
  });

  Future<void> seed({
    LifecycleState shirt = LifecycleState.active,
    LifecycleState chinos = LifecycleState.active,
  }) async {
    await repository.save(
      confidentItem(
        id: 'shirt',
        name: 'Oxford shirt',
        type: ItemType.dressShirt,
        lifecycle: shirt,
      ),
    );
    await repository.save(
      confidentItem(
        id: 'chinos',
        name: 'Stone chinos',
        type: ItemType.chinos,
        lifecycle: chinos,
      ),
    );
    // A third garment so putting one in the wash still leaves two to offer.
    // Without it the "too thin to dress anybody" guard fires first and the
    // test would be checking that instead of what it says it checks.
    await repository.save(
      confidentItem(
        id: 'shoes',
        name: 'White sneakers',
        type: ItemType.sneakers,
      ),
    );
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeRepositoryProvider.overrideWithValue(repository),
          outfitRepositoryProvider.overrideWithValue(outfits),
          imageStoreProvider.overrideWithValue(MemoryImageStore()),
          eventLogProvider.overrideWithValue(events),
          idGeneratorProvider.overrideWithValue(
            SequentialIdGenerator(prefix: 'ev'),
          ),
          aiGatewayProvider.overrideWithValue(stylist),
        ],
        child: const MaterialApp(
          home: OutfitsScreen(initialTab: OutfitsTab.stylist),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ask(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Ask for ideas'));
    await tester.pumpAndSettle();
  }

  testWidgets('nothing is asked for until somebody asks', (tester) async {
    // A paid call over a network. A tab that fired one on every rebuild would
    // be spending the user's money to answer a question they had not put.
    await seed();
    await pump(tester);

    expect(stylist.offered, isEmpty);
    expect(find.text('Ask for ideas'), findsWidgets);
  });

  testWidgets('an idea arrives with the reason the model gave', (tester) async {
    // The whole point of asking. A suggestion that hid its reasoning would be
    // asking to be obeyed rather than considered.
    await seed();
    await pump(tester);
    await ask(tester);

    expect(find.text('Oxford shirt'), findsOneWidget);
    expect(
      find.text('The stone chinos soften the oxford into something weekday.'),
      findsOneWidget,
    );
  });

  testWidgets('a garment that does not exist never reaches the screen', (
    tester,
  ) async {
    // A model returning a plausible id it invented would otherwise put a
    // garment on screen that cannot be opened.
    stylist = _Stylist(
      proposals: [
        const StyleProposal(
          itemIds: [ItemId('shirt'), ItemId('imaginary-belt')],
          rationale: 'A belt I made up.',
        ),
      ],
    );
    await seed();
    await pump(tester);
    await ask(tester);

    expect(find.text('A belt I made up.'), findsNothing);
    expect(find.textContaining('not in your wardrobe'), findsOneWidget);
  });

  testWidgets('and neither does the shirt that is in the machine', (
    tester,
  ) async {
    // The one failure that would make the whole feature look broken: being
    // told to wear something going round in the drum.
    await seed(shirt: LifecycleState.beingWashed);
    stylist = _Stylist(
      proposals: [
        const StyleProposal(
          itemIds: [ItemId('shirt'), ItemId('chinos')],
          rationale: 'The one in the wash.',
        ),
      ],
    );
    await pump(tester);
    await ask(tester);

    expect(find.text('The one in the wash.'), findsNothing);
    expect(find.textContaining('not available to wear'), findsOneWidget);
  });

  testWidgets('what is in the wash is not offered in the first place', (
    tester,
  ) async {
    // Refusing it afterwards is the backstop for a garment that reaches the
    // basket mid-request. Sending it up in the first place spends a call to
    // throw the answer away.
    await seed(shirt: LifecycleState.beingWashed);
    await pump(tester);
    await ask(tester);

    expect(stylist.offered, ['chinos', 'shoes']);
  });

  testWidgets('a wardrobe too thin to dress anybody says so without asking', (
    tester,
  ) async {
    await repository.save(confidentItem(id: 'shirt', name: 'Oxford shirt'));
    await pump(tester);
    await ask(tester);

    expect(stylist.offered, isEmpty);
    expect(find.textContaining('not enough in your wardrobe'), findsOneWidget);
  });

  testWidgets('the occasion from the other tab is what gets asked about', (
    tester,
  ) async {
    await seed();
    await pump(tester);
    await ask(tester);

    expect(stylist.sentOccasion, Occasion.everyday.label);
  });

  testWidgets('a note is passed on in the words it was typed in', (
    tester,
  ) async {
    await seed();
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'it will be cold');
    await ask(tester);

    expect(stylist.sentNote, 'it will be cold');
  });

  testWidgets('a failure offers another go rather than a dead end', (
    tester,
  ) async {
    stylist = _Stylist(fails: true);
    await seed();
    await pump(tester);
    await ask(tester);

    expect(find.text('Could not ask for ideas'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('an idea can be worn, and that teaches the other tab', (
    tester,
  ) async {
    // The loop that makes taking the model's advice improve the arithmetic on
    // the Suggested tab: a pairing that gets worn is a pairing the co-wear
    // graph then knows about.
    await seed();
    await pump(tester);
    await ask(tester);

    await tester.tap(find.text('Wearing this'));
    await tester.pumpAndSettle();

    final logged = await events.all();
    expect(logged.map((e) => e.itemId.value), containsAll(['shirt', 'chinos']));
  });

  testWidgets('and saved, after which it is an outfit like any other', (
    tester,
  ) async {
    await seed();
    await pump(tester);
    await ask(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Saved as'), findsOneWidget);
  });
}
