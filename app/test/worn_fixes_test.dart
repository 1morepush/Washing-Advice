/// The review fixes to the worn-photo feature, each pinned against real pixels
/// or a real controller run:
///
/// * the front photo is an opaque box crop and the cutout shares its frame, so
///   the editor's "add back" brush restores real pixels;
/// * leaving a screen mid-scan stops it, in both controllers;
/// * a garment that fails to save leaves no files behind;
/// * Worn today re-matches after a garment is added, and a failed confirm says
///   so instead of hanging.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show decodeImageFromList;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/features/laundry/worn_today_photo_controller.dart';
import 'package:washing_advice/features/scan/crop.dart';
import 'package:washing_advice/features/scan/cutout_preview.dart';
import 'package:washing_advice/features/scan/garment_intake.dart';
import 'package:washing_advice/features/scan/worn_photo_controller.dart';
import 'package:washing_advice/features/wardrobe/mask_edit.dart';

import 'support/fixtures.dart';
import 'support/worn_fakes.dart';

const _red = (220, 30, 30);
const _blue = (40, 60, 200);

/// A 100 x 80 photograph, blue with a red garment in the box 20..60 x 16..56.
ScanImage _photo() {
  final image = img.Image(width: 100, height: 80);
  img.fill(image, color: img.ColorRgb8(_blue.$1, _blue.$2, _blue.$3));
  img.fillRect(
    image,
    x1: 20,
    y1: 16,
    x2: 59,
    y2: 55,
    color: img.ColorRgb8(_red.$1, _red.$2, _red.$3),
  );
  return ScanImage(
    bytes: img.encodePng(image),
    mimeType: 'image/png',
    width: 100,
    height: 80,
  );
}

/// What the server sends for [_box]: a transparent frame of the box's own size
/// with nothing of the garment in it, as a mask that missed everything would.
Uint8List _emptyCutout(int width, int height) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
  return Uint8List.fromList(img.encodePng(image));
}

// The box 20..60 x 16..56 of the 100 x 80 photograph, as the server reports it.
final _box = BoundingBox(left: 0.2, top: 0.2, width: 0.4, height: 0.5);

WornDetection _detection({
  String name = 'Red top',
  Uint8List? cutout,
  CutoutKind? kind = CutoutKind.outline,
  ItemType type = ItemType.sweater,
  String hex = '#DC1E1E',
}) => WornDetection(
  scan: wornDetection(type: type, hex: hex, name: name).scan,
  boundingBox: _box,
  detectionConfidence: 0.9,
  cutout: kind == null ? null : (cutout ?? _emptyCutout(40, 40)),
  cutoutKind: kind,
);

/// Fails to save the garments named in [failing], as a full disk would.
class _FlakyIntake extends GarmentIntake {
  const _FlakyIntake(super.ref, this.failing);

  final Set<String> failing;

  @override
  Future<WardrobeItem> saveItem(WardrobeItem item) {
    if (failing.contains(item.displayName)) {
      throw Exception('disk full');
    }
    return super.saveItem(item);
  }
}

/// An event log that cannot record a wear, as a full disk would not.
class _FailingEventLog implements EventLog {
  final _inner = InMemoryEventLog();

  @override
  Future<void> append(WardrobeEvent event) {
    if (event is ItemWorn) throw Exception('log is down');
    return _inner.append(event);
  }

  @override
  Future<void> appendAll(Iterable<WardrobeEvent> events) {
    if (events.any((e) => e is ItemWorn)) throw Exception('log is down');
    return _inner.appendAll(events);
  }

  @override
  Future<List<WardrobeEvent>> forItem(ItemId itemId) => _inner.forItem(itemId);

  @override
  Future<List<WardrobeEvent>> all({
    DateTime? since,
    DateTime? until,
    DateTime? recordedSince,
    Set<String>? types,
  }) => _inner.all(
    since: since,
    until: until,
    recordedSince: recordedSince,
    types: types,
  );
}

void main() {
  late InMemoryWardrobeRepository repository;
  late CountingImageStore store;
  late WornGateway gateway;
  late ProviderContainer container;

  void setUpWith(
    List<Object> script, {
    ScanImage? photo,
    int photos = 1,
    Set<String> failing = const {},
    EventLog? events,
  }) {
    repository = InMemoryWardrobeRepository();
    store = CountingImageStore();
    gateway = WornGateway(script);
    final shot = photo ?? wornPng;
    container = ProviderContainer(
      overrides: [
        imageStoreProvider.overrideWithValue(store),
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(events ?? InMemoryEventLog()),
        aiGatewayProvider.overrideWithValue(gateway),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'garment'),
        ),
        if (failing.isNotEmpty)
          garmentIntakeProvider.overrideWith(
            (ref) => _FlakyIntake(ref, failing),
          ),
        imageCaptureProvider.overrideWithValue(
          FixedImageCaptureSource([
            for (var i = 0; i < photos; i++)
              ScanImage(
                bytes: [...shot.bytes],
                mimeType: shot.mimeType,
                width: shot.width,
                height: shot.height,
              ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(wornPhotoControllerProvider, (_, _) {});
    container.listen(wornTodayPhotoControllerProvider, (_, _) {});
  }

  WornPhotoController worn() =>
      container.read(wornPhotoControllerProvider.notifier);
  WornPhotoState wornState() => container.read(wornPhotoControllerProvider);

  group('the box crop and the cutout share a frame', () {
    test('the box is rounded edge by edge, as the server does', () {
      // 0.2 * 100 = 20.000000000000004-ish; edges, never a rounded width.
      final pixels = exactBoxPixels(_box, 100, 80)!;
      expect(
        [pixels.left, pixels.top, pixels.right, pixels.bottom],
        [20, 16, 60, 56],
      );

      // A server box in a 1003 px photograph: pixel edges 101..407 over 1003.
      final awkward = BoundingBox(
        left: 101 / 1003,
        top: 0,
        width: (407 - 101) / 1003,
        height: 1,
      );
      final awkwardPixels = exactBoxPixels(awkward, 1003, 10)!;
      expect([awkwardPixels.left, awkwardPixels.right], [101, 407]);
    });

    test('a small box is not enlarged to a tenth of the photograph', () {
      final glasses = BoundingBox(
        left: 0.4,
        top: 0.1,
        width: 0.05,
        height: 0.03,
      );

      final pixels = exactBoxPixels(glasses, 1000, 1000)!;

      expect((pixels.width, pixels.height), (50, 30));
    });

    test('a box with no area is nothing', () {
      expect(
        exactBoxPixels(
          BoundingBox(left: 0.5, top: 0.5, width: 0, height: 0.2),
          100,
          100,
        ),
        isNull,
      );
    });

    testWidgets('the crop is exactly the box, opaque and from the photo', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final photo = _photo();
        final decoded = await decodeImageFromList(
          Uint8List.fromList(photo.bytes),
        );

        final crop = await cropToExactBox(
          photo: photo,
          decoded: decoded,
          box: _box,
        );

        expect((crop.width, crop.height), (40, 40));
        final out = img.decodeJpg(Uint8List.fromList(crop.bytes))!;
        expect((out.width, out.height), (40, 40));
        final centre = out.getPixel(20, 20);
        expect(centre.r, closeTo(_red.$1, 12));
        expect(centre.b, closeTo(_red.$3, 12));
        decoded.dispose();
      });
    });

    testWidgets('painting "add back" on a worn garment gets real pixels back', (
      tester,
    ) async {
      // The server's cutout missed the garment entirely: transparent from
      // corner to corner. The editor can still restore it, because the
      // front photo is the box crop and the cutout is the same frame.
      setUpWith([
        [_detection()],
      ], photo: _photo());
      await tester.runAsync(() => worn().start());
      await tester.runAsync(() => worn().saveAccepted());

      final item = (await repository.query(const WardrobeQuery.owned())).single;
      final front = item.photos.withRole(PhotoRole.front).single;
      expect(front.cutoutUri, isNotNull);

      await tester.runAsync(() async {
        final original = await decodeImageFromList(
          (await store.read(front.uri))!,
        );
        final cutout = await decodeImageFromList(
          (await store.read(front.cutoutUri!))!,
        );
        // The same frame, so the editor's mask lines up.
        expect((original.width, original.height), (40, 40));
        expect((cutout.width, cutout.height), (40, 40));

        final png = await renderMask(
          original: original,
          cutout: cutout,
          strokes: [
            MaskStroke(
              mode: MaskMode.add,
              points: const [Offset(20, 20)],
              width: 24,
            ),
          ],
        );
        final restored = img.decodePng(png)!;

        final inside = restored.getPixel(20, 20);
        expect(inside.a, 255, reason: 'the brush brought the garment back');
        expect(inside.r, closeTo(_red.$1, 12));
        expect(inside.b, closeTo(_red.$3, 12));
        expect(restored.getPixel(0, 0).a, 0, reason: 'only where brushed');

        original.dispose();
        cutout.dispose();
      });
    });

    testWidgets('a smaller cutout is scaled onto the box, not misread', (
      tester,
    ) async {
      // The server caps a cutout at 768 px, the box crop is not capped. Same
      // box at half the resolution must still line up.
      await tester.runAsync(() async {
        final photo = _photo();
        final original = await decodeImageFromList(
          Uint8List.fromList(photo.bytes),
        );
        final full = img.Image(width: 20, height: 20, numChannels: 4);
        img.fill(full, color: img.ColorRgba8(255, 255, 255, 255));
        final cutout = await decodeImageFromList(
          Uint8List.fromList(img.encodePng(full)),
        );

        final png = await renderMask(
          original: original,
          cutout: cutout,
          strokes: const [],
        );
        final out = img.decodePng(png)!;

        expect((out.width, out.height), (100, 80));
        expect(out.getPixel(99, 79).a, 255, reason: 'covers the whole frame');
        original.dispose();
        cutout.dispose();
      });
    });
  });

  group('how the garment is stored', () {
    testWidgets('uri is the opaque crop and cutoutUri is the outline', (
      tester,
    ) async {
      final cutout = _emptyCutout(40, 40);
      setUpWith([
        [_detection(cutout: cutout)],
      ], photo: _photo());
      await tester.runAsync(() => worn().start());

      await tester.runAsync(() => worn().saveAccepted());

      final item = (await repository.query(const WardrobeQuery.owned())).single;
      final front = item.photos.withRole(PhotoRole.front).single;
      expect(await store.read(front.cutoutUri!), cutout);
      final stored = img.decodeJpg((await store.read(front.uri))!)!;
      expect((stored.width, stored.height), (40, 40));
      expect(front.width, 40);
      expect(front.height, 40);
    });

    testWidgets('a box garment is the box crop with no cutout', (tester) async {
      setUpWith([
        [_detection(kind: CutoutKind.box)],
      ], photo: _photo());
      await tester.runAsync(() => worn().start());
      await tester.runAsync(() => worn().saveAccepted());

      final front = (await repository.query(
        const WardrobeQuery.owned(),
      )).single.photos.withRole(PhotoRole.front).single;

      expect(front.hasCutout, isFalse);
      final stored = img.decodeJpg((await store.read(front.uri))!)!;
      expect((stored.width, stored.height), (40, 40));
    });

    test('the tile trims the margin the stored cutout keeps', () {
      final frame = img.Image(width: 100, height: 100, numChannels: 4);
      img.fill(frame, color: img.ColorRgba8(0, 0, 0, 0));
      img.fillRect(
        frame,
        x1: 40,
        y1: 30,
        x2: 59,
        y2: 69,
        color: img.ColorRgba8(10, 10, 10, 255),
      );
      final cutout = ScanImage(
        bytes: img.encodePng(frame),
        mimeType: 'image/png',
      );

      final tile = trimmedForTile(cutout);

      expect(tile.width, lessThan(40));
      expect(tile.height, lessThan(60));
      expect(tile.width, greaterThanOrEqualTo(20));
      expect(tile.height, greaterThanOrEqualTo(40));
    });

    test('an empty or undecodable cutout is left as it is', () {
      final empty = ScanImage(
        bytes: _emptyCutout(10, 10),
        mimeType: 'image/png',
      );
      const junk = ScanImage(bytes: [1, 2, 3], mimeType: 'image/png');

      expect(trimmedForTile(empty), same(empty));
      expect(trimmedForTile(junk), same(junk));
    });
  });

  group('leaving the screen mid-scan', () {
    testWidgets('stops the batch: no more requests, state stays idle', (
      tester,
    ) async {
      setUpWith([
        [wornDetection()],
      ], photos: 3);
      final gate = Completer<void>();
      gateway.hold = gate;

      final running = worn().start(fromGallery: true);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(gateway.calls, 1);

      worn().reset();
      gate.complete();
      await tester.runAsync(() => running);

      expect(gateway.calls, 1, reason: 'photos two and three were never sent');
      expect(wornState(), isA<WornIdle>());
    });

    testWidgets('a rate-limit wait is abandoned too', (tester) async {
      setUpWith([
        const ScanFailure('Busy.', retryAfter: Duration(milliseconds: 40)),
        [wornDetection()],
      ]);

      // Wholly inside runAsync, so the controller's wait is a real timer.
      await tester.runAsync(() async {
        final running = worn().start();
        await Future<void>.delayed(const Duration(milliseconds: 15));
        expect((wornState() as WornScanning).waitingFor, isNotNull);

        worn().reset();
        await running;
      });

      expect(gateway.calls, 1, reason: 'no retry after leaving');
      expect(wornState(), isA<WornIdle>());
    });

    testWidgets('reopening starts fresh and works', (tester) async {
      setUpWith([
        [wornDetection()],
      ]);
      final gate = Completer<void>();
      gateway.hold = gate;
      final running = worn().start();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      worn().reset();
      gate.complete();
      await tester.runAsync(() => running);
      expect(wornState(), isA<WornIdle>());

      gateway.hold = null;
      await tester.runAsync(() => worn().start());

      expect(wornState(), isA<WornReviewing>());
    });

    testWidgets('Worn today: reset mid-scan makes no further calls', (
      tester,
    ) async {
      setUpWith([
        [wornDetection()],
      ]);
      final gate = Completer<void>();
      gateway.hold = gate;
      final today = container.read(wornTodayPhotoControllerProvider.notifier);

      final running = today.start();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      today.reset();
      gate.complete();
      await tester.runAsync(() => running);

      expect(gateway.calls, 1);
      expect(
        container.read(wornTodayPhotoControllerProvider).phase,
        WornPhase.idle,
      );
    });
  });

  group('saving a garment that cannot be written', () {
    testWidgets('its files are deleted and the others are kept', (
      tester,
    ) async {
      setUpWith(
        [
          [
            _detection(name: 'Bad top'),
            _detection(name: 'Good top', type: ItemType.jeans, hex: '#222222'),
          ],
        ],
        photo: _photo(),
        failing: {'Bad top'},
      );
      await tester.runAsync(() => worn().start());

      await tester.runAsync(() => worn().saveAccepted());

      final saved = await repository.query(const WardrobeQuery.owned());
      expect(saved.map((i) => i.displayName), ['Good top']);
      expect((wornState() as WornSaved).skipped, 1);
      // The bad garment's crop and cutout go, and so does the original it was
      // the only holder of at that moment; the good garment, saved next,
      // stores it again, so it is there for the garment that kept it.
      expect(store.deleted, hasLength(3));
      final good = saved.single.photos;
      expect(
        await store.read(good.withRole(PhotoRole.worn).single.uri),
        isNotNull,
      );
      final front = good.withRole(PhotoRole.front).single;
      expect(await store.read(front.uri), isNotNull);
      expect(await store.read(front.cutoutUri!), isNotNull);
      expect(store.length, 3, reason: 'crop, cutout and original: no strays');
    });

    testWidgets('the shared original goes too when nothing else holds it', (
      tester,
    ) async {
      setUpWith(
        [
          [_detection(name: 'Bad top')],
        ],
        photo: _photo(),
        failing: {'Bad top'},
      );
      await tester.runAsync(() => worn().start());

      await tester.runAsync(() => worn().saveAccepted());

      expect(await repository.query(const WardrobeQuery.owned()), isEmpty);
      expect(store.deleted, hasLength(3), reason: 'crop, cutout and original');
      expect(store.length, 0, reason: 'nothing is left behind');
    });
  });

  group('Worn today', () {
    testWidgets('a garment added from the photo is matched and ticked', (
      tester,
    ) async {
      setUpWith([
        [
          wornDetection(),
          wornDetection(
            type: ItemType.hat,
            hex: '#CC8822',
            colour: 'Mustard',
            name: 'Mustard hat',
            left: 0.6,
          ),
        ],
      ], photo: _photo());
      final today = container.read(wornTodayPhotoControllerProvider.notifier);
      await tester.runAsync(() => today.start());
      final before = container.read(wornTodayPhotoControllerProvider);
      expect(before.unmatched, hasLength(2));

      await tester.runAsync(() => today.addToWardrobe(before.unmatched.first));
      await tester.runAsync(() => worn().saveAccepted());
      await tester.runAsync(() => today.rematch());

      final after = container.read(wornTodayPhotoControllerProvider);
      expect(
        after.unmatched,
        hasLength(1),
        reason: 'one is in the wardrobe now',
      );
      expect(after.matched, hasLength(1));
      final index = after.sightings.indexWhere(
        (s) => s.certainty != Certainty.none,
      );
      expect(after.selected, contains(index), reason: 'ticked to be logged');
      expect(gateway.calls, 1, reason: 'matching again is not scanning again');
    });

    testWidgets('a confirm that fails clears saving and says so', (
      tester,
    ) async {
      setUpWith([
        [wornDetection()],
      ], events: _FailingEventLog());
      await repository.save(
        confidentItem(
          id: 'jumper',
          name: 'Navy jumper',
          type: ItemType.sweater,
          hex: '#1F2A44',
          colorName: 'Navy',
        ),
      );
      final today = container.read(wornTodayPhotoControllerProvider.notifier);
      await tester.runAsync(() => today.start());
      expect(
        container.read(wornTodayPhotoControllerProvider).selected,
        isNotEmpty,
      );

      await tester.runAsync(() => today.confirm());

      final state = container.read(wornTodayPhotoControllerProvider);
      expect(state.phase, WornPhase.result);
      expect(state.saving, isFalse);
      expect(state.message, contains('Nothing was logged'));
      expect(state.selected, isNotEmpty, reason: 'can be tried again');
    });
  });
}
