/// The screens under a garment, reached for one that has been deleted.
///
/// A deleted garment stays stored as a tombstone so the deletion can sync.
/// The detail screen already says "no longer exists"; these are the screens
/// a deep link can reach beneath it. They used to find the tombstone, carry
/// on, and write a care label or a stain onto a row nobody can see.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/features/scan/care_tag_controller.dart';
import 'package:washing_advice/features/stains/stain_controller.dart';

import '../support/fixtures.dart';

void main() {
  const id = ItemId('gone');
  late InMemoryWardrobeRepository repository;
  late ProviderContainer container;

  setUp(() async {
    repository = InMemoryWardrobeRepository();
    await repository.save(
      confidentItem(
        id: 'gone',
        name: 'Deleted jumper',
        lifecycle: LifecycleState.removed,
      ),
    );
    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
      ],
    );
    addTearDown(container.dispose);
  });

  test('stain advice is not offered for it', () async {
    await container
        .read(stainControllerProvider(id).notifier)
        .advise(substance: 'red wine');

    expect(container.read(stainControllerProvider(id)), isA<StainFailed>());
  });

  test('a care label is not read onto it', () async {
    await container.read(careTagControllerProvider(id).notifier).readImages(
      const [
        ScanImage(bytes: [1, 2, 3]),
      ],
    );

    expect(container.read(careTagControllerProvider(id)), isA<CareTagFailed>());
  });

  test('and the detail screen sees nothing', () async {
    expect(await container.read(itemProvider(id).future), isNull);
  });
}
