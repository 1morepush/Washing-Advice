/// Adding clothes from photos of you wearing them.
///
/// The reading is the server's job and is tested there. What is worth pinning
/// here is what the app does with it, each piece of which is silent when it
/// breaks:
///
/// * photos are read one at a time, a busy server is waited for, and a photo
///   that fails or is empty does not take the others with it;
/// * a garment already owned, or already seen earlier in the batch, is shown
///   and not ticked;
/// * the cutout becomes the garment's picture and the original becomes its
///   "Worn" photo, stored once however many garments came from it;
/// * and those photos are arranged so that the cutout editor, "Clean up",
///   retaking and deleting a neighbour all still work.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/features/scan/worn_photo_controller.dart';
import 'package:washing_advice/features/wardrobe/cutout_controller.dart';
import 'package:washing_advice/features/wardrobe/shared_photos.dart';

import 'support/fixtures.dart';
import 'support/worn_fakes.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late CountingImageStore store;
  late WornGateway gateway;
  late ProviderContainer container;

  /// Builds the container around [photos] as the camera roll.
  void setUpWith(List<Object> script, {int photos = 1}) {
    repository = InMemoryWardrobeRepository();
    store = CountingImageStore();
    gateway = WornGateway(script);
    container = ProviderContainer(
      overrides: [
        imageStoreProvider.overrideWithValue(store),
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        aiGatewayProvider.overrideWithValue(gateway),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'garment'),
        ),
        imageCaptureProvider.overrideWithValue(
          FixedImageCaptureSource([
            for (var i = 0; i < photos; i++)
              ScanImage(bytes: [...wornPng.bytes, i], width: 30, height: 40),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  WornPhotoController controller() =>
      container.read(wornPhotoControllerProvider.notifier);
  WornPhotoState state() => container.read(wornPhotoControllerProvider);
  WornReviewing reviewing() => state() as WornReviewing;

  Future<List<WardrobeItem>> wardrobe() =>
      repository.query(const WardrobeQuery.owned());

  group('reading photos', () {
    testWidgets('each photo is one request, read in order', (tester) async {
      setUpWith([
        [wornDetection(name: 'A')],
        [wornDetection(name: 'B', type: ItemType.jeans, hex: '#222222')],
        [wornDetection(name: 'C', type: ItemType.hoodie, hex: '#AA2222')],
      ], photos: 3);

      final seen = <(int, int)>[];
      container.listen(wornPhotoControllerProvider, (_, next) {
        if (next is WornScanning) seen.add((next.current, next.total));
      });

      await tester.runAsync(() => controller().start(fromGallery: true));

      expect(gateway.calls, 3);
      expect(seen.toSet(), {(1, 3), (2, 3), (3, 3)});
      expect(reviewing().finds, hasLength(3));
      expect(
        [for (final f in reviewing().finds) f.photoIndex],
        [0, 1, 2],
        reason: 'each find remembers the photo it came from',
      );
    });

    testWidgets('a rate-limited photo waits and continues', (tester) async {
      // The free tier meters by the minute, and the photo after a limited one
      // would fail the same way. Waiting once costs seconds.
      setUpWith([
        [wornDetection(name: 'A')],
        const ScanFailure(
          'The AI service is busy.',
          retryAfter: Duration(milliseconds: 20),
        ),
        [wornDetection(name: 'B', type: ItemType.jeans, hex: '#222222')],
        [wornDetection(name: 'C', type: ItemType.hoodie, hex: '#AA2222')],
      ], photos: 3);

      // `script` is by call number, so the retry is call 3 (index 2) and
      // photo three is call 4.
      await tester.runAsync(() => controller().start(fromGallery: true));

      expect(gateway.calls, 4, reason: 'three photos plus one retry');
      expect(reviewing().finds, hasLength(3));
      expect(reviewing().notes, isEmpty);
    });

    testWidgets('a wait longer than a batch should hold for is reported', (
      tester,
    ) async {
      setUpWith([
        const ScanFailure('Busy.', retryAfter: Duration(minutes: 30)),
        [wornDetection()],
      ], photos: 2);

      await tester.runAsync(() => controller().start(fromGallery: true));

      expect(reviewing().notes.single.photoNumber, 1);
      expect(reviewing().finds, hasLength(1), reason: 'photo 2 still read');
    });

    testWidgets('an empty photo and a failed one are named, the rest go on', (
      tester,
    ) async {
      setUpWith([
        <WornDetection>[],
        const ScanFailure('Could not reach the server.'),
        [wornDetection()],
      ], photos: 3);

      await tester.runAsync(() => controller().start(fromGallery: true));

      final notes = reviewing().notes;
      expect([for (final n in notes) n.photoNumber], [1, 2]);
      expect(notes.first.message, contains('No clothes'));
      expect(notes.last.message, contains('Could not reach'));
      expect(reviewing().finds, hasLength(1));
      expect(reviewing().finds.single.photoIndex, 2);
    });

    testWidgets('nothing found anywhere leaves nothing to add', (tester) async {
      setUpWith([<WornDetection>[]]);

      await tester.runAsync(() => controller().start());

      expect(reviewing().finds, isEmpty);
      expect(reviewing().notes, hasLength(1));
    });

    testWidgets('backing out of the camera changes nothing', (tester) async {
      setUpWith([]);
      container.read(imageCaptureProvider);
      // An empty camera roll: the same as cancelling the picker.
      final empty = ProviderContainer(
        overrides: [
          imageCaptureProvider.overrideWithValue(FixedImageCaptureSource([])),
          aiGatewayProvider.overrideWithValue(gateway),
          wardrobeRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(empty.dispose);

      await tester.runAsync(
        () => empty.read(wornPhotoControllerProvider.notifier).start(),
      );

      expect(empty.read(wornPhotoControllerProvider), isA<WornIdle>());
      expect(gateway.calls, 0);
    });
  });

  group('garments already known', () {
    testWidgets('one in the wardrobe is shown and not ticked', (tester) async {
      setUpWith([
        [wornDetection()],
      ]);
      await repository.save(
        confidentItem(
          id: 'owned',
          name: 'My navy jumper',
          type: ItemType.sweater,
          hex: '#1F2A44',
          colorName: 'Navy',
        ),
      );

      await tester.runAsync(() => controller().start());

      final r = reviewing();
      expect(r.finds.single.ownedAs?.displayName, 'My navy jumper');
      expect(r.accepted, isEmpty);
      expect(r.alreadyOwnedCount, 1);
    });

    testWidgets('a new one is ticked', (tester) async {
      setUpWith([
        [wornDetection()],
      ]);
      await repository.save(
        confidentItem(id: 'x', name: 'Red dress', type: ItemType.dress),
      );

      await tester.runAsync(() => controller().start());

      expect(reviewing().accepted, hasLength(1));
      expect(reviewing().finds.single.isDuplicate, isFalse);
    });

    testWidgets('the same jumper in a second photo is not offered twice', (
      tester,
    ) async {
      // Outfit photos are full of favourites. Adding each sighting would fill
      // the wardrobe with copies.
      setUpWith([
        [wornDetection()],
        [wornDetection()],
      ], photos: 2);

      await tester.runAsync(() => controller().start(fromGallery: true));

      final finds = reviewing().finds;
      expect(finds, hasLength(2));
      expect(finds.first.isDuplicate, isFalse);
      expect(finds.last.repeatOf?.photoNumber, 1);
      expect(reviewing().accepted, hasLength(1));
    });

    testWidgets('two alike in one photo are two garments', (tester) async {
      setUpWith([
        [wornDetection(), wornDetection(left: 0.5)],
      ]);

      await tester.runAsync(() => controller().start());

      expect(reviewing().accepted, hasLength(2));
    });

    testWidgets('one can be taken anyway', (tester) async {
      setUpWith([
        [wornDetection()],
      ]);
      await repository.save(
        confidentItem(
          id: 'owned',
          name: 'My navy jumper',
          type: ItemType.sweater,
          hex: '#1F2A44',
          colorName: 'Navy',
        ),
      );
      await tester.runAsync(() => controller().start());
      controller().toggle(0);

      await tester.runAsync(() => controller().saveAccepted());

      expect(await wardrobe(), hasLength(2));
    });
  });

  group('pictures', () {
    testWidgets('a cutout is the garment picture, as the server sent it', (
      tester,
    ) async {
      setUpWith([
        [wornDetection()],
      ]);

      await tester.runAsync(() => controller().start());

      final find = reviewing().finds.single;
      expect(find.pictureKind, WornPicture.outline);
      expect(find.picture.bytes, wornCutoutBytes);
    });

    testWidgets('a box picture is kept as a box picture', (tester) async {
      setUpWith([
        [wornDetection(kind: CutoutKind.box)],
      ]);

      await tester.runAsync(() => controller().start());

      expect(reviewing().finds.single.pictureKind, WornPicture.box);
    });

    testWidgets('a detection with no picture is cropped from the photo', (
      tester,
    ) async {
      setUpWith([
        [wornDetection(kind: null)],
      ]);

      await tester.runAsync(() => controller().start());

      final find = reviewing().finds.single;
      expect(find.pictureKind, WornPicture.cropped);
      expect(find.picture.bytes, isNotEmpty);
    });

    testWidgets('and a photo that will not decode still yields the garment', (
      tester,
    ) async {
      // A worse picture, never a lost garment.
      setUpWith([
        [wornDetection(kind: null)],
      ]);
      container = ProviderContainer(
        overrides: [
          imageStoreProvider.overrideWithValue(store),
          wardrobeRepositoryProvider.overrideWithValue(repository),
          eventLogProvider.overrideWithValue(InMemoryEventLog()),
          aiGatewayProvider.overrideWithValue(gateway),
        ],
      );
      addTearDown(container.dispose);

      await tester.runAsync(
        () => controller().scan([
          const ScanImage(bytes: [1, 2, 3]),
        ]),
      );

      expect(reviewing().finds, hasLength(1));
      expect(reviewing().finds.single.pictureKind, WornPicture.cropped);
    });
  });

  group('saving', () {
    testWidgets('the cutout is the display picture, the original is Worn', (
      tester,
    ) async {
      setUpWith([
        [wornDetection()],
      ]);
      await tester.runAsync(() => controller().start());

      await tester.runAsync(() => controller().saveAccepted());

      final item = (await wardrobe()).single;
      final front = item.photos.withRole(PhotoRole.front).single;
      final worn = item.photos.withRole(PhotoRole.worn).single;

      // What the tile shows is the cutout...
      expect(item.photos.displayPhoto, front);
      expect(front.isPrimary, isTrue);
      expect(
        await tester.runAsync(() => store.read(item.photos.displayImageUri!)),
        wornCutoutBytes,
      );
      // ...and the Worn photo is the whole photograph, never a tile.
      expect(worn.isPrimary, isFalse);
      expect(worn.hasCutout, isFalse);
      expect(await tester.runAsync(() => store.read(worn.uri)), [
        ...wornPng.bytes,
        0,
      ]);
      expect(worn.width, 30);
      expect(worn.height, 40);
      expect((state() as WornSaved).saved, 1);
    });

    testWidgets('the cutout is stored twice so editing cannot lose it', (
      tester,
    ) async {
      // The mask editor reads `uri` as the picture to cut from and writes to
      // the cutout's own name, deleting what was there. One file for both
      // would be overwritten by the very edit it feeds.
      setUpWith([
        [wornDetection()],
      ]);
      await tester.runAsync(() => controller().start());
      await tester.runAsync(() => controller().saveAccepted());

      final front = (await wardrobe()).single.photos
          .withRole(PhotoRole.front)
          .single;

      expect(front.cutoutUri, isNotNull);
      expect(front.cutoutUri, isNot(front.uri));
      expect(await tester.runAsync(() => store.read(front.uri)), isNotNull);
      expect(
        await tester.runAsync(() => store.read(front.cutoutUri!)),
        wornCutoutBytes,
      );
    });

    testWidgets('the cutout editor and Clean up have a photo to work on', (
      tester,
    ) async {
      setUpWith([
        [wornDetection()],
      ]);
      await tester.runAsync(() => controller().start());
      await tester.runAsync(() => controller().saveAccepted());

      final item = (await wardrobe()).single;

      expect(CutoutController.isAvailableFor(item), isTrue);
      // The editor reads this photo's `uri` and `cutoutUri`; neither may be
      // the whole worn photograph.
      final editable = item.photos.displayPhoto!;
      expect(editable.role, PhotoRole.front);
      expect(
        editable.uri,
        isNot(item.photos.withRole(PhotoRole.worn).single.uri),
      );
    });

    testWidgets('a box picture has no cutout, so Clean up can offer one', (
      tester,
    ) async {
      setUpWith([
        [wornDetection(kind: CutoutKind.box)],
      ]);
      await tester.runAsync(() => controller().start());
      await tester.runAsync(() => controller().saveAccepted());

      final item = (await wardrobe()).single;
      final front = item.photos.withRole(PhotoRole.front).single;

      expect(front.hasCutout, isFalse);
      expect(item.photos.displayPhoto, front, reason: 'primary, not the worn');
      expect(
        await tester.runAsync(() => store.read(front.uri)),
        wornCutoutBytes,
      );
    });

    testWidgets('retaking later leaves the worn photo and takes over', (
      tester,
    ) async {
      setUpWith([
        [wornDetection()],
      ]);
      await tester.runAsync(() => controller().start());
      await tester.runAsync(() => controller().saveAccepted());
      final item = (await wardrobe()).single;

      // What the retake does to the photo set.
      final retaken = ItemPhoto(
        uri: 'memory:retake',
        role: PhotoRole.front,
        capturedAt: DateTime(2030),
      );
      final photos = item.photos.add(retaken).withPrimary('memory:retake');

      expect(photos.displayPhoto?.uri, retaken.uri);
      expect(photos.withRole(PhotoRole.worn), hasLength(1));
    });

    testWidgets('the original is stored once for every garment in it', (
      tester,
    ) async {
      setUpWith([
        [
          wornDetection(),
          wornDetection(
            type: ItemType.jeans,
            hex: '#222222',
            colour: 'Black',
            name: 'Black jeans',
            left: 0.3,
          ),
          wornDetection(
            type: ItemType.hoodie,
            hex: '#AA2222',
            colour: 'Red',
            name: 'Red hoodie',
            left: 0.5,
          ),
        ],
      ]);
      await tester.runAsync(() => controller().start());

      await tester.runAsync(() => controller().saveAccepted());

      final items = await wardrobe();
      expect(items, hasLength(3));
      expect(
        store.saved.where((name) => name.startsWith('worn-')),
        hasLength(1),
        reason: 'one photo is one file',
      );
      final uris = {
        for (final item in items)
          item.photos.withRole(PhotoRole.worn).single.uri,
      };
      expect(uris, hasLength(1), reason: 'all three point at that file');
    });

    testWidgets('a photo whose garments were all turned down is not stored', (
      tester,
    ) async {
      setUpWith([
        [wornDetection()],
        [wornDetection(type: ItemType.jeans, hex: '#222222', name: 'Jeans')],
      ], photos: 2);
      await tester.runAsync(() => controller().start(fromGallery: true));
      controller().toggle(0);

      await tester.runAsync(() => controller().saveAccepted());

      expect(
        store.saved.where((name) => name.startsWith('worn-')),
        hasLength(1),
      );
      expect(await wardrobe(), hasLength(1));
    });

    testWidgets('photos from different batches get different files', (
      tester,
    ) async {
      setUpWith([
        [wornDetection()],
        [wornDetection(type: ItemType.jeans, hex: '#222222', name: 'Jeans')],
      ], photos: 2);
      await tester.runAsync(() => controller().start(fromGallery: true));
      await tester.runAsync(() => controller().saveAccepted());

      final names = store.saved.where((name) => name.startsWith('worn-'));
      expect(names.toSet(), hasLength(2));
    });

    testWidgets('care is resolved and there is no label reading', (
      tester,
    ) async {
      setUpWith([
        [wornDetection()],
      ]);
      await tester.runAsync(() => controller().start());
      await tester.runAsync(() => controller().saveAccepted());

      final item = (await wardrobe()).single;

      expect(item.care.source, isNot(Provenance.tagScan));
      expect(
        await repository.query(const WardrobeQuery(needsCareTagScan: true)),
        hasLength(1),
        reason: 'it gets the usual scan-the-care-label prompt',
      );
    });

    testWidgets('a rename before saving is kept', (tester) async {
      setUpWith([
        [wornDetection()],
      ]);
      await tester.runAsync(() => controller().start());
      controller().rename(0, 'Dad\'s jumper');

      await tester.runAsync(() => controller().saveAccepted());

      expect((await wardrobe()).single.displayName, 'Dad\'s jumper');
    });

    testWidgets('nothing reaches the wardrobe before they say so', (
      tester,
    ) async {
      setUpWith([
        [wornDetection()],
      ]);

      await tester.runAsync(() => controller().start());

      expect(await wardrobe(), isEmpty);
      expect(store.saved, isEmpty);
    });
  });

  group('deleting a garment from a shared photo', () {
    testWidgets('leaves the file the others still show', (tester) async {
      setUpWith([
        [wornDetection(), wornDetection(left: 0.5, name: 'Other')],
      ]);
      // Two different garments so neither is a duplicate of the other.
      gateway.script[0] = [
        wornDetection(),
        wornDetection(
          type: ItemType.jeans,
          hex: '#222222',
          colour: 'Black',
          name: 'Black jeans',
        ),
      ];
      await tester.runAsync(() => controller().start());
      await tester.runAsync(() => controller().saveAccepted());
      final items = await wardrobe();
      expect(items, hasLength(2));

      final held = await urisHeldByOthers(repository, items.first);

      final wornUri = items.first.photos.withRole(PhotoRole.worn).single.uri;
      expect(held, {wornUri});
    });

    testWidgets('a lone garment holds nothing back', (tester) async {
      setUpWith([
        [wornDetection()],
      ]);
      await tester.runAsync(() => controller().start());
      await tester.runAsync(() => controller().saveAccepted());

      final item = (await wardrobe()).single;

      expect(await urisHeldByOthers(repository, item), isEmpty);
    });
  });

  group('handed a detection from Worn today', () {
    testWidgets('opens the review on it without asking the server', (
      tester,
    ) async {
      setUpWith([]);

      await tester.runAsync(
        () => controller().reviewDetections(wornPng, [wornDetection()]),
      );

      expect(gateway.calls, 0);
      expect(reviewing().accepted, hasLength(1));
    });
  });
}
