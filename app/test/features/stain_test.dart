/// Asking how to get a stain out.
///
/// The assertion that matters is the negative one: what the server proposed
/// must not be what the screen shows. Everything in this flow is acted on
/// directly — somebody follows these steps with the garment in their hands —
/// so a step that slipped past the vetting is not a display bug, it is a
/// ruined jumper.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/router.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/api/stain_dto.dart';
import 'package:washing_advice/features/stains/stain_controller.dart';

import '../support/fixtures.dart';

const _wool = ItemId('jumper');
const _tee = ItemId('tee');

/// What a model really answers for a stubborn mark: hot, and bleached.
final _proposed = [
  const TreatmentStep(
    instruction: 'Blot it with a clean cloth.',
    abrades: true,
  ),
  const TreatmentStep(
    instruction: 'Soak in hot water with household bleach.',
    temperatureC: 60,
    bleach: BleachUse.chlorine,
  ),
  const TreatmentStep(instruction: 'Wash as normal.', isMachineWash: true),
];

class _Adviser extends AiGateway {
  _Adviser({this.steps, this.fails = false, this.stopsAfter, this.breaksWith})
    : super(baseUrl: Uri.parse('http://test.invalid/'));

  final List<TreatmentStep>? steps;
  final bool fails;

  /// Ends the stream after this many steps, with no `done` — a dropped
  /// connection partway through a treatment.
  final int? stopsAfter;

  /// Sends an in-band error after the steps, the way the server reports a
  /// provider that gave up once the response had already started.
  final String? breaksWith;

  /// What the request carried, so the test can check the garment was described.
  String? sentFabric;
  String? sentCare;

  @override
  Stream<StainStreamEvent> streamStainAdvice({
    required String substance,
    required String fabric,
    required String care,
    String? color,
    String? note,
    ScanImage? photo,
  }) async* {
    if (fails) throw const ScanFailure('The server is having a moment.');
    sentFabric = fabric;
    sentCare = care;

    yield const StainIdentified('red wine');
    final all = steps ?? _proposed;
    for (final step in all.take(stopsAfter ?? all.length)) {
      yield StainStep(step);
    }

    if (breaksWith case final String message) {
      yield StainStreamError(message);
      return;
    }
    if (stopsAfter != null) return; // The connection went, mid-treatment.
    yield const StainDone();
  }
}

void main() {
  late InMemoryWardrobeRepository repository;
  late InMemoryEventLog log;

  /// A hand-wash wool jumper that must not be bleached: the garment every
  /// refusal in the core is written for.
  Future<void> seedWool() => repository.save(
    confidentItem(id: _wool.value, name: 'Charcoal merino jumper').copyWith(
      composition: Confident.fromUser(
        FabricComposition(const {Fiber.wool: 100}),
      ),
      care: const CareProfile(
        instructions: CareInstructions(
          wash: WashCare(method: WashMethod.hand, maxTempC: 30),
          bleach: BleachAllowance.none,
          dry: DryCare.unknown(),
          iron: IronCare.unknown(),
          professional: ProfessionalCare.unspecified(),
        ),
        source: Provenance.tagScan,
        confidence: 0.95,
      ),
    ),
  );

  Future<void> seedCotton() => repository.save(
    confidentItem(id: _tee.value, name: 'White cotton tee').copyWith(
      composition: Confident.fromUser(
        FabricComposition(const {Fiber.cotton: 100}),
      ),
      care: const CareProfile(
        instructions: CareInstructions(
          wash: WashCare(method: WashMethod.machine, maxTempC: 60),
          bleach: BleachAllowance.any,
          dry: DryCare.unknown(),
          iron: IronCare.unknown(),
          professional: ProfessionalCare.unspecified(),
        ),
        source: Provenance.tagScan,
        confidence: 0.95,
      ),
    ),
  );

  ProviderContainer build(AiGateway gateway) {
    final container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(log),
        aiGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    repository = InMemoryWardrobeRepository();
    log = InMemoryEventLog();
  });

  test('unsafe advice never reaches the screen', () async {
    // The whole feature in one assertion. The server proposed a 60°C chlorine
    // soak and a machine wash; this jumper is hand-wash, 30°C, do not bleach.
    await seedWool();
    final container = build(_Adviser());

    await container
        .read(stainControllerProvider(_wool).notifier)
        .advise(substance: 'red wine');

    final state =
        container.read(stainControllerProvider(_wool)) as StainAdvised;
    expect(state.plan.steps.map((s) => s.instruction), [
      'Blot it with a clean cloth.',
    ]);
    expect(state.plan.refused, hasLength(2));
  });

  test('what was refused is kept, so the screen can say why', () async {
    await seedWool();
    final container = build(_Adviser());

    await container
        .read(stainControllerProvider(_wool).notifier)
        .advise(substance: 'red wine');

    final state =
        container.read(stainControllerProvider(_wool)) as StainAdvised;
    expect(
      state.plan.refused.map((r) => r.reason).join(' '),
      contains('dissolves wool'),
    );
  });

  test('a garment that can take it keeps the whole treatment', () async {
    // The other half. A flow that refused everything would be safe and
    // useless, and this is the check that would catch it.
    await seedCotton();
    final container = build(_Adviser());

    await container
        .read(stainControllerProvider(_tee).notifier)
        .advise(substance: 'red wine');

    final state = container.read(stainControllerProvider(_tee)) as StainAdvised;
    expect(state.plan.steps, hasLength(3));
    expect(state.plan.refused, isEmpty);
  });

  test('the garment is described to the server', () async {
    // Without the fabric and the care summary the model is answering about a
    // garment in general, and the advice is worth very little.
    await seedWool();
    final gateway = _Adviser();

    await build(gateway)
        .read(stainControllerProvider(_wool).notifier)
        .advise(substance: 'red wine');

    expect(gateway.sentFabric, contains('Wool'));
    expect(gateway.sentCare, contains('Do not bleach'));
  });

  test(
    'a treatment with nothing safe left is an answer, not an error',
    () async {
      await seedWool();
      final container = build(
        _Adviser(
          steps: [
            const TreatmentStep(
              instruction: 'Soak in bleach.',
              bleach: BleachUse.chlorine,
            ),
          ],
        ),
      );

      await container
          .read(stainControllerProvider(_wool).notifier)
          .advise(substance: 'ink');

      final state =
          container.read(stainControllerProvider(_wool)) as StainAdvised;
      expect(state.plan.isEmpty, isTrue);
    },
  );

  test('a server that cannot answer is a failure, not a hang', () async {
    await seedWool();
    final container = build(_Adviser(fails: true));

    await container
        .read(stainControllerProvider(_wool).notifier)
        .advise(substance: 'red wine');

    expect(container.read(stainControllerProvider(_wool)), isA<StainFailed>());
  });

  test('an item deleted mid-flow is said so, not retried forever', () async {
    final container = build(_Adviser());

    await container
        .read(stainControllerProvider(const ItemId('gone')).notifier)
        .advise(substance: 'red wine');

    final state =
        container.read(stainControllerProvider(const ItemId('gone')))
            as StainFailed;
    expect(state.isRetryable, isFalse);
  });

  test('an empty description asks for nothing', () async {
    // The button is disabled for this, but a stray submit must not spend a
    // request asking the model about "".
    await seedWool();
    final gateway = _Adviser();

    await build(
      gateway,
    ).read(stainControllerProvider(_wool).notifier).advise(substance: '   ');

    expect(gateway.sentFabric, isNull);
  });

  test('recording a treatment puts it in the garment history', () async {
    await seedWool();
    final container = build(_Adviser());

    await container
        .read(stainControllerProvider(_wool).notifier)
        .record('red wine');

    final observed = (await log.all()).whereType<ConditionObserved>().single;
    expect(observed.observation.type, WearType.stain);
    expect(observed.observation.note, contains('red wine'));
  });

  test('and reaches the wash plan, not just the history', () async {
    // The link most likely to go missing. Appending the event alone would look
    // right in the history and leave the load card silent, so the garment goes
    // in the dryer and whatever did not come out is set for good.
    await seedWool();
    final container = build(_Adviser());

    await container
        .read(stainControllerProvider(_wool).notifier)
        .record('red wine');

    final item = (await repository.byId(_wool))!;
    expect(item.hasStainAwaitingAWash, isTrue);
    expect(
      const LaundrySorter()
          .sort([item])
          .loads
          .single
          .rationaleOf(RationaleKind.handling)
          .map((r) => r.reason)
          .join(' '),
      contains('near heat'),
    );
  });

  testWidgets('the item screen offers it in words, not as an icon', (
    tester,
  ) async {
    // It was a bare brush glyph in an app bar carrying five of them, and the
    // first person to use it could not find it. A tooltip is not an
    // affordance — nobody hovers a phone.
    await seedWool();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wardrobeRepositoryProvider.overrideWithValue(repository),
          eventLogProvider.overrideWithValue(log),
        ],
        child: MaterialApp.router(
          routerConfig: buildRouter(initialLocation: '/item/${_wool.value}'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spilled something?'), findsOneWidget);
  });

  group('the advice arrives a step at a time', () {
    /// Every state the controller published, in order.
    ///
    /// The point of streaming is what the user sees *before* the end, so a
    /// test that only inspected the final state would pass just as happily
    /// against the old blocking call.
    List<StainState> record(ProviderContainer container) {
      final seen = <StainState>[];
      container.listen(
        stainControllerProvider(_tee),
        (_, next) => seen.add(next),
        fireImmediately: true,
      );
      return seen;
    }

    test('steps are shown before the treatment is finished', () async {
      await seedCotton();
      final container = build(_Adviser());
      final seen = record(container);

      await container
          .read(stainControllerProvider(_tee).notifier)
          .advise(substance: 'red wine');

      // Advised, with some but not all of the steps, and not yet complete.
      final partial = seen.whereType<StainAdvised>().firstWhere(
        (state) => !state.isComplete,
      );
      expect(partial.plan.steps, isNotEmpty);
      expect(partial.plan.steps.length, lessThan(_proposed.length));
    });

    test('and the count only ever grows', () async {
      // A step already on screen is one the user may have started. Re-ordering
      // or dropping one underneath them is not a rendering glitch here.
      await seedCotton();
      final container = build(_Adviser());
      final seen = record(container);

      await container
          .read(stainControllerProvider(_tee).notifier)
          .advise(substance: 'red wine');

      final counts = [
        for (final state in seen.whereType<StainAdvised>())
          state.plan.steps.length,
      ];
      expect(counts, orderedEquals(List.of(counts)..sort()));
    });

    test('an unsafe step is refused as it lands, not at the end', () async {
      // The vetting cannot be deferred to the close: a step shown now is a
      // step someone can act on now. This wool jumper must never see the
      // chlorine soak, at any point in the stream.
      await seedWool();
      final container = build(_Adviser());
      final seen = record(container);

      await container
          .read(stainControllerProvider(_wool).notifier)
          .advise(substance: 'red wine');

      for (final state in seen.whereType<StainAdvised>()) {
        expect(
          state.plan.steps.where((step) => step.bleach != null),
          isEmpty,
          reason: 'a bleach step was visible mid-stream',
        );
      }
    });

    test('the finished plan matches the one-shot answer exactly', () async {
      // Streaming is a delivery detail. If it produced a different treatment
      // from the same steps it would be a second opinion, and the cautions —
      // which depend on which steps were kept — are the part most likely to
      // drift.
      await seedWool();
      final container = build(_Adviser());

      await container
          .read(stainControllerProvider(_wool).notifier)
          .advise(substance: 'red wine');

      final streamed =
          container.read(stainControllerProvider(_wool)) as StainAdvised;
      final atOnce = const StainSafety().vet(
        _proposed,
        item: (await repository.byId(_wool))!,
      );

      expect(
        streamed.plan.steps.map((s) => s.instruction),
        atOnce.steps.map((s) => s.instruction),
      );
      expect(
        streamed.plan.refused.map((r) => r.reason),
        atOnce.refused.map((r) => r.reason),
      );
      expect(streamed.plan.cautions, atOnce.cautions);
    });

    test('a stream that stops early is not presented as finished', () async {
      // The dangerous case. A truncated treatment reads exactly like a short
      // one, and the step most often lost is the last — which is usually the
      // one about checking the mark before it goes near heat.
      await seedCotton();
      final container = build(_Adviser(stopsAfter: 1));

      await container
          .read(stainControllerProvider(_tee).notifier)
          .advise(substance: 'red wine');

      final state =
          container.read(stainControllerProvider(_tee)) as StainAdvised;
      expect(state.plan.steps, hasLength(1));
      expect(state.isComplete, isFalse);
    });

    test('a stream that stops before saying anything is a failure', () async {
      await seedCotton();
      final container = build(_Adviser(stopsAfter: 0));

      await container
          .read(stainControllerProvider(_tee).notifier)
          .advise(substance: 'red wine');

      expect(container.read(stainControllerProvider(_tee)), isA<StainFailed>());
    });

    test('an error sent mid-stream is a failure, not a short answer', () async {
      // Once the response has started the server has no status code left, so
      // it reports the problem in band. Treating that as the end of a good
      // treatment would show half of one as though it were whole.
      await seedCotton();
      final container = build(_Adviser(breaksWith: 'The model gave up.'));

      await container
          .read(stainControllerProvider(_tee).notifier)
          .advise(substance: 'red wine');

      final state = container.read(stainControllerProvider(_tee));
      expect(state, isA<StainFailed>());
      expect((state as StainFailed).message, 'The model gave up.');
    });
  });
}
