/// The two screens the worn photo adds, as a person meets them.
///
/// Each is driven through its real controller against a scripted server, and
/// checked at the narrowest phone width and the largest text size the app
/// supports, where a row that fits at 1.0 is the one that overflows.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/laundry/worn_today_photo_controller.dart';
import 'package:washing_advice/features/laundry/worn_today_photo_screen.dart';
import 'package:washing_advice/features/scan/worn_photo_controller.dart';
import 'package:washing_advice/features/scan/worn_photo_screen.dart';

import 'support/fixtures.dart';
import 'support/worn_fakes.dart';

void main() {
  late InMemoryWardrobeRepository repository;
  late WornGateway gateway;
  late ProviderContainer container;

  void setUpWith(List<Object> script, {int photos = 1}) {
    repository = InMemoryWardrobeRepository();
    gateway = WornGateway(script);
    container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(MemoryImageStore()),
        aiGatewayProvider.overrideWithValue(gateway),
        idGeneratorProvider.overrideWithValue(
          SequentialIdGenerator(prefix: 'g'),
        ),
        imageCaptureProvider.overrideWithValue(
          FixedImageCaptureSource([
            for (var i = 0; i < photos; i++)
              ScanImage(bytes: [...wornPng.bytes, i]),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
  }

  Future<void> show(
    WidgetTester tester,
    Widget screen, {
    double width = 320,
    double scale = 1.6,
  }) async {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('add from a photo of me', () {
    testWidgets('the start explains itself and offers both ways in', (
      tester,
    ) async {
      setUpWith([]);

      await show(tester, const WornPhotoScreen());

      expect(find.text('Choose photos'), findsOneWidget);
      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.textContaining('with you in it'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('progress counts the photos, then admits a slow server', (
      tester,
    ) async {
      setUpWith([
        [wornDetection()],
      ], photos: 2);
      gateway.hold = Completer<void>();
      await show(tester, const WornPhotoScreen());

      final running = container
          .read(wornPhotoControllerProvider.notifier)
          .start(fromGallery: true);
      await tester.pump();
      await tester.pump();

      expect(find.text('Photo 1 of 2'), findsOneWidget);
      expect(find.textContaining('waking up'), findsNothing);

      await tester.pump(wakingAfter);
      expect(find.textContaining('waking up'), findsOneWidget);
      expect(tester.takeException(), isNull);

      gateway.hold!.complete();
      await tester.pump();
      await tester.pump();
      await tester.runAsync(() => running);
      await tester.pumpAndSettle();
      expect(find.text('Add 1 garment'), findsOneWidget);
    });

    testWidgets('the review names each garment, its picture and its state', (
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
            kind: CutoutKind.box,
          ),
          wornDetection(
            type: ItemType.hat,
            hex: '#CC8822',
            colour: 'Mustard',
            name: 'Mustard hat',
            kind: null,
          ),
        ],
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
      await show(tester, const WornPhotoScreen());

      await tester.runAsync(
        () => container.read(wornPhotoControllerProvider.notifier).start(),
      );
      await tester.pumpAndSettle();

      expect(find.text('3 garments found'), findsOneWidget);
      expect(find.textContaining('already in your wardrobe'), findsWidgets);
      expect(
        find.textContaining('Looks like "My navy jumper"'),
        findsOneWidget,
      );
      expect(find.text('Black jeans'), findsOneWidget);
      expect(
        find.textContaining(
          'Includes some background — you can tidy it in the cutout editor.',
        ),
        findsOneWidget,
        reason: 'only the box picture says so; the outline one does not',
      );
      expect(find.textContaining('Cropped from your photo'), findsOneWidget);
      expect(find.text('Add 2 garments'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a photo with nothing in it is named, not hidden', (
      tester,
    ) async {
      setUpWith([
        <WornDetection>[],
        [wornDetection()],
      ], photos: 2);
      await show(tester, const WornPhotoScreen());

      await tester.runAsync(
        () => container
            .read(wornPhotoControllerProvider.notifier)
            .start(fromGallery: true),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Photo 1: No clothes were found'),
        findsOneWidget,
      );
      expect(find.text('1 garment found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('only failures says so and offers another go', (tester) async {
      setUpWith([const ScanFailure('Could not reach the server.')]);
      await show(tester, const WornPhotoScreen());

      await tester.runAsync(
        () => container.read(wornPhotoControllerProvider.notifier).start(),
      );
      await tester.pumpAndSettle();

      expect(find.text('No garments found'), findsOneWidget);
      expect(
        find.textContaining('Could not reach the server.'),
        findsOneWidget,
      );
      expect(find.text('Try other photos'), findsOneWidget);
    });

    testWidgets('adding finishes with the care-label prompt in words', (
      tester,
    ) async {
      setUpWith([
        [wornDetection()],
      ]);
      await show(tester, const WornPhotoScreen());
      await tester.runAsync(
        () => container.read(wornPhotoControllerProvider.notifier).start(),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(
        () =>
            container.read(wornPhotoControllerProvider.notifier).saveAccepted(),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 garment added'), findsOneWidget);
      expect(find.textContaining('scan its care label'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('worn today, from a photo', () {
    testWidgets('lists what it is wearing, then what it does not know', (
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
      ]);
      await repository.save(
        confidentItem(
          id: 'jumper',
          name: 'Blue jumper',
          type: ItemType.sweater,
          hex: '#1F2A44',
          colorName: 'Navy',
        ),
      );
      await show(tester, const WornTodayPhotoScreen());
      expect(find.text('Take a photo'), findsOneWidget);

      await tester.runAsync(
        () => container.read(wornTodayPhotoControllerProvider.notifier).start(),
      );
      await tester.pumpAndSettle();

      expect(find.text("You're wearing: Blue jumper"), findsOneWidget);
      expect(find.text('Not in your wardrobe — add it?'), findsOneWidget);
      expect(find.text('Mustard hat'), findsOneWidget);
      expect(find.text('Add it to my wardrobe'), findsOneWidget);
      expect(find.text('Log 1 and put it in the basket'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an uncertain match is offered unticked', (tester) async {
      setUpWith([
        [wornDetection()],
      ]);
      for (final id in ['a', 'b']) {
        await repository.save(
          confidentItem(
            id: id,
            name: 'Navy jumper $id',
            type: ItemType.sweater,
            hex: '#1F2A44',
            colorName: 'Navy',
          ),
        );
      }
      await show(tester, const WornTodayPhotoScreen());

      await tester.runAsync(
        () => container.read(wornTodayPhotoControllerProvider.notifier).start(),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Not sure'), findsOneWidget);
      expect(find.text('Tick what you wore'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
