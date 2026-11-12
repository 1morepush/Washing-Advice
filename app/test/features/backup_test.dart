/// Backup and restore, against a real (in-memory) database and image store.
///
/// The core tests pin the format and the merge rules with lists. These pin the
/// part only the app can get wrong: that what comes off Drift and the image
/// store goes back onto a different Drift and image store equal, that a
/// restore which fails changes nothing, and what the Settings group says.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/core/theme.dart' show Appearance;
import 'package:washing_advice/data/backup/backup_files_port.dart';
import 'package:washing_advice/data/drift/database.dart';
import 'package:washing_advice/data/drift/drift_event_log.dart';
import 'package:washing_advice/data/drift/drift_wardrobe_repository.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/backup/backup_service.dart';
import 'package:washing_advice/features/laundry/evening_nudge.dart';
import 'package:washing_advice/main.dart';

import '../support/fixtures.dart';
import '../support/recording_nudges.dart';

/// Hands over whatever it is told to, and remembers what it was given.
class FakeBackupFiles implements BackupFiles {
  final saved = <({Uint8List bytes, String name})>[];
  PickedBackupFile? toPick;
  BackupHandover handover = BackupHandover.done;

  @override
  Future<BackupHandover> save(
    Uint8List bytes, {
    required String fileName,
  }) async {
    saved.add((bytes: bytes, name: fileName));
    return handover;
  }

  @override
  Future<PickedBackupFile?> pick() async => toPick;
}

/// An image store that fails on the nth save.
class FailingImageStore extends MemoryImageStore {
  FailingImageStore({required this.failOn});

  final int failOn;
  int _saves = 0;

  @override
  Future<String> save(Uint8List bytes, {required String name}) async {
    if (++_saves >= failOn) throw StateError('disk full');
    return super.save(bytes, name: name);
  }
}

Uint8List fakePng(int seed) => Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  for (var i = 0; i < 40; i++) (seed * 7 + i) & 0xFF,
]);

/// A phone: a database, a picture store and preferences.
class Phone {
  Phone._(this.db, this.images, this.settings);

  static Future<Phone> open({
    MemoryImageStore? images,
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    return Phone._(
      AppDatabase(NativeDatabase.memory()),
      images ?? MemoryImageStore(),
      SettingsStore(await SharedPreferences.getInstance()),
    );
  }

  final AppDatabase db;
  final MemoryImageStore images;
  final SettingsStore settings;

  late final service = BackupService(
    database: db,
    images: images,
    settings: settings,
    appVersion: '0.34.0',
  );

  Future<BackupSnapshot> snapshot() => service.snapshot();

  Future<void> close() => db.close();
}

/// Writes [items] and friends into [phone] through the real repositories.
Future<void> fill(
  Phone phone, {
  List<WardrobeItem> items = const [],
  List<WardrobeEvent> events = const [],
  List<Outfit> outfits = const [],
  List<Listing> listings = const [],
}) async {
  await phone.db.batch((batch) {
    batch.insertAllOnConflictUpdate(phone.db.items, [
      for (final item in items) rowFor(item),
    ]);
    batch.insertAllOnConflictUpdate(phone.db.outfits, [
      for (final o in outfits) outfitRowFor(o),
    ]);
    batch.insertAllOnConflictUpdate(phone.db.listings, [
      for (final l in listings) listingRowFor(l),
    ]);
  });
  await DriftEventLog(phone.db).appendAll(events);
}

Listing listing(
  String id, {
  DateTime? at,
  List<ListingPhoto> photos = const [],
}) => Listing(
  id: ListingId(id),
  createdAt: DateTime.utc(2026, 10, 1),
  updatedAt: at ?? DateTime.utc(2026, 10, 1),
  title: 'Nike crewneck',
  photos: photos,
);

Outfit outfit(String id, {DateTime? at}) => Outfit(
  id: OutfitId(id),
  name: 'Saturday',
  itemIds: const [ItemId('tee'), ItemId('jeans')],
  occasion: Occasion.everyday,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: at ?? DateTime.utc(2026, 8, 1),
);

/// A garment with a stored photograph and cutout, saved in [phone]'s store.
Future<WardrobeItem> photographedItem(
  Phone phone,
  String id, {
  required int seed,
  DateTime? at,
}) async {
  final photo = await phone.images.save(fakePng(seed), name: '$id-front');
  final cutout = await phone.images.save(fakePng(seed + 100), name: '$id-cut');
  return confidentItem(id: id, name: 'Garment $id').copyWith(
    photos: PhotoSet([
      ItemPhoto(
        uri: photo,
        cutoutUri: cutout,
        role: PhotoRole.front,
        capturedAt: DateTime.utc(2026, 2, 1),
        width: 300,
        height: 400,
        isPrimary: true,
      ),
    ]),
    updatedAt: at ?? DateTime.utc(2026, 8, 5),
  );
}

/// Every image a snapshot's records point at, as bytes by role, so two phones
/// with different URIs can be compared.
Future<Map<String, Uint8List?>> picturesOf(
  Phone phone,
  BackupSnapshot snapshot,
) async => {
  for (final item in snapshot.items)
    for (final photo in item.photos.photos) ...{
      '${item.id.value}/photo': await phone.images.read(photo.uri),
      '${item.id.value}/cutout': photo.cutoutUri == null
          ? null
          : await phone.images.read(photo.cutoutUri!),
    },
  for (final l in snapshot.listings)
    for (final (i, p) in l.photos.indexed)
      '${l.id.value}/$i': await phone.images.read(p.uri),
};

ItemWorn wornEvent(String item, DateTime at) => ItemWorn(
  id: EventId('worn-$item-${at.microsecondsSinceEpoch}'),
  itemId: ItemId(item),
  occurredAt: at,
);

ItemWashed washedEvent(String item, DateTime at) => ItemWashed(
  id: EventId('washed-$item-${at.microsecondsSinceEpoch}'),
  itemId: ItemId(item),
  occurredAt: at,
  record: LaundryRecord(washedAt: at),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Phone source;

  setUp(() async {
    source = await Phone.open(
      prefs: {
        'washerBrand': 'Bosch',
        'splitDrying': true,
        'appearance': 'amoled',
        // Things that must never travel.
        'syncToken': 'secret-token-${'x' * 30}',
        'backendUrl': 'http://192.168.1.50:8000',
        'syncCursorRemote': '2026-08-01T00:00:00.000Z',
        'eveningNudgeMinutes': 20 * 60,
      },
    );

    final a = await photographedItem(source, 'a', seed: 1);
    final b = await photographedItem(source, 'b', seed: 2);
    final gone = confidentItem(
      id: 'gone',
      name: 'Gone',
    ).copyWith(lifecycle: LifecycleState.removed);
    final listed = await source.images.save(fakePng(9), name: 'listing-cover');
    await fill(
      source,
      items: [a, b, gone],
      events: [
        wornEvent('a', DateTime.utc(2026, 8, 1)),
        wornEvent('a', DateTime.utc(2026, 8, 2)),
        washedEvent('b', DateTime.utc(2026, 8, 3)),
      ],
      outfits: [outfit('o1')],
      listings: [
        listing(
          'l1',
          photos: [
            ListingPhoto(uri: listed, shot: ListingShot.cover),
            // The same file as a garment's own: stored once.
            ListingPhoto(
              uri: a.photos.photos.first.uri,
              shot: ListingShot.other,
            ),
          ],
        ),
      ],
    );
  });

  tearDown(() => source.close());

  group('saving', () {
    test('builds an archive holding everything on the phone', () async {
      final built = await source.service.create();

      expect(
        built.manifest.counts,
        const BackupCounts(
          items: 2,
          deletedItems: 1,
          events: 3,
          outfits: 1,
          listings: 1,
          images: 5,
        ),
      );
      expect(built.manifest.appVersion, '0.34.0');
    });

    test('leaves out the sync token and the server address', () async {
      final built = await source.service.create();
      final archive = ZipDecoder().decodeBytes(built.bytes);
      final text = [
        for (final f in archive)
          if (!f.name.startsWith('images/')) utf8.decode(f.readBytes()!),
      ].join('\n');

      for (final secret in [
        'secret-token',
        '192.168.1.50',
        'syncToken',
        'backendUrl',
        'syncCursor',
        'eveningNudge',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      expect(text, contains('"washerBrand":"Bosch"'));
    });
  });

  group('restoring onto a fresh phone', () {
    test('gives an equal wardrobe, with every picture', () async {
      final built = await source.service.create();
      final before = await source.snapshot();

      final fresh = await Phone.open();
      addTearDown(fresh.close);
      final outcome = await fresh.service.restore(
        BackupReader.open(built.bytes),
        RestoreMode.replace,
      );
      final after = await fresh.snapshot();

      expect(outcome.imagesWritten, 5);
      expect(outcome.imagesMissing, 0);
      expect(
        after.events.map((e) => e.toJson()),
        before.events.map((e) => e.toJson()),
      );
      expect(after.outfits, before.outfits);
      expect(after.items.length, before.items.length);
      expect(
        [for (final i in after.items) i.id.value]..sort(),
        [for (final i in before.items) i.id.value]..sort(),
      );

      // Equal apart from where the pictures now live.
      WardrobeItem unpictured(WardrobeItem i) =>
          i.copyWith(photos: PhotoSet.empty);
      Map<String, WardrobeItem> byId(BackupSnapshot s) => {
        for (final i in s.items) i.id.value: unpictured(i),
      };
      expect(byId(after), byId(before));

      expect(await picturesOf(fresh, after), await picturesOf(source, before));
      // The listing still shares the garment's file, rather than a copy.
      final listing = after.listings.single;
      final garmentA = after.items.firstWhere((i) => i.id.value == 'a');
      expect(listing.photos.last.uri, garmentA.photos.photos.first.uri);
    });

    test('brings the portable settings, and only those', () async {
      final built = await source.service.create();
      final fresh = await Phone.open(
        prefs: {'syncToken': 'fresh-token', 'backendUrl': 'https://mine'},
      );
      addTearDown(fresh.close);

      await fresh.service.restore(
        BackupReader.open(built.bytes),
        RestoreMode.replace,
      );

      expect(fresh.settings.washerBrand, 'Bosch');
      expect(fresh.settings.splitDrying, isTrue);
      expect(fresh.settings.appearance, Appearance.amoled);
      expect(fresh.settings.syncToken, 'fresh-token');
      expect(fresh.settings.backendUrl, 'https://mine');
      expect(fresh.settings.nudgeMinutes, isNull);
    });

    test('forgets the sync cursors, so the next sync sends it all', () async {
      final built = await source.service.create();
      final fresh = await Phone.open(
        prefs: {
          'syncCursorRemote': '2026-08-01T00:00:00.000Z',
          'syncCursorLocal': '2026-08-01T00:00:00.000Z',
        },
      );
      addTearDown(fresh.close);

      await fresh.service.restore(
        BackupReader.open(built.bytes),
        RestoreMode.merge,
      );

      expect(fresh.settings.syncedAt, isNull);
      expect(fresh.settings.pushedAt, isNull);
    });
  });

  group('merge and replace on a phone that has things', () {
    late Phone target;
    late Uint8List backup;

    setUp(() async {
      backup = (await source.service.create()).bytes;

      target = await Phone.open(
        prefs: {'washerBrand': 'LG', 'appearance': 'dark'},
      );
      final mine = await photographedItem(target, 'mine', seed: 50);
      // `a` exists here too, but edited later than the backup.
      final newerA = (await photographedItem(
        target,
        'a',
        seed: 60,
        at: DateTime.utc(2026, 9, 1),
      )).copyWith(name: 'Edited later');
      await fill(
        target,
        items: [mine, newerA],
        events: [wornEvent('mine', DateTime.utc(2026, 9, 2))],
        outfits: [outfit('o-mine', at: DateTime.utc(2026, 9, 1))],
        listings: [listing('l-mine')],
      );
    });

    tearDown(() => target.close());

    test('merge adds, keeps the newer, and deletes nothing', () async {
      final outcome = await target.service.restore(
        BackupReader.open(backup),
        RestoreMode.merge,
      );
      final after = await target.snapshot();
      final byId = {for (final i in after.items) i.id.value: i};

      expect(byId.keys, unorderedEquals(['mine', 'a', 'b', 'gone']));
      expect(byId['a']!.name, 'Edited later');
      expect(outcome.plan.itemCounts.added, 1);
      expect(outcome.plan.itemCounts.kept, 1);
      expect(after.events, hasLength(4));
      expect(
        after.outfits.map((o) => o.id.value),
        unorderedEquals(['o1', 'o-mine']),
      );
      expect(
        after.listings.map((l) => l.id.value),
        unorderedEquals(['l1', 'l-mine']),
      );

      // The kept garment kept its own pictures.
      expect(
        await target.images.read(byId['a']!.photos.photos.first.uri),
        fakePng(60),
      );
      // The new ones arrived with theirs.
      expect(
        await target.images.read(byId['b']!.photos.photos.first.uri),
        fakePng(2),
      );
      // The wear logged here for `a`... counters follow the history.
      expect(byId['a']!.usage.timesWorn, 2);

      // Preferences already chosen here are not overwritten by a merge.
      expect(target.settings.washerBrand, 'LG');
      expect(target.settings.appearance, Appearance.dark);
      // One it had not chosen is filled in.
      expect(target.settings.splitDrying, isTrue);
    });

    test('merging the same backup again changes nothing', () async {
      await target.service.restore(
        BackupReader.open(backup),
        RestoreMode.merge,
      );
      final once = await target.snapshot();

      final again = await target.service.restore(
        BackupReader.open(backup),
        RestoreMode.merge,
      );
      final twice = await target.snapshot();

      expect(again.plan.isEmpty, isTrue);
      expect(again.imagesWritten, 0);
      expect(
        twice.items.map((i) => i.toJson()),
        once.items.map((i) => i.toJson()),
      );
      expect(twice.events, hasLength(once.events.length));
    });

    test('replace makes the phone the backup, and clears the rest', () async {
      final before = target.images.length;
      expect(before, 4);

      final outcome = await target.service.restore(
        BackupReader.open(backup),
        RestoreMode.replace,
      );
      final after = await target.snapshot();

      expect(
        after.items.map((i) => i.id.value),
        unorderedEquals(['a', 'b', 'gone']),
      );
      expect(
        after.items.firstWhere((i) => i.id.value == 'a').name,
        isNot('Edited later'),
      );
      expect(after.events, hasLength(3));
      expect(after.outfits.map((o) => o.id.value), ['o1']);
      expect(after.listings.map((l) => l.id.value), ['l1']);
      expect(outcome.plan.itemCounts.removed, 1);

      // The pictures the old records used are gone; only the backup's remain.
      expect(target.images.length, 5);
      expect(target.settings.washerBrand, 'Bosch');
      expect(target.settings.appearance, Appearance.amoled);
    });
  });

  group('a restore that fails', () {
    late Phone target;
    late Uint8List backup;
    late Map<String, Object?> untouched;

    Future<Map<String, Object?>> everything(Phone p) async {
      final s = await p.snapshot();
      return {
        'items': [for (final i in s.items) i.toJson()],
        'events': [for (final e in s.events) e.toJson()],
        'outfits': [for (final o in s.outfits) o.toJson()],
        'listings': [for (final l in s.listings) l.toJson()],
        'images': p.images.length,
        'washer': p.settings.washerBrand,
      };
    }

    setUp(() async {
      backup = (await source.service.create()).bytes;
    });

    Future<Phone> populated({MemoryImageStore? images}) async {
      final p = await Phone.open(images: images, prefs: {'washerBrand': 'LG'});
      await fill(
        p,
        items: [await photographedItem(p, 'mine', seed: 50)],
        events: [wornEvent('mine', DateTime.utc(2026, 9, 2))],
        outfits: [outfit('o-mine')],
        listings: [listing('l-mine')],
      );
      return p;
    }

    for (final mode in RestoreMode.values) {
      test(
        'in the transaction rolls every record back (${mode.name})',
        () async {
          target = await populated();
          addTearDown(target.close);
          untouched = await everything(target);
          target.service.afterWritesForTest = () async =>
              throw StateError('power cut');

          await expectLater(
            target.service.restore(BackupReader.open(backup), mode),
            throwsA(
              isA<RestoreFailed>().having(
                (e) => e.message,
                'message',
                contains('nothing on this phone was changed'),
              ),
            ),
          );

          expect(await everything(target), untouched);
        },
      );

      test(
        'while writing pictures changes nothing either (${mode.name})',
        () async {
          final store = FailingImageStore(failOn: 3);
          target = await populated(images: store);
          addTearDown(target.close);
          untouched = await everything(target);

          await expectLater(
            target.service.restore(BackupReader.open(backup), mode),
            throwsA(isA<RestoreFailed>()),
          );

          // The pictures written before the failure are removed again, and the
          // ones that were already there are left alone.
          expect(await everything(target), untouched);
        },
      );
    }

    test('a damaged file is refused before the service is involved', () async {
      target = await populated();
      addTearDown(target.close);
      untouched = await everything(target);

      expect(
        () => BackupReader.open(
          Uint8List.sublistView(backup, 0, backup.length - 40),
        ),
        throwsA(isA<BackupException>()),
      );
      expect(await everything(target), untouched);
    });
  });

  group('the Backup group in Settings', () {
    late Phone phone;
    late FakeBackupFiles files;

    Future<void> open(
      WidgetTester tester, {
      Size size = const Size(400, 900),
      double scale = 1,
      DateTime? lastBackup,
      int? garmentsAtLast,
      bool withItems = true,
    }) async {
      phone = (await tester.runAsync(
        () => Phone.open(
          prefs: {
            'lastBackupAt': ?lastBackup?.toUtc().toIso8601String(),
            'garmentsAtLastBackup': ?garmentsAtLast,
          },
        ),
      ))!;
      addTearDown(() async => tester.runAsync(phone.close));
      files = FakeBackupFiles();

      if (withItems) {
        await tester.runAsync(() async {
          final a = await photographedItem(phone, 'a', seed: 1);
          await fill(
            phone,
            items: [
              a,
              confidentItem(id: 'b', name: 'Garment b'),
            ],
            events: [wornEvent('a', DateTime.utc(2026, 8, 1))],
          );
        });
      }

      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(phone.db),
            imageStoreProvider.overrideWithValue(phone.images),
            settingsStoreProvider.overrideWithValue(phone.settings),
            wardrobeRepositoryProvider.overrideWithValue(
              DriftWardrobeRepository(phone.db),
            ),
            outfitRepositoryProvider.overrideWithValue(
              InMemoryOutfitRepository(),
            ),
            eventLogProvider.overrideWithValue(InMemoryEventLog()),
            backupFilesProvider.overrideWithValue(files),
            nudgesProvider.overrideWithValue(RecordingNudges()),
          ],
          child: const WashingAdviceApp(initialLocation: '/settings'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save a backup'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }

    /// Lets real async work (the database) finish, then redraws.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('says there is no backup, and nudges, when there never was', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('No backup yet.'), findsOneWidget);
      expect(find.textContaining('lives only on this device'), findsOneWidget);
    });

    testWidgets('says nothing about an empty wardrobe', (tester) async {
      await open(tester, withItems: false);

      expect(find.text('No backup yet.'), findsOneWidget);
      expect(find.textContaining('lives only on this device'), findsNothing);
    });

    testWidgets('shows when the last backup was, and is quiet when recent', (
      tester,
    ) async {
      await open(
        tester,
        lastBackup: DateTime.now().subtract(const Duration(days: 3)),
        garmentsAtLast: 1,
      );

      expect(find.text('Last backup 3 days ago.'), findsOneWidget);
      expect(find.textContaining('has grown'), findsNothing);
      expect(find.textContaining('lives only'), findsNothing);
    });

    testWidgets('nudges when it is over a month old and the wardrobe grew', (
      tester,
    ) async {
      await open(
        tester,
        lastBackup: DateTime.now().subtract(const Duration(days: 45)),
        garmentsAtLast: 1,
      );

      expect(find.text('Last backup 45 days ago.'), findsOneWidget);
      expect(
        find.textContaining('has grown since the last backup'),
        findsOneWidget,
      );
    });

    testWidgets('does not nudge about an old backup of an unchanged wardrobe', (
      tester,
    ) async {
      await open(
        tester,
        lastBackup: DateTime.now().subtract(const Duration(days: 45)),
        garmentsAtLast: 2,
      );

      expect(find.textContaining('has grown'), findsNothing);
    });

    for (final (width, scale) in [(320.0, 1.0), (320.0, 1.6), (400.0, 1.6)]) {
      testWidgets('fits ${width.toInt()} dp wide at ${scale}x text', (
        tester,
      ) async {
        await open(
          tester,
          size: Size(width, 700),
          scale: scale,
          lastBackup: DateTime.now().subtract(const Duration(days: 45)),
          garmentsAtLast: 1,
        );

        await tester.tap(find.text('Save a backup'));
        await settle(tester);

        expect(find.text('Backup saved'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'Save a backup hands over a named file and says what is in it',
      (tester) async {
        await open(tester);

        await tester.tap(find.text('Save a backup'));
        await settle(tester);

        expect(files.saved, hasLength(1));
        expect(
          files.saved.single.name,
          matches(RegExp(r'^washing-advice-backup-\d{4}-\d{2}-\d{2}\.zip$')),
        );
        expect(find.text('Backup saved'), findsOneWidget);
        expect(
          find.textContaining('2 garments, 2 photos, 1 history entry'),
          findsOneWidget,
        );
        expect(find.textContaining(' KB'), findsOneWidget);
        // The line above the buttons moves on at once.
        expect(find.text('Last backup just now.'), findsOneWidget);
        expect(find.textContaining('lives only'), findsNothing);
        expect(phone.settings.lastBackupAt, isNotNull);
        expect(phone.settings.garmentsAtLastBackup, 2);
      },
    );

    testWidgets('a cancelled save is not recorded as a backup', (tester) async {
      await open(tester);
      files.handover = BackupHandover.cancelled;

      await tester.tap(find.text('Save a backup'));
      await settle(tester);

      expect(find.text('Nothing was saved.'), findsOneWidget);
      expect(find.text('No backup yet.'), findsOneWidget);
      expect(phone.settings.lastBackupAt, isNull);
    });

    testWidgets(
      'Restore refuses a damaged file in words, and changes nothing',
      (tester) async {
        await open(tester);
        files.toPick = PickedBackupFile(
          name: 'broken.zip',
          bytes: Uint8List.fromList(utf8.encode('not a zip')),
        );

        await tester.tap(find.text('Restore from a backup'));
        await settle(tester);

        expect(find.text('That file could not be restored'), findsOneWidget);
        expect(find.textContaining('cut short'), findsOneWidget);
        expect((await tester.runAsync(phone.snapshot))!.items, hasLength(2));
      },
    );

    testWidgets('Restore says plainly when the backup is from a newer app', (
      tester,
    ) async {
      await open(tester);
      final built = (await tester.runAsync(() => source.service.create()))!;
      final archive = ZipDecoder().decodeBytes(built.bytes);
      final out = Archive();
      for (final f in archive) {
        if (f.name == 'manifest.json') {
          final m =
              jsonDecode(utf8.decode(f.readBytes()!)) as Map<String, Object?>;
          m['formatVersion'] = 99;
          out.add(ArchiveFile.string(f.name, jsonEncode(m)));
        } else {
          out.add(ArchiveFile.noCompress(f.name, f.size, f.readBytes()!));
        }
      }
      files.toPick = PickedBackupFile(
        name: 'future.zip',
        bytes: Uint8List.fromList(ZipEncoder().encodeBytes(out)),
      );

      await tester.tap(find.text('Restore from a backup'));
      await settle(tester);

      expect(
        find.textContaining('newer version of Washing Advice'),
        findsOneWidget,
      );
    });

    testWidgets('Restore shows what is in the file, then merges by default', (
      tester,
    ) async {
      await open(tester, withItems: false);
      final built = (await tester.runAsync(() => source.service.create()))!;
      files.toPick = PickedBackupFile(name: 'mine.zip', bytes: built.bytes);

      await tester.tap(find.text('Restore from a backup'));
      await settle(tester);

      expect(find.text('Restore this backup?'), findsOneWidget);
      expect(find.text('mine.zip'), findsOneWidget);
      expect(find.textContaining('Holds 2 garments, 5 photos'), findsOneWidget);
      expect(find.textContaining('version 0.34.0'), findsOneWidget);
      expect(find.text('Merge (recommended)'), findsOneWidget);
      expect(find.textContaining('Would add 2 garments'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await settle(tester);

      expect(find.text('Merged'), findsOneWidget);
      expect(find.textContaining('Garments: 2 added'), findsOneWidget);
      final after = (await tester.runAsync(phone.snapshot))!;
      expect(
        after.items.map((i) => i.id.value),
        containsAll(['a', 'b', 'gone']),
      );
    });

    testWidgets(
      'Replace asks a second time, says what is lost, and can be refused',
      (tester) async {
        await open(tester);
        final built = (await tester.runAsync(() => source.service.create()))!;
        files.toPick = PickedBackupFile(name: 'mine.zip', bytes: built.bytes);

        await tester.tap(find.text('Restore from a backup'));
        await settle(tester);
        await tester.tap(find.text('Replace everything'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
        await settle(tester);

        expect(find.text('Replace everything?'), findsOneWidget);
        expect(find.textContaining('cannot be undone'), findsOneWidget);
        expect(
          find.textContaining('This wardrobe has 2 garments'),
          findsOneWidget,
        );

        await tester.tap(find.text('Cancel'));
        await settle(tester);

        expect(find.text('Wardrobe replaced'), findsNothing);
        expect((await tester.runAsync(phone.snapshot))!.events, hasLength(1));
      },
    );

    testWidgets('Replace, once confirmed, reports its numbers', (tester) async {
      await open(tester);
      final built = (await tester.runAsync(() => source.service.create()))!;
      files.toPick = PickedBackupFile(name: 'mine.zip', bytes: built.bytes);

      await tester.tap(find.text('Restore from a backup'));
      await settle(tester);
      await tester.tap(find.text('Replace everything'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Replace everything'));
      await settle(tester);

      expect(find.text('Wardrobe replaced'), findsOneWidget);
      expect(find.textContaining('Garments:'), findsOneWidget);
      expect((await tester.runAsync(phone.snapshot))!.events, hasLength(3));
    });

    testWidgets('both restore dialogs fit 320 dp at 1.6x text', (tester) async {
      await open(tester, size: const Size(320, 640), scale: 1.6);
      final built = (await tester.runAsync(() => source.service.create()))!;
      files.toPick = PickedBackupFile(name: 'mine.zip', bytes: built.bytes);

      await tester.tap(find.text('Restore from a backup'));
      await settle(tester);
      expect(find.text('Restore this backup?'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Replace everything'));
      await tester.tap(find.text('Replace everything'));
      await tester.pump();
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Continue'));
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await settle(tester);
      expect(find.text('Replace everything?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
