/// One Outfits screen for both sources of ideas.
///
/// The app builds outfits by arithmetic and a model proposes them by taste. They
/// used to be separate destinations and then separate tabs; they now share the
/// Ideas tab and one occasion filter. What these pin is that sharing never costs
/// the distinction: every card says where it came from, the model's cards cannot
/// be mistaken for the arithmetic's, and one filter really does drive both.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/api/style_dto.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/outfits/outfit_source.dart';
import 'package:washing_advice/features/outfits/outfits_screen.dart';
import 'package:washing_advice/features/outfits/stylist_section.dart';

import '../support/fixtures.dart';

class _Stylist extends AiGateway {
  _Stylist({this.fails = false})
    : super(baseUrl: Uri.parse('http://test.invalid/'));

  final bool fails;
  final occasions = <String>[];

  @override
  Future<StyleAnswer> proposeOutfits({
    required List<WardrobeItem> wardrobe,
    required String occasion,
    String? season,
    int count = 4,
    String? note,
    bool suggestGaps = false,
  }) async {
    if (fails) throw const ScanFailure('The server is having a moment.');
    occasions.add(occasion);
    return (
      outfits: [
        const StyleProposal(
          itemIds: [ItemId('tee'), ItemId('jeans')],
          rationale: 'Denim keeps the tee from looking like a pyjama top.',
        ),
      ],
      pieces: const <PieceProposal>[],
    );
  }
}

void main() {
  late InMemoryWardrobeRepository repository;
  late _Stylist stylist;

  setUp(() async {
    repository = InMemoryWardrobeRepository();
    stylist = _Stylist();
    await repository.saveAll([
      confidentItem(id: 'tee', name: 'Cream tee', hex: '#F2E8D5'),
      confidentItem(id: 'jeans', name: 'Navy jeans', type: ItemType.jeans),
    ]);
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeRepositoryProvider.overrideWithValue(repository),
          outfitRepositoryProvider.overrideWithValue(
            InMemoryOutfitRepository(),
          ),
          imageStoreProvider.overrideWithValue(MemoryImageStore()),
          eventLogProvider.overrideWithValue(InMemoryEventLog()),
          idGeneratorProvider.overrideWithValue(
            SequentialIdGenerator(prefix: 'ev'),
          ),
          aiGatewayProvider.overrideWithValue(stylist),
        ],
        child: const MaterialApp(home: OutfitsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ask(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Ask for ideas'));
    await tester.pumpAndSettle();
  }

  testWidgets('has two tabs, Ideas and Saved', (tester) async {
    await pump(tester);

    expect(tester.widgetList<Tab>(find.byType(Tab)).map((t) => t.text), [
      'Ideas',
      'Saved',
    ]);
  });

  testWidgets('every wardrobe-built card is labelled as such', (tester) async {
    await pump(tester);

    final cards = find.byWidgetPredicate(
      (w) => w is OutfitCard && w.source == OutfitSource.wardrobe,
    );
    expect(cards, findsWidgets);
    for (var i = 0; i < cards.evaluate().length; i++) {
      expect(
        find.descendant(
          of: cards.at(i),
          matching: find.text('From your wardrobe'),
        ),
        findsOneWidget,
      );
    }
    expect(find.text('Stylist idea'), findsNothing);
  });

  testWidgets('every stylist card is labelled, and the two never mix', (
    tester,
  ) async {
    await pump(tester);
    await ask(tester);

    final stylistCards = find.descendant(
      of: find.byType(StylistSection),
      matching: find.byType(OutfitCard),
    );
    expect(stylistCards, findsOneWidget);
    expect(
      find.descendant(of: stylistCards, matching: find.text('Stylist idea')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: stylistCards,
        matching: find.text('From your wardrobe'),
      ),
      findsNothing,
    );
    // Not one of the arithmetic's cards carries the model's label.
    final builtCards = find.byWidgetPredicate(
      (w) => w is OutfitCard && w.source == OutfitSource.wardrobe,
    );
    expect(
      find.descendant(of: builtCards, matching: find.text('Stylist idea')),
      findsNothing,
    );
    expect(find.text('Stylist idea'), findsOneWidget);
  });

  testWidgets('the two sources are in headed sections of their own', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text(OutfitSource.wardrobe.heading), findsOneWidget);
    expect(find.text(OutfitSource.stylist.heading), findsOneWidget);
  });

  testWidgets('one occasion filter drives both sources', (tester) async {
    await pump(tester);
    // One row of occasions, not one per source.
    expect(find.widgetWithText(ChoiceChip, 'Formal'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Formal'));
    await tester.pumpAndSettle();
    // The built suggestions followed it...
    expect(find.textContaining('Nothing for formal'), findsOneWidget);

    // ...and so does the question put to the stylist.
    await ask(tester);
    expect(stylist.occasions, ['Formal']);
  });

  testWidgets('a stylist that fails leaves the built suggestions on screen', (
    tester,
  ) async {
    stylist = _Stylist(fails: true);
    await pump(tester);
    await ask(tester);

    expect(find.text('Could not ask for ideas'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('From your wardrobe'), findsWidgets);
  });
}
