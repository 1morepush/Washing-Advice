/// Re-cutting the whole wardrobe: what it touches, what it must not, and how it
/// behaves while the server is slow, busy or unwell.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/images/image_store.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/settings/cutouts_section.dart';
import 'package:washing_advice/features/wardrobe/redo_cutouts_controller.dart';

import '../support/fixtures.dart';

typedef Attempt = ({Uint8List? bytes, Duration? retryAfter});

final Attempt cut = (bytes: Uint8List.fromList([7, 7, 7]), retryAfter: null);
const Attempt refused = (bytes: null, retryAfter: null);

void main() {
  late InMemoryWardrobeRepository repository;
  late MemoryImageStore images;

  ProviderContainer build(AiGateway gateway) {
    final container = ProviderContainer(
      overrides: [
        wardrobeRepositoryProvider.overrideWithValue(repository),
        eventLogProvider.overrideWithValue(InMemoryEventLog()),
        imageStoreProvider.overrideWithValue(images),
        aiGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// A garment with a stored photograph and, optionally, an existing cutout.
  Future<WardrobeItem> garment(
    String id, {
    PhotoRole role = PhotoRole.front,
    String? cutoutName,
  }) async {
    final photoUri = await images.save(
      Uint8List.fromList([1, 2, 3]),
      name: '$id-${role.name}',
    );
    final cutoutUri = cutoutName == null
        ? null
        : await images.save(Uint8List.fromList([5]), name: cutoutName);
    final item = confidentItem(id: id, name: 'Garment $id').copyWith(
      photos: PhotoSet([
        ItemPhoto(
          uri: photoUri,
          role: role,
          capturedAt: DateTime.utc(2026, 1, 1),
          cutoutUri: cutoutUri,
        ),
      ]),
    );
    await repository.save(item);
    return item;
  }

  Future<String?> cutoutOf(String id) async =>
      (await repository.byId(ItemId(id)))!.photos.displayPhoto!.cutoutUri;

  setUp(() {
    repository = InMemoryWardrobeRepository();
    images = MemoryImageStore();
  });

  test('every plain garment is re-cut and the result is stored', () async {
    final gateway = _Gateway([cut, cut]);
    final container = build(gateway);
    await garment('a');
    await garment('b', cutoutName: 'b-front-old-cutout');

    await container.read(redoCutoutsProvider.notifier).run();

    final done = container.read(redoCutoutsProvider) as RedoFinished;
    expect(done.redone, 2);
    expect(done.kept, 0);
    expect(await cutoutOf('a'), isNotNull);
    expect(
      await images.read((await cutoutOf('b'))!),
      Uint8List.fromList([7, 7, 7]),
    );
    // The superseded file is not left behind.
    expect(await images.read('b-front-old-cutout'), isNull);
  });

  test('a cutout edited by hand is never sent and never replaced', () async {
    final gateway = _Gateway([cut]);
    final container = build(gateway);
    final item = await garment('a');
    final edited = await images.save(
      Uint8List.fromList([42]),
      name:
          '${cutoutNameFor(item.id, item.photos.displayPhoto!)}$handEditedSuffix',
    );
    await repository.save(
      item.copyWith(
        photos: item.photos.withCutout(item.photos.displayPhoto!.uri, edited),
      ),
    );
    await garment('b');

    await container.read(redoCutoutsProvider.notifier).run();

    final done = container.read(redoCutoutsProvider) as RedoFinished;
    expect(done.skippedHandEdited, 1);
    expect(done.redone, 1);
    expect(gateway.calls, 1, reason: 'only the automatic one was uploaded');
    expect(await cutoutOf('a'), edited);
    expect(await images.read(edited), Uint8List.fromList([42]));
  });

  test('a worn photograph is skipped', () async {
    final gateway = _Gateway([cut]);
    final container = build(gateway);
    await garment('worn', role: PhotoRole.worn);
    await garment('flat');

    await container.read(redoCutoutsProvider.notifier).run();

    final done = container.read(redoCutoutsProvider) as RedoFinished;
    expect(done.skippedWorn, 1);
    expect(done.redone, 1);
    expect(gateway.calls, 1);
    expect(await cutoutOf('worn'), isNull);
  });

  test('a failure does not stop the rest, and keeps the old cutout', () async {
    final gateway = _Gateway([refused, cut]);
    final container = build(gateway);
    await garment('first', cutoutName: 'first-front-old-cutout');
    await garment('second');
    final before = await cutoutOf('first');

    await container.read(redoCutoutsProvider.notifier).run();

    final done = container.read(redoCutoutsProvider) as RedoFinished;
    expect(done.kept, 1);
    expect(done.redone, 1);
    expect(await cutoutOf('first'), before);
    expect(await cutoutOf('second'), isNotNull);
  });

  test('a garment whose photograph is gone is kept, not fatal', () async {
    final container = build(_Gateway([cut]));
    final lost = await garment('lost');
    await images.delete(lost.photos.displayPhoto!.uri);
    await garment('fine');

    await container.read(redoCutoutsProvider.notifier).run();

    final done = container.read(redoCutoutsProvider) as RedoFinished;
    expect(done.kept, 1);
    expect(done.redone, 1);
  });

  test('a rate limit is waited out and the same garment retried', () async {
    final gateway = _Gateway([
      (bytes: null, retryAfter: const Duration(milliseconds: 30)),
      cut,
    ]);
    final container = build(gateway);
    await garment('a');
    final seen = <RedoCutoutsState>[];
    container.listen(redoCutoutsProvider, (_, next) => seen.add(next));

    await container.read(redoCutoutsProvider.notifier).run();

    expect(gateway.calls, 2);
    expect((container.read(redoCutoutsProvider) as RedoFinished).redone, 1);
    expect(
      seen.whereType<RedoRunning>().any((s) => s.waiting != null),
      isTrue,
      reason: 'the wait is visible, not a silent stall',
    );
  });

  test('a wait longer than the limit gives that garment up', () async {
    final gateway = _Gateway([
      (bytes: null, retryAfter: const Duration(hours: 1)),
      cut,
    ]);
    final container = build(gateway);
    await garment('a');
    await garment('b');

    await container.read(redoCutoutsProvider.notifier).run();

    final done = container.read(redoCutoutsProvider) as RedoFinished;
    expect(done.kept, 1);
    expect(done.redone, 1);
  });

  test('progress counts every garment, skipped or not', () async {
    final container = build(_Gateway([cut, cut]));
    await garment('a');
    await garment('worn', role: PhotoRole.worn);
    await garment('b');
    final seen = <RedoCutoutsState>[];
    container.listen(redoCutoutsProvider, (_, next) => seen.add(next));

    await container.read(redoCutoutsProvider.notifier).run();

    final running = seen.whereType<RedoRunning>().toList();
    expect(running.first.total, 3);
    expect(running.map((s) => s.finished), containsAllInOrder([0, 1, 2, 3]));
  });

  test(
    'cancelling stops after the garment in flight and drops its result',
    () async {
      final hold = Completer<Attempt>();
      final gateway = _Gateway([], hold: hold);
      final container = build(gateway);
      await garment('a', cutoutName: 'a-front-old-cutout');
      await garment('b');
      final before = await cutoutOf('a');
      final controller = container.read(redoCutoutsProvider.notifier);

      final running = controller.run();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(gateway.calls, 1);
      controller.cancel();
      expect(
        (container.read(redoCutoutsProvider) as RedoRunning).cancelling,
        isTrue,
      );
      hold.complete(cut);
      await running;

      final done = container.read(redoCutoutsProvider) as RedoFinished;
      expect(done.cancelled, isTrue);
      expect(gateway.calls, 1, reason: 'the second garment was never sent');
      expect(
        await cutoutOf('a'),
        before,
        reason: 'a stopped run changes nothing more',
      );
    },
  );

  test('cancelling interrupts a rate-limit wait at once', () async {
    final gateway = _Gateway([
      (bytes: null, retryAfter: const Duration(seconds: 90)),
    ]);
    final container = build(gateway);
    await garment('a');
    final controller = container.read(redoCutoutsProvider.notifier);

    final running = controller.run();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.cancel();
    await running.timeout(const Duration(seconds: 2));

    expect(
      (container.read(redoCutoutsProvider) as RedoFinished).cancelled,
      isTrue,
    );
  });

  test(
    'skipReason reads the marker, and treats old cutouts as automatic',
    () async {
      final plain = await garment('p', cutoutName: 'p-front-cutout');
      expect(RedoCutoutsController.skipReason(plain), isNull);
      expect(isHandEditedCutout('x-front-1-cutout'), isFalse);
      expect(isHandEditedCutout('x-front-1-cutout-edited'), isTrue);
      expect(isHandEditedCutout(null), isFalse);
    },
  );

  group('the settings section', () {
    Future<void> show(
      WidgetTester tester,
      RedoCutoutsState state, {
      double width = 320,
      double scale = 1.6,
    }) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            redoCutoutsProvider.overrideWith((ref) => _Fixed(ref, state)),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1200),
                textScaler: TextScaler.linear(scale),
              ),
              child: const Scaffold(
                body: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: CutoutsSection(),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('offers the action when idle, with nothing overflowing', (
      tester,
    ) async {
      await show(tester, const RedoIdle());

      expect(find.text('Redo cutouts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows progress and a Cancel at 320 px and 1.6x text', (
      tester,
    ) async {
      await show(tester, const RedoRunning(finished: 3, total: 13));

      expect(find.text('Redoing cutouts: 3 of 13'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says it is waiting, and that it is stopping', (tester) async {
      await show(
        tester,
        const RedoRunning(
          finished: 3,
          total: 13,
          waiting: Duration(seconds: 12),
        ),
      );
      expect(find.textContaining('continuing in 12 s'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says it is stopping once Cancel is pressed', (tester) async {
      await show(
        tester,
        const RedoRunning(finished: 3, total: 13, cancelling: true),
      );
      expect(find.textContaining('Stopping'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the summary names what was left alone', (tester) async {
      await show(
        tester,
        const RedoFinished(
          redone: 8,
          kept: 2,
          skippedHandEdited: 3,
          skippedWorn: 1,
          cancelled: false,
          total: 10,
        ),
      );

      expect(find.textContaining('8 cutouts redone'), findsOneWidget);
      expect(
        find.textContaining('3 you edited by hand were left alone'),
        findsOneWidget,
      );
      expect(find.textContaining('1 worn photo was skipped'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _Fixed extends RedoCutoutsController {
  _Fixed(super.ref, RedoCutoutsState initial) {
    state = initial;
  }
}

/// A gateway that answers each cutout from a script, in order. When the script
/// runs out the last answer repeats; [hold] makes the first call wait.
class _Gateway extends AiGateway {
  _Gateway(this._script, {this.hold})
    : super(baseUrl: Uri.parse('http://test.invalid/'));

  final List<Attempt> _script;
  final Completer<Attempt>? hold;
  int calls = 0;

  @override
  Future<Attempt> cutoutAttempt(ScanImage image) async {
    final index = calls++;
    if (hold != null && index == 0) return hold!.future;
    if (_script.isEmpty) return cut;
    return _script[index < _script.length ? index : _script.length - 1];
  }
}
