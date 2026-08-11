/// Retaking a garment's photograph and asking what it is again.
///
/// Two things have to be true at once and they pull against each other: the new
/// answer has to actually take effect, or the feature does nothing; and the
/// user's own corrections have to survive it, or the feature quietly undoes
/// their work. Most of what is asserted here is the second, because it is the
/// half that fails silently.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/scan/retake_controller.dart';

import '../support/fixtures.dart';

final _image = ScanImage(bytes: const [4, 5, 6], width: 800, height: 1200);

void main() {
  late InMemoryWardrobeRepository repository;
  late MemoryImageStore images;

  ProviderContainer build({AiGateway? gateway, ImageCaptureSource? camera}) {
    final container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(images),
        aiGatewayProvider.overrideWithValue(gateway ?? _Gateway()),
        if (camera != null) imageCaptureProvider.overrideWithValue(camera),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// An item with a front photograph and a cutout — the bad one being replaced.
  Future<WardrobeItem> photographed({String? brand}) async {
    final uri = await images.save(
      Uint8List.fromList([1, 2, 3]),
      name: 'tee-front',
    );
    final cutoutUri = await images.save(
      Uint8List.fromList([7, 7, 7]),
      name: 'tee-front-cutout',
    );
    final item = confidentItem(id: 'tee', name: 'White cotton tee').copyWith(
      brand: brand == null ? null : Confident.fromUser(brand),
      photos: PhotoSet([
        ItemPhoto(
          uri: uri,
          cutoutUri: cutoutUri,
          role: PhotoRole.front,
          capturedAt: DateTime.utc(2026, 1, 1),
        ),
      ]),
    );
    await repository.save(item);
    return item;
  }

  setUp(() {
    repository = InMemoryWardrobeRepository();
    images = MemoryImageStore();
  });

  test('the new photograph becomes the one the item shows', () async {
    // The reason this needs `withPrimary` rather than just adding the photo:
    // `displayPhoto` prefers whichever photo has a cutout, so a retake whose
    // own cutout failed would lose to the bad mask it was taken to replace and
    // the screen would not visibly change at all.
    final container = build();
    final item = await photographed();
    final was = item.photos.displayPhoto!.uri;
    final controller = container.read(
      retakeControllerProvider(item.id).notifier,
    );

    await controller.identify(_image);
    await controller.save();

    final saved = (await repository.byId(item.id))!;
    expect(saved.photos.displayPhoto!.uri, isNot(was));
    expect(saved.photos.displayPhoto!.hasCutout, isTrue);
  });

  test('the old photograph is kept rather than overwritten', () async {
    // Sync unions photos by URI, so a deleted one comes back on the next round
    // trip anyway — and if the second attempt is worse, the first is the only
    // picture of the garment that exists.
    final container = build();
    final item = await photographed();
    final was = item.photos.displayPhoto!.uri;
    final controller = container.read(
      retakeControllerProvider(item.id).notifier,
    );

    await controller.identify(_image);
    await controller.save();

    final saved = (await repository.byId(item.id))!;
    expect(saved.photos.length, 2);
    expect(saved.photos.photos.map((p) => p.uri), contains(was));
    // And its bytes are still there — a name collision would have written the
    // new picture over them while the record kept the old dimensions.
    expect(await images.read(was), Uint8List.fromList([1, 2, 3]));
  });

  test('a correction the user made by hand survives the re-scan', () async {
    final container = build(gateway: _Gateway(brand: 'Muji'));
    final item = await photographed(brand: 'Uniqlo');
    final controller = container.read(
      retakeControllerProvider(item.id).notifier,
    );

    await controller.identify(_image);
    await controller.save();

    expect((await repository.byId(item.id))!.brand!.value, 'Uniqlo');
  });

  test('a better identification does take effect', () async {
    final container = build(gateway: _Gateway(type: ItemType.poloShirt));
    final item = await photographed();
    final controller = container.read(
      retakeControllerProvider(item.id).notifier,
    );

    await controller.identify(_image);
    await controller.save();

    expect((await repository.byId(item.id))!.type.value, ItemType.poloShirt);
  });

  test('the review shows the difference and nothing else', () async {
    final container = build(gateway: _Gateway(type: ItemType.poloShirt));
    final item = await photographed();

    await container
        .read(retakeControllerProvider(item.id).notifier)
        .identify(_image);

    final state =
        container.read(retakeControllerProvider(item.id)) as RetakeReviewing;
    expect(state.changes.map((c) => c.$1), ['Type']);
    expect(state.changes.single.$3, 'Polo shirt');
  });

  test('a photograph that agrees with the old one says so', () async {
    // An empty change list is a real outcome, not an error state — the picture
    // is still worth replacing, and the screen has to say why.
    final container = build();
    final item = await photographed();

    await container
        .read(retakeControllerProvider(item.id).notifier)
        .identify(_image);

    final state =
        container.read(retakeControllerProvider(item.id)) as RetakeReviewing;
    expect(state.changes, isEmpty);
  });

  test('nothing is written until the review is accepted', () async {
    // The photograph is held on the state and filed on save. A review the user
    // abandons has to leave the item exactly as it was.
    final container = build(gateway: _Gateway(type: ItemType.poloShirt));
    final item = await photographed();

    await container
        .read(retakeControllerProvider(item.id).notifier)
        .identify(_image);

    final untouched = (await repository.byId(item.id))!;
    expect(untouched.type.value, item.type.value);
    expect(untouched.photos.length, 1);
  });

  test(
    'a cutout that fails still leaves the new photograph attached',
    () async {
      // The garment can be marked out by hand afterwards; losing the picture
      // because the remover gave up would take that option away too.
      final container = build(gateway: _Gateway(cuts: false));
      final item = await photographed();
      final controller = container.read(
        retakeControllerProvider(item.id).notifier,
      );

      await controller.identify(_image);
      await controller.save();

      final saved = (await repository.byId(item.id))!;
      expect(saved.photos.length, 2);
      expect(saved.photos.displayPhoto!.hasCutout, isFalse);
    },
  );

  test('a cancelled camera goes back to the button, not to an error', () async {
    final container = build(camera: const _CancellingCamera());
    final item = await photographed();

    await container
        .read(retakeControllerProvider(item.id).notifier)
        .captureAndIdentify();

    expect(
      container.read(retakeControllerProvider(item.id)),
      isA<RetakeIdle>(),
    );
  });

  test(
    'a server that cannot read the photo is a failure, not a hang',
    () async {
      final container = build(gateway: _FailingGateway());
      final item = await photographed();

      await container
          .read(retakeControllerProvider(item.id).notifier)
          .identify(_image);

      expect(
        container.read(retakeControllerProvider(item.id)),
        isA<RetakeFailed>(),
      );
    },
  );

  test('an item deleted mid-flow is said so, not retried forever', () async {
    final container = build();

    await container
        .read(retakeControllerProvider(const ItemId('gone')).notifier)
        .identify(_image);

    final state =
        container.read(retakeControllerProvider(const ItemId('gone')))
            as RetakeFailed;
    expect(state.isRetryable, isFalse);
  });
}

class _Gateway extends AiGateway {
  _Gateway({this.type = ItemType.tShirt, this.brand, this.cuts = true})
    : super(baseUrl: Uri.parse('http://test.invalid/'));

  final ItemType type;
  final String? brand;
  final bool cuts;

  @override
  Future<GarmentScanResult> scanGarment(List<ScanImage> images) async =>
      GarmentScanResult(
        type: Confident(type, confidence: 0.99, source: Provenance.aiInference),
        colors: Confident(
          ColorPalette([ItemColor.fromHex('#FAFAFA', name: 'White')]),
          confidence: 0.9,
          source: Provenance.aiInference,
        ),
        brand: brand == null
            ? null
            : Confident(
                brand!,
                confidence: 0.99,
                source: Provenance.aiInference,
              ),
      );

  @override
  Future<Uint8List?> cutout(ScanImage image) async =>
      cuts ? Uint8List.fromList([9, 9, 9]) : null;
}

class _FailingGateway extends AiGateway {
  _FailingGateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  @override
  Future<GarmentScanResult> scanGarment(List<ScanImage> images) async =>
      throw const ScanFailure('The server could not read that photo.');
}

class _CancellingCamera implements ImageCaptureSource {
  const _CancellingCamera();

  @override
  Future<ScanImage?> capture() async => null;

  @override
  Future<List<ScanImage>> pickMultiple() async => const [];
}
