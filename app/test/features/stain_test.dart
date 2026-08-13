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
  _Adviser({this.steps, this.fails = false})
    : super(baseUrl: Uri.parse('http://test.invalid/'));

  final List<TreatmentStep>? steps;
  final bool fails;

  /// What the request carried, so the test can check the garment was described.
  String? sentFabric;
  String? sentCare;

  @override
  Future<StainAdvice> adviseOnStain({
    required String substance,
    required String fabric,
    required String care,
    String? color,
    String? note,
    ScanImage? photo,
  }) async {
    if (fails) throw const ScanFailure('The server is having a moment.');
    sentFabric = fabric;
    sentCare = care;
    return StainAdvice(steps: steps ?? _proposed, identifiedAs: 'red wine');
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

  testWidgets('the item screen offers it', (tester) async {
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

    expect(find.byTooltip('Treat a stain'), findsOneWidget);
  });
}
