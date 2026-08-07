/// Making a cutout for an item that does not have one.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/wardrobe/cutout_controller.dart';

void main() {
  const id = ItemId('jumper');

  late InMemoryWardrobeRepository repository;
  late MemoryImageStore images;
  late _FakeGateway gateway;
  late ProviderContainer container;

  setUp(() {
    repository = InMemoryWardrobeRepository();
    images = MemoryImageStore();
    gateway = _FakeGateway();
    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        imageStoreProvider.overrideWithValue(images),
        aiGatewayProvider.overrideWithValue(gateway),
      ],
    );
  });

  tearDown(() => container.dispose());

  CutoutController controller() =>
      container.read(cutoutControllerProvider.notifier);

  /// An item with a photograph and no cutout — what everything scanned before
  /// the feature existed looks like.
  Future<WardrobeItem> withPhoto() async {
    final uri = await images.save(
      Uint8List.fromList([1, 2, 3]),
      name: 'jumper-front',
    );
    final item = _item().copyWith(
      photos: PhotoSet([
        ItemPhoto(
          uri: uri,
          role: PhotoRole.front,
          capturedAt: DateTime.utc(2026, 1, 1),
        ),
      ]),
    );
    await repository.save(item);
    return item;
  }

  group('when it is offered', () {
    test('an item with a photo and no cutout can have one made', () async {
      expect(CutoutController.isAvailableFor(await withPhoto()), isTrue);
    });

    test('an item with no photo at all cannot', () async {
      // Nothing to work from. Offering the button would be offering a failure.
      expect(CutoutController.isAvailableFor(_item()), isFalse);
    });

    test('an item that already has one is not offered it again', () async {
      final item = (await withPhoto());
      final done = item.copyWith(
        photos: item.photos.withCutout(
          item.photos.displayPhoto!.uri,
          'data:image/png;base64,AAAA',
        ),
      );

      expect(CutoutController.isAvailableFor(done), isFalse);
    });
  });

  group('generating', () {
    test('attaches the cutout and keeps the original photo', () async {
      final before = await withPhoto();
      await controller().generate(id);

      final after = (await repository.byId(id))!;
      final photo = after.photos.displayPhoto!;

      expect(container.read(cutoutControllerProvider), CutoutStatus.done);
      expect(photo.hasCutout, isTrue);
      // The source survives, so a better remover can redo this later.
      expect(photo.uri, before.photos.displayPhoto!.uri);
      expect(after.photos.displayImageUri, photo.cutoutUri);
    });

    test(
      're-reads the stored photo rather than asking for a new one',
      () async {
        await withPhoto();
        await controller().generate(id);

        // Making someone re-photograph a garment to fix a background is asking
        // them to do the app's work.
        expect(gateway.received, isNotNull);
        expect(gateway.received, [1, 2, 3]);
      },
    );

    test('a refusal leaves the item untouched', () async {
      gateway.result = null;
      await withPhoto();

      await controller().generate(id);

      expect(container.read(cutoutControllerProvider), CutoutStatus.failed);
      expect(
        (await repository.byId(id))!.photos.displayPhoto!.hasCutout,
        isFalse,
      );
    });

    test('a photo whose file is gone fails rather than throwing', () async {
      // A restored backup that carried the database but not the images. The
      // row is fine and the bytes are not, and no amount of retrying helps.
      await repository.save(
        _item().copyWith(
          photos: PhotoSet([
            ItemPhoto(
              uri: 'file:///gone.png',
              role: PhotoRole.front,
              capturedAt: DateTime.utc(2026, 1, 1),
            ),
          ]),
        ),
      );

      await controller().generate(id);
      expect(container.read(cutoutControllerProvider), CutoutStatus.failed);
    });

    test('an item that no longer exists fails quietly', () async {
      await controller().generate(const ItemId('deleted'));
      expect(container.read(cutoutControllerProvider), CutoutStatus.failed);
    });
  });
}

WardrobeItem _item() {
  final now = DateTime.utc(2026, 8, 5);
  return WardrobeItem(
    id: const ItemId('jumper'),
    name: 'Charcoal merino jumper',
    type: Confident(
      ItemType.sweater,
      confidence: 0.9,
      source: Provenance.aiInference,
    ),
    composition: Confident(
      FabricComposition(const {Fiber.wool: 100}),
      confidence: 0.9,
      source: Provenance.tagScan,
    ),
    colors: Confident(
      ColorPalette([ItemColor.fromHex('#3C3F44', name: 'Charcoal')]),
      confidence: 0.9,
      source: Provenance.aiInference,
    ),
    care: const CareProfile.unknown(),
    addedAt: now,
    updatedAt: now,
  );
}

class _FakeGateway extends AiGateway {
  _FakeGateway() : super(baseUrl: Uri.parse('http://test.invalid/'));

  /// Null stands for a server that refused to separate the garment.
  Uint8List? result = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);

  List<int>? received;

  @override
  Future<Uint8List?> cutout(ScanImage image) async {
    received = image.bytes;
    return result;
  }
}
