/// The HTTP sync client.
///
/// Driven against a stub transport rather than a live server, because what is
/// under test is the client's own behaviour: what it sends, what it decodes,
/// and — the part that matters most — which failures are worth retrying. A
/// separate suite runs the whole thing against the real FastAPI service.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/api/http_sync_remote.dart';

void main() {
  late List<http.Request> sent;

  HttpSyncRemote remoteThat(
    http.Response Function(http.Request request) respond, {
    String token = 'a-token-long-enough-to-be-accepted-xxxx',
  }) {
    sent = [];
    return HttpSyncRemote(
      baseUrl: Uri.parse('https://example.invalid/'),
      token: token,
      client: MockClient((request) async {
        sent.add(request);
        return respond(request);
      }),
    );
  }

  http.Response ok(Map<String, Object?> body) =>
      http.Response(jsonEncode(body), 200);

  group('what it sends', () {
    test('the token travels in a header, never in the URL', () async {
      // Query strings end up in proxy logs, server access logs and browser
      // history. A bearer token in one is a token in all three.
      final remote = remoteThat((_) => ok({'items': [], 'events': []}));
      await remote.pull();

      expect(sent.single.headers['Authorization'], startsWith('Bearer '));
      expect(sent.single.url.toString(), isNot(contains('a-token')));
    });

    test('a cursor is sent as UTC', () async {
      // The server compares against its own UTC stamps. Sending a local time
      // would skip exactly the window between the two.
      final remote = remoteThat((_) => ok({'items': [], 'events': []}));
      await remote.pull(since: DateTime.utc(2026, 8, 5, 12).toLocal());

      expect(sent.single.url.queryParameters['since'], endsWith('Z'));
    });

    test('no cursor means no query at all', () async {
      final remote = remoteThat((_) => ok({'items': [], 'events': []}));
      await remote.pull();

      expect(sent.single.url.queryParameters, isEmpty);
    });

    test('the endpoint is resolved beneath the configured base', () async {
      // `resolve` against a base without a trailing slash drops the last
      // segment, which is why the app normalises it. This pins the result.
      final remote = remoteThat((_) => ok({'items': [], 'events': []}));
      await remote.pull();

      expect(sent.single.url.path, '/v1/sync');
    });

    test(
      'a push carries items and events as the core serialises them',
      () async {
        final remote = remoteThat(
          (_) => ok({'acceptedAt': '2026-08-05T12:00:00Z'}),
        );

        await remote.push(SyncPayload(items: [_item()], events: [_event()]));

        final body = jsonDecode(sent.single.body) as Map<String, Object?>;
        expect((body['items']! as List).single, _item().toJson());
        expect((body['events']! as List).single, _event().toJson());
      },
    );
  });

  group('what it makes of the answer', () {
    test('decodes items and events back into domain objects', () async {
      final remote = remoteThat(
        (_) => ok({
          'items': [_item().toJson()],
          'events': [_event().toJson()],
          'serverTime': '2026-08-05T12:00:00Z',
        }),
      );

      final payload = await remote.pull();

      expect(payload.items.single.id, const ItemId('tee'));
      expect(payload.events.single, isA<ItemWorn>());
    });

    test('an empty response is empty, not an error', () async {
      final remote = remoteThat(
        (_) => ok({'serverTime': '2026-08-05T12:00:00Z'}),
      );

      expect((await remote.pull()).isEmpty, isTrue);
    });

    test('the accepted time comes back as UTC', () async {
      final remote = remoteThat(
        (_) => ok({'acceptedAt': '2026-08-05T12:00:00+02:00'}),
      );

      final at = await remote.push(const SyncPayload());
      expect(at.isUtc, isTrue);
      expect(at, DateTime.utc(2026, 8, 5, 10));
    });
  });

  group('failure, and whether it is worth retrying', () {
    Future<SyncFailure> failureFrom(Future<void> Function() call) async {
      try {
        await call();
      } on SyncFailure catch (failure) {
        return failure;
      }
      fail('expected a SyncFailure');
    }

    test('an unreachable server is retryable', () async {
      final remote = HttpSyncRemote(
        baseUrl: Uri.parse('https://example.invalid/'),
        token: 'a-token-long-enough-to-be-accepted-xxxx',
        client: MockClient((_) async => throw const SocketishError()),
      );

      final failure = await failureFrom(remote.pull);
      expect(failure.isRetryable, isTrue);
    });

    test('a rejected token is not', () async {
      // Retrying an identical bad credential forever flattens a battery and
      // never succeeds. The user has to change something.
      final remote = remoteThat((_) => http.Response('{}', 401));

      final failure = await failureFrom(remote.pull);
      expect(failure.isRetryable, isFalse);
      expect(failure.message, contains('Settings'));
    });

    test('a server without sync is not', () async {
      final remote = remoteThat((_) => http.Response('{}', 404));

      final failure = await failureFrom(remote.pull);
      expect(failure.isRetryable, isFalse);
    });

    test('a server error is', () async {
      final remote = remoteThat((_) => http.Response('boom', 503));

      expect((await failureFrom(remote.pull)).isRetryable, isTrue);
    });

    test('an oversized push is, because the backlog drains', () async {
      final remote = remoteThat((_) => http.Response('{}', 413));

      expect(
        (await failureFrom(() => remote.push(const SyncPayload()))).isRetryable,
        isTrue,
      );
    });

    test('a malformed body is not', () async {
      final remote = remoteThat((_) => http.Response('not json', 200));

      expect((await failureFrom(remote.pull)).isRetryable, isFalse);
    });

    test(
      'a push with no acceptance time is refused rather than guessed',
      () async {
        // Advancing the cursor to a made-up time would skip whatever was written
        // in between, permanently.
        final remote = remoteThat((_) => ok({'items': 1}));

        final failure = await failureFrom(
          () => remote.push(const SyncPayload()),
        );
        expect(failure.isRetryable, isFalse);
      },
    );

    test('no failure message quotes the response body', () async {
      // The body can echo back what was sent, which for a wardrobe is the
      // user's own data and for a push is potentially the whole payload.
      final remote = remoteThat(
        (_) => http.Response('the secret is hunter2', 500),
      );

      expect(
        (await failureFrom(remote.pull)).message,
        isNot(contains('hunter2')),
      );
    });
  });

  test(
    'the engine turns a failure into a report rather than an exception',
    () async {
      // The contract that matters to every caller: sync is attempted, and a dead
      // network is a result, not something to wrap in a try/catch at each site.
      final items = InMemoryWardrobeRepository();
      final engine = SyncEngine(
        items: items,
        events: InMemoryEventLog(),
        remote: HttpSyncRemote(
          baseUrl: Uri.parse('https://example.invalid/'),
          token: 'a-token-long-enough-to-be-accepted-xxxx',
          client: MockClient((_) async => throw const SocketishError()),
        ),
        cursor: InMemorySyncCursor(),
      );

      final report = await engine.sync();
      expect(report.succeeded, isFalse);
      expect(report.failure, isNotNull);
    },
  );
}

/// Stands in for a socket failure without depending on `dart:io`, so this
/// suite runs on every platform the app targets.
class SocketishError implements Exception {
  const SocketishError();

  @override
  String toString() => 'connection refused';
}

WardrobeItem _item() => WardrobeItem(
  id: const ItemId('tee'),
  name: 'White tee',
  type: Confident(
    ItemType.tShirt,
    confidence: 0.9,
    source: Provenance.aiInference,
  ),
  composition: Confident(
    FabricComposition(const {Fiber.cotton: 100}),
    confidence: 0.9,
    source: Provenance.tagScan,
  ),
  colors: Confident(
    ColorPalette([ItemColor.fromHex('#F4F4F2')]),
    confidence: 0.9,
    source: Provenance.aiInference,
  ),
  care: const CareProfile.unknown(),
  addedAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 8, 1),
);

ItemWorn _event() => ItemWorn(
  id: const EventId('e1'),
  itemId: const ItemId('tee'),
  occurredAt: DateTime.utc(2026, 8, 1),
);
