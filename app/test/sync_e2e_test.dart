/// Two devices, one real server.
///
/// Every other sync test uses a fake on one side or the other. This one starts
/// the actual FastAPI service and drives two independent `SyncEngine`s against
/// it, because the failure this is really guarding against is a *wire* failure
/// — a field name that differs between Dart's `toJson` and Python's camelCase
/// aliasing, a timestamp format one side cannot parse, a cursor that skips a
/// record. Unit tests on both sides pass happily while that is broken.
///
/// Skipped when `uv` is not on the PATH, so a Flutter-only checkout still has
/// a green suite. CI runs it in a job that has both toolchains, which is the
/// only place the skip would hide something.
@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/api/http_sync_remote.dart';

void main() {
  // Guarded rather than assumed. A Flutter-only checkout has no `uv`, and a
  // suite that fails there would train people to ignore a red bar. CI runs
  // these in a job that has both toolchains, which is the only place where
  // skipping would hide a real failure.
  final missingUv = _uvIsUnavailable();

  group('sync, end to end', skip: missingUv, () {
    _tests();
  });
}

String? _uvIsUnavailable() {
  try {
    final found = Process.runSync('uv', ['--version']);
    if (found.exitCode == 0) return null;
  } on Exception {
    // Falls through to the skip reason below.
  }
  return 'needs `uv` on the PATH to start the server';
}

void _tests() {
  late Process server;
  late Uri baseUrl;

  setUpAll(() async {
    final serverDirectory = _findServerDirectory();

    // Port 0 lets the OS choose, but uvicorn does not report the chosen port
    // in a machine-readable way, so a port is picked here by binding and
    // immediately releasing. A small race remains and is worth the simplicity.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    server = await Process.start(
      'uv',
      [
        'run',
        'uvicorn',
        'app.main:app',
        '--host',
        '127.0.0.1',
        '--port',
        '$port',
        '--log-level',
        'warning',
      ],
      workingDirectory: serverDirectory,
      environment: {
        // In memory, so the suite leaves no database behind and each run
        // starts from nothing.
        'SYNC_DB_PATH': ':memory:',
        'SYNC_ENABLED': 'true',
        'VISION_PROVIDER': 'fake',
      },
    );
    // Drained so the child never blocks on a full pipe; kept for the failure
    // message, because "the server did not start" with no output is useless.
    final output = <String>[];
    server.stdout.transform(utf8.decoder).listen(output.add);
    server.stderr.transform(utf8.decoder).listen(output.add);

    baseUrl = Uri.parse('http://127.0.0.1:$port/');
    await _waitForHealth(baseUrl, output);
  });

  tearDownAll(() => server.kill());

  /// One device: its own storage, its own cursor, the same account.
  ({SyncEngine engine, InMemoryWardrobeRepository items, InMemoryEventLog log})
  device(String token) {
    final items = InMemoryWardrobeRepository();
    final log = InMemoryEventLog();
    return (
      engine: SyncEngine(
        items: items,
        events: log,
        remote: HttpSyncRemote(baseUrl: baseUrl, token: token),
        cursor: InMemorySyncCursor(),
      ),
      items: items,
      log: log,
    );
  }

  test('an item saved on one device arrives on the other', () async {
    final token = _token('basic');
    final a = device(token);
    final b = device(token);

    await a.items.save(_item(id: 'tee', name: 'White tee'));
    expect((await a.engine.sync()).succeeded, isTrue);

    expect((await b.engine.sync()).succeeded, isTrue);
    final arrived = await b.items.byId(const ItemId('tee'));
    expect(arrived, isNotNull);
    expect(arrived!.name, 'White tee');
  });

  test('an item survives the round trip byte for byte', () async {
    // The wire test. Anything the Python layer quietly reshapes — a dropped
    // null, a renamed key, a truncated timestamp — shows up here and nowhere
    // else.
    final token = _token('fidelity');
    final a = device(token);
    final b = device(token);

    final original = _item(id: 'jumper', name: 'Wool jumper').copyWith(
      brand: Confident.fromUser('Uniqlo'),
      purchase: PurchaseInfo(priceMinorUnits: 5990, currencyCode: 'EUR'),
      seasons: {Season.winter, Season.autumn},
      tags: {'work', 'favourite'},
      notes: 'the itchy one',
    );
    await a.items.save(original);
    await a.engine.sync();

    await b.engine.sync();
    final arrived = (await b.items.byId(const ItemId('jumper')))!;
    expect(arrived.toJson(), original.toJson());
  });

  test('wears recorded on one device reach the other', () async {
    final token = _token('events');
    final a = device(token);
    final b = device(token);

    await a.items.save(_item(id: 'tee', name: 'White tee'));
    await a.log.append(_worn('e1', DateTime.utc(2026, 8, 1)));
    await a.engine.sync();
    await b.engine.sync();

    expect(await b.log.all(), hasLength(1));
    // And the counters were rebuilt from the log rather than trusted from the
    // item, which is the whole reason events are pulled before items reconcile.
    expect((await b.items.byId(const ItemId('tee')))!.usage.timesWorn, 1);
  });

  test('two devices wearing the same garment do not lose a wear', () async {
    // The case a naive "latest wins" would get wrong: both devices recorded a
    // real wear, and the truth is the union.
    final token = _token('union');
    final a = device(token);
    final b = device(token);

    await a.items.save(_item(id: 'tee', name: 'White tee'));
    await a.engine.sync();
    await b.engine.sync();

    await a.log.append(_worn('a1', DateTime.utc(2026, 8, 1)));
    await b.log.append(_worn('b1', DateTime.utc(2026, 8, 2)));

    await a.engine.sync();
    await b.engine.sync();
    await a.engine.sync();

    expect((await a.items.byId(const ItemId('tee')))!.usage.timesWorn, 2);
    expect((await b.items.byId(const ItemId('tee')))!.usage.timesWorn, 2);
  });

  test(
    'a label reading beats a photo guess, whichever arrived later',
    () async {
      // Provenance, not the clock. This is the rule a plain overwrite destroys,
      // and the reason merging happens on the device rather than on the server.
      final token = _token('provenance');
      final a = device(token);
      final b = device(token);

      await a.items.save(_item(id: 'tee', name: 'White tee'));
      await a.engine.sync();
      await b.engine.sync();

      await a.items.save(
        (await a.items.byId(const ItemId('tee')))!.copyWith(
          composition: Confident(
            FabricComposition(const {Fiber.cotton: 60, Fiber.polyester: 40}),
            confidence: 0.95,
            source: Provenance.tagScan,
          ),
          updatedAt: _later(1),
        ),
      );
      await a.engine.sync();

      // B then makes a *later* but weaker change.
      await b.items.save(
        (await b.items.byId(const ItemId('tee')))!.copyWith(
          composition: Confident(
            FabricComposition(const {Fiber.cotton: 100}),
            confidence: 0.5,
            source: Provenance.aiInference,
          ),
          updatedAt: _later(2),
        ),
      );
      await b.engine.sync();
      await a.engine.sync();
      await b.engine.sync();

      for (final side in [a, b]) {
        final stored = (await side.items.byId(const ItemId('tee')))!;
        expect(stored.composition.source, Provenance.tagScan);
      }
    },
  );

  test('syncing repeatedly changes nothing', () async {
    // Idempotence against the real transport, not against a fake that cannot
    // re-deliver. The server's cursor is inclusive, so a device does receive
    // its own last push back — and must be unmoved by it.
    final token = _token('idempotent');
    final a = device(token);

    await a.items.save(_item(id: 'tee', name: 'White tee'));
    await a.engine.sync();
    final after = (await a.items.byId(const ItemId('tee')))!.toJson();

    await a.engine.sync();
    await a.engine.sync();

    expect((await a.items.byId(const ItemId('tee')))!.toJson(), after);
  });

  test('a wardrobe is not visible to a different token', () async {
    // The isolation property, verified across the whole stack rather than at
    // the store. If this regresses, everyone's wardrobe is everyone's.
    final a = device(_token('mine'));
    final stranger = device(_token('theirs'));

    await a.items.save(_item(id: 'tee', name: 'White tee'));
    await a.engine.sync();

    expect((await stranger.engine.sync()).succeeded, isTrue);
    expect(await stranger.items.byId(const ItemId('tee')), isNull);
  });

  test('a rejected token is reported, not retried forever', () async {
    final short = SyncEngine(
      items: InMemoryWardrobeRepository(),
      events: InMemoryEventLog(),
      remote: HttpSyncRemote(baseUrl: baseUrl, token: 'too-short'),
      cursor: InMemorySyncCursor(),
    );

    final report = await short.sync();
    expect(report.succeeded, isFalse);
    expect(report.failure, isNotNull);
  });
}

/// A wear, recorded now for a day in the past — exactly as the app's recorder
/// builds one. `recordedAt` is what sync selects on, and stamping it with the
/// backdated `occurredAt` would put the event behind the push cursor and
/// strand it, which is the bug this suite found in the first place.
ItemWorn _worn(String id, DateTime occurredAt) => ItemWorn(
  id: EventId(id),
  itemId: const ItemId('tee'),
  occurredAt: occurredAt,
  recordedAt: DateTime.now(),
);

/// When this run started, and the base for every timestamp in it.
///
/// Not a fixed date. A device pushes the items whose `updatedAt` is at or
/// after its own `lastPushedAt` mark, and that mark is stamped from the real
/// clock — so an `updatedAt` hard-coded in the past is silently never pushed.
/// The provenance test below was written with dates a few days ahead, passed
/// while they were still in the future, and began failing on 9 August 2026
/// when the wall clock caught up: neither device pushed its change, so each
/// kept its own and the weaker one "won" on the device that made it.
///
/// A calendar is not a fixture. Everything here is relative to this instant
/// instead, which keeps the ordering the tests actually care about.
final _startedAt = DateTime.now().toUtc();

/// [minutes] after the run started — far enough ahead of any cursor stamped
/// during it that a change is always eligible to be pushed.
DateTime _later(int minutes) => _startedAt.add(Duration(minutes: minutes));

WardrobeItem _item({required String id, required String name}) => WardrobeItem(
  id: ItemId(id),
  name: name,
  type: Confident(
    ItemType.tShirt,
    confidence: 0.9,
    source: Provenance.aiInference,
  ),
  composition: Confident(
    FabricComposition(const {Fiber.cotton: 100}),
    confidence: 0.6,
    source: Provenance.aiInference,
  ),
  colors: Confident(
    ColorPalette([ItemColor.fromHex('#F4F4F2')]),
    confidence: 0.9,
    source: Provenance.aiInference,
  ),
  care: const CareProfile.unknown(),
  addedAt: _startedAt.subtract(const Duration(days: 200)),
  updatedAt: _startedAt,
);

/// A distinct account per test, so one test's wardrobe cannot leak into
/// another's and make a failure look like a sync bug.
String _token(String name) => 'e2e-${name.padRight(40, '0')}';

/// Walks up to find `server/`, so the test works from any working directory.
String _findServerDirectory() {
  var directory = Directory.current.absolute;
  for (var depth = 0; depth < 6; depth++) {
    final candidate = Directory('${directory.path}/server');
    if (File('${candidate.path}/pyproject.toml').existsSync()) {
      return candidate.path;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError('could not find server/ from ${Directory.current.path}');
}

Future<void> _waitForHealth(Uri baseUrl, List<String> output) async {
  final client = http.Client();
  final deadline = DateTime.now().add(const Duration(seconds: 60));

  while (DateTime.now().isBefore(deadline)) {
    try {
      final response = await client
          .get(baseUrl.resolve('v1/health'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        client.close();
        return;
      }
    } on Exception {
      // Not up yet. Uvicorn takes a second or two to import the app.
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  client.close();
  throw StateError(
    'the server did not become healthy within 60s. Output:\n'
    '${output.join()}',
  );
}
