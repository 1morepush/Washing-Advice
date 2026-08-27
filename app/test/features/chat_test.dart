/// Asking the app a question.
///
/// Two things are worth holding in place here, and neither is the answer
/// itself — that is the part being delegated, and asserting it would be this
/// file quietly re-implementing laundry advice.
///
/// The first is what goes *up*. The assistant is only as good as the wardrobe
/// it is told about, and the one field that can cost somebody a garment is
/// whether a care line was read off a label or worked out from the fabric. The
/// domain has always known the difference; this is the seam where it would be
/// easiest to drop it, and the answer would be confidently wrong in exactly
/// the way that ruins a jumper.
///
/// The second is that a failure stays visible. An answer that never arrives
/// must not leave a question sitting alone above an empty space, because the
/// next thing somebody does is assume the app is thinking and wait.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/api/chat_dto.dart';
import 'package:washing_advice/features/chat/chat_controller.dart';
import 'package:washing_advice/features/chat/chat_screen.dart';

import '../support/fixtures.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late _AskGateway gateway;
  late ProviderContainer container;

  setUp(() {
    repository = InMemoryWardrobeRepository();
    gateway = _AskGateway();
    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        aiGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
  });

  ChatController controller() =>
      container.read(chatControllerProvider.notifier);
  ChatState state() => container.read(chatControllerProvider);

  /// A garment whose care came from [source].
  Future<WardrobeItem> save(
    String id, {
    String name = 'Navy jumper',
    Provenance source = Provenance.tagScan,
  }) async {
    final base = confidentItem(id: id, name: name);
    final item = base.copyWith(
      // The instructions themselves are beside the point here; where the app
      // believes they came from is the whole subject.
      care: CareProfile(
        instructions: const CareInstructions.conservative(),
        source: source,
        confidence: 0.95,
      ),
    );
    await repository.save(item);
    return item;
  }

  group('what the question carries with it', () {
    test('the wardrobe goes up with the question', () async {
      await save('jumper');

      await controller().ask('can I tumble dry the navy jumper?');

      expect(gateway.lastWardrobe, hasLength(1));
      expect(gateway.lastQuestion, 'can I tumble dry the navy jumper?');
    });

    test('a label reading is not marked as a guess', () async {
      await save('jumper');

      await controller().ask('anything');

      expect(careIsGuess(gateway.lastWardrobe.single), isFalse);
    });

    test('a rule-table derivation is marked as a guess', () async {
      // The one that matters. `careRule` is exact and conservative and
      // outranks a photograph, which makes it the tempting one to relay as
      // fact — but it is a deduction from a fibre content that may itself have
      // been guessed off a picture.
      await save('jumper', source: Provenance.careRule);

      await controller().ask('anything');

      expect(careIsGuess(gateway.lastWardrobe.single), isTrue);
    });

    test('and so is a reading off a photograph', () async {
      await save('jumper', source: Provenance.aiInference);

      await controller().ask('anything');

      expect(careIsGuess(gateway.lastWardrobe.single), isTrue);
    });

    test('what the user typed themselves is not a guess', () async {
      await save('jumper', source: Provenance.userEdited);

      await controller().ask('anything');

      expect(careIsGuess(gateway.lastWardrobe.single), isFalse);
    });

    test('the care line matches what the item screen shows', () async {
      // Phrased once, in the helpers the item screen and the stain adviser
      // already use. A second wording here would let the assistant describe a
      // garment differently from the screen the user is looking at.
      final item = await save('jumper');

      await controller().ask('anything');

      expect(
        chatCareSummary(gateway.lastWardrobe.single),
        chatCareSummary(item),
      );
    });
  });

  group('the thread', () {
    test('a follow-up carries what came before it', () async {
      // "And the black one?" means nothing without the question above it.
      await save('jumper');
      await controller().ask('first');
      await controller().ask('second');

      expect(gateway.lastHistory, hasLength(2));
      expect(gateway.lastHistory.first.text, 'first');
      expect(gateway.lastHistory.first.fromUser, isTrue);
      expect(gateway.lastHistory.last.fromUser, isFalse);
    });

    test('the first question carries none', () async {
      await controller().ask('first');

      expect(gateway.lastHistory, isEmpty);
    });

    test('a failed turn is not replayed as something the app said', () async {
      // Otherwise the model is handed "could not reach the server" as its own
      // words and apologises for an outage it knows nothing about.
      gateway.failNext = true;
      await controller().ask('first');
      gateway.failNext = false;
      await controller().ask('second');

      expect(gateway.lastHistory.map((t) => t.text), ['first']);
    });

    test('clearing throws the thread away', () async {
      await controller().ask('first');
      controller().clear();

      expect(state().isEmpty, isTrue);
    });
  });

  group('when the answer does not come', () {
    test('the failure is kept in the transcript', () async {
      // Not a snackbar. A question left with nothing under it reads as the app
      // still thinking, and the user waits.
      gateway.failNext = true;

      await controller().ask('anything');

      expect(state().messages, hasLength(2));
      expect(state().messages.last.failed, isTrue);
      expect(state().messages.last.fromUser, isFalse);
    });

    test('and the question stays asked', () async {
      gateway.failNext = true;

      await controller().ask('why is my shirt pink');

      expect(state().messages.first.text, 'why is my shirt pink');
    });

    test('the conversation carries on afterwards', () async {
      gateway.failNext = true;
      await controller().ask('first');
      gateway.failNext = false;

      await controller().ask('second');

      expect(state().messages.last.failed, isFalse);
    });
  });

  group('asking', () {
    test('an empty question is not sent', () async {
      await controller().ask('   ');

      expect(gateway.calls, 0);
      expect(state().isEmpty, isTrue);
    });

    test('a question is trimmed before it is sent', () async {
      await controller().ask('  how much detergent?  ');

      expect(gateway.lastQuestion, 'how much detergent?');
    });

    test('an empty wardrobe is not an error', () async {
      // Plenty of questions are not about the user's clothes at all.
      await controller().ask('what does the triangle mean?');

      expect(state().messages.last.failed, isFalse);
    });
  });

  group('the screen', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an empty screen offers something to tap', (tester) async {
      // An empty chat box asks you to guess what it is for.
      await open(tester);

      expect(find.text('Ask about laundry'), findsOneWidget);
      expect(find.byType(ActionChip), findsWidgets);
    });

    testWidgets('tapping an opener asks it', (tester) async {
      await open(tester);

      await tester.tap(find.byType(ActionChip).first);
      await tester.pumpAndSettle();

      expect(gateway.calls, 1);
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('a question and its answer are both shown', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'how much detergent?');
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();

      expect(find.text('how much detergent?'), findsOneWidget);
      expect(find.text(_AskGateway.reply), findsOneWidget);
    });

    testWidgets('the box empties once the question is sent', (tester) async {
      // Otherwise the next question is typed onto the end of the last one.
      await open(tester);

      await tester.enterText(find.byType(TextField), 'first');
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
    });

    testWidgets('a failure is readable on screen', (tester) async {
      gateway.failNext = true;
      await open(tester);

      await tester.enterText(find.byType(TextField), 'anything');
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();

      expect(find.text('The server is asleep.'), findsOneWidget);
    });

    testWidgets('clearing is only offered once there is something to clear', (
      tester,
    ) async {
      await open(tester);
      expect(find.byIcon(Icons.delete_outline), findsNothing);

      await tester.tap(find.byType(ActionChip).first);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });
  });
}

class _AskGateway extends AiGateway {
  _AskGateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  static const reply = 'Cold wash, hang it up.';

  int calls = 0;
  bool failNext = false;

  String lastQuestion = '';
  List<WardrobeItem> lastWardrobe = const [];
  List<({bool fromUser, String text})> lastHistory = const [];

  @override
  Future<String> askQuestion({
    required String question,
    required List<WardrobeItem> wardrobe,
    List<({bool fromUser, String text})> history = const [],
  }) async {
    calls++;
    lastQuestion = question;
    lastWardrobe = wardrobe;
    lastHistory = history;

    if (failNext) throw const ScanFailure('The server is asleep.');
    return reply;
  }
}
