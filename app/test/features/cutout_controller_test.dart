/// Making a cutout after the fact, and what happens when it cannot be made.
///
/// The interesting half is the failures. The button that starts this is
/// replaced by a spinner while the work runs, so a status that never leaves
/// `working` is not a stalled operation — it is a screen with nothing left to
/// press, and the only way out is to restart the app.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/images/image_store.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/wardrobe/cutout_controller.dart';

import '../support/fixtures.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late MemoryImageStore images;

  ProviderContainer build({ImageStore? store, AiGateway? gateway}) {
    final container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(store ?? images),
        aiGatewayProvider.overrideWithValue(gateway ?? _CuttingGateway()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// An item with a real photograph and no cutout yet.
  Future<ItemId> photographedItem() async {
    final uri = await images.save(
      Uint8List.fromList([1, 2, 3]),
      name: 'tee-front',
    );
    final item = confidentItem(id: 'tee', name: 'White cotton tee').copyWith(
      photos: PhotoSet([
        ItemPhoto(uri: uri, role: PhotoRole.front, capturedAt: DateTime.now()),
      ]),
    );
    await repository.save(item);
    return item.id;
  }

  setUp(() {
    repository = InMemoryWardrobeRepository();
    images = MemoryImageStore();
  });

  test('a cutout is made, stored and attached', () async {
    final container = build();
    final id = await photographedItem();

    await container.read(cutoutControllerProvider.notifier).generate(id);

    expect(container.read(cutoutControllerProvider), CutoutStatus.done);
    expect((await repository.byId(id))!.photos.displayPhoto!.hasCutout, isTrue);
  });

  test(
    'a server that cannot separate the garment is a failure, not a hang',
    () async {
      final container = build(gateway: _RefusingGateway());
      final id = await photographedItem();

      await container.read(cutoutControllerProvider.notifier).generate(id);

      expect(container.read(cutoutControllerProvider), CutoutStatus.failed);
    },
  );

  test('storage that refuses the write is a failure, not a hang', () async {
    // The realistic one: a browser origin out of quota, which fails at exactly
    // the moment an image is written. Before this was caught the status stayed
    // `working` and the screen kept a spinner where its only button had been.
    final container = build(store: _FullImageStore(images));
    final id = await photographedItem();

    await container.read(cutoutControllerProvider.notifier).generate(id);

    expect(container.read(cutoutControllerProvider), CutoutStatus.failed);
  });

  test('an item whose photograph is gone is a failure, not a hang', () async {
    final container = build();
    final item = confidentItem(id: 'bare', name: 'No photo');
    await repository.save(item);

    await container.read(cutoutControllerProvider.notifier).generate(item.id);

    expect(container.read(cutoutControllerProvider), CutoutStatus.failed);
  });
}

class _CuttingGateway extends AiGateway {
  _CuttingGateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  @override
  Future<Uint8List?> cutout(ScanImage image) async =>
      Uint8List.fromList([9, 9, 9]);
}

/// The gateway's own answer when the remover could not separate anything —
/// null rather than an exception, which is what it already does for an
/// unreachable server too.
class _RefusingGateway extends AiGateway {
  _RefusingGateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  @override
  Future<Uint8List?> cutout(ScanImage image) async => null;
}

/// Reads fine, refuses every write.
class _FullImageStore implements ImageStore {
  _FullImageStore(this._inner);

  final ImageStore _inner;

  @override
  Future<Uint8List?> read(String uri) => _inner.read(uri);

  @override
  Future<String> save(List<int> bytes, {required String name}) async =>
      throw const _QuotaExceeded();

  @override
  Future<void> delete(String uri) => _inner.delete(uri);
}

/// What a browser throws when the origin has no room left.
class _QuotaExceeded implements Exception {
  const _QuotaExceeded();

  @override
  String toString() => 'QuotaExceededError';
}
