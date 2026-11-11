/// Worn today, from a mirror photo.
///
/// What is worth pinning is what is *not* done silently: a confident match is
/// ticked, an uncertain one is shown and left unticked, and nothing the person
/// did not confirm reaches the event log. A garment the wardrobe does not have
/// is handed to the add flow rather than dropped.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/features/laundry/worn_today_photo_controller.dart';
import 'package:washing_advice/features/scan/worn_photo_controller.dart';

import 'support/fixtures.dart';
import 'support/worn_fakes.dart';

WardrobeItem _navyJumper(String id, {String name = 'Navy jumper'}) =>
    confidentItem(
      id: id,
      name: name,
      type: ItemType.sweater,
      hex: '#1F2A44',
      colorName: 'Navy',
    );

WardrobeItem _blackJeans() => confidentItem(
  id: 'jeans',
  name: 'Black jeans',
  type: ItemType.jeans,
  hex: '#222222',
  colorName: 'Black',
);

WornDetection _jumper() => wornDetection();
WornDetection _jeans() => wornDetection(
  type: ItemType.jeans,
  hex: '#222222',
  colour: 'Black',
  name: 'Black jeans',
  left: 0.3,
);
WornDetection _hat() => wornDetection(
  type: ItemType.hat,
  hex: '#CC8822',
  colour: 'Mustard',
  name: 'Mustard hat',
  left: 0.6,
);

void main() {
  late InMemoryWardrobeRepository repository;
  late InMemoryEventLog events;
  late WornGateway gateway;
  late ProviderContainer container;

  void setUpWith(List<Object> script, List<WardrobeItem> owned) {
    repository = InMemoryWardrobeRepository();
    events = InMemoryEventLog();
    gateway = WornGateway(script);
    for (final item in owned) {
      repository.save(item);
    }
    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(events),
        aiGatewayProvider.overrideWithValue(gateway),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'ev'),
        ),
        imageCaptureProvider.overrideWithValue(
          FixedImageCaptureSource([wornPng]),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(wornTodayPhotoControllerProvider, (_, _) {});
  }

  WornTodayPhotoController controller() =>
      container.read(wornTodayPhotoControllerProvider.notifier);
  WornTodayPhotoState state() =>
      container.read(wornTodayPhotoControllerProvider);

  group('matching what is worn', () {
    testWidgets('confident matches are ticked', (tester) async {
      setUpWith(
        [
          [_jumper(), _jeans()],
        ],
        [_navyJumper('jumper'), _blackJeans()],
      );

      await tester.runAsync(() => controller().start());

      expect(state().phase, WornPhase.result);
      expect(state().sightings.map((s) => s.certainty), [
        Certainty.sure,
        Certainty.sure,
      ]);
      expect(state().selected, {0, 1});
      expect(state().sightings.first.item?.displayName, 'Navy jumper');
    });

    testWidgets('an ambiguous match is shown and left unticked', (
      tester,
    ) async {
      // Two identical navy jumpers: the photo cannot say which.
      setUpWith(
        [
          [_jumper()],
        ],
        [
          _navyJumper('a', name: 'Navy jumper'),
          _navyJumper('b', name: 'Navy jumper 2'),
        ],
      );

      await tester.runAsync(() => controller().start());

      final s = state().sightings.single;
      expect(s.certainty, Certainty.unsure);
      expect(s.item, isNotNull, reason: 'named, so the person can decide');
      expect(state().selected, isEmpty);
    });

    testWidgets('what matches nothing is listed apart', (tester) async {
      setUpWith(
        [
          [_jumper(), _hat()],
        ],
        [_navyJumper('jumper')],
      );

      await tester.runAsync(() => controller().start());

      expect(state().matched, hasLength(1));
      expect(
        state().unmatched.single.detection.scan.suggestedName,
        'Mustard hat',
      );
      expect(state().selected, {0}, reason: 'the unknown one is not ticked');
    });

    testWidgets('a garment in the basket still counts as owned', (
      tester,
    ) async {
      setUpWith(
        [
          [_jumper()],
        ],
        [_navyJumper('jumper').copyWith(lifecycle: LifecycleState.inLaundry)],
      );

      await tester.runAsync(() => controller().start());

      expect(state().unmatched, isEmpty);
    });
  });

  group('confirming', () {
    testWidgets('records the ticked garments worn, once, together', (
      tester,
    ) async {
      setUpWith(
        [
          [_jumper(), _jeans()],
        ],
        [_navyJumper('jumper'), _blackJeans()],
      );
      await tester.runAsync(() => controller().start());

      await tester.runAsync(() => controller().confirm());

      final worn = (await events.all()).whereType<ItemWorn>().toList();
      expect({for (final e in worn) e.itemId.value}, {'jumper', 'jeans'});
      expect(
        worn.map((e) => e.occurredAt).toSet(),
        hasLength(1),
        reason: 'one outfit, one instant',
      );
      expect(state().phase, WornPhase.done);
      expect(state().saved, 2);
      final moved = await repository.byId(const ItemId('jumper'));
      expect(moved!.lifecycle, LifecycleState.inLaundry);
    });

    testWidgets('an unticked match is not recorded', (tester) async {
      setUpWith(
        [
          [_jumper(), _jeans()],
        ],
        [_navyJumper('jumper'), _blackJeans()],
      );
      await tester.runAsync(() => controller().start());
      controller().toggle(1);

      await tester.runAsync(() => controller().confirm());

      final worn = (await events.all()).whereType<ItemWorn>();
      expect(worn.map((e) => e.itemId.value), ['jumper']);
    });

    testWidgets('an uncertain match can be ticked by the person', (
      tester,
    ) async {
      setUpWith(
        [
          [_jumper()],
        ],
        [_navyJumper('a'), _navyJumper('b', name: 'Navy jumper 2')],
      );
      await tester.runAsync(() => controller().start());
      controller().toggle(0);

      await tester.runAsync(() => controller().confirm());

      expect((await events.all()).whereType<ItemWorn>(), hasLength(1));
    });

    testWidgets('nothing is recorded before they confirm', (tester) async {
      setUpWith(
        [
          [_jumper()],
        ],
        [_navyJumper('jumper')],
      );

      await tester.runAsync(() => controller().start());

      expect(await events.all(), isEmpty);
    });
  });

  group('adding what is not in the wardrobe', () {
    testWidgets('hands that garment to the add review, preselected', (
      tester,
    ) async {
      setUpWith(
        [
          [_jumper(), _hat()],
        ],
        [_navyJumper('jumper')],
      );
      await tester.runAsync(() => controller().start());

      await tester.runAsync(
        () => controller().addToWardrobe(state().unmatched.single),
      );

      final add = container.read(wornPhotoControllerProvider);
      expect(add, isA<WornReviewing>());
      final reviewing = add as WornReviewing;
      expect(reviewing.finds.single.draft.displayName, 'Mustard hat');
      expect(reviewing.accepted, hasLength(1));
      expect(gateway.calls, 1, reason: 'the photo is not scanned twice');
    });
  });

  group('when the photo does not work out', () {
    testWidgets('a failed scan says so', (tester) async {
      setUpWith(
        [const ScanFailure('Could not reach the server.')],
        [_navyJumper('jumper')],
      );

      await tester.runAsync(() => controller().start());

      expect(state().phase, WornPhase.failed);
      expect(state().message, contains('Could not reach'));
    });

    testWidgets('an empty photo says so', (tester) async {
      setUpWith([<WornDetection>[]], [_navyJumper('jumper')]);

      await tester.runAsync(() => controller().start());

      expect(state().phase, WornPhase.failed);
      expect(state().message, contains('No clothes'));
    });
  });
}
