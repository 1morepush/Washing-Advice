/// The gateway calls the paths the server actually serves.
///
/// Every route the server exposes lives under a `/v1` prefix
/// (`server/app/api/v1/router.py`). `health()` is the one call that used to
/// skip it — `baseUrl.resolve('health')` instead of `baseUrl.resolve('v1/health')`
/// — which meant "Save and test" in Settings could never succeed against any
/// real deployment. Nothing exercised the request `AiGateway` actually made,
/// only fakes standing in for it, so the wrong path shipped unnoticed.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/api/stain_dto.dart';

void main() {
  _streamingStainAdvice();

  group('health()', () {
    test('requests v1/health, not the bare path', () async {
      Uri? requested;
      final client = MockClient((request) async {
        requested = request.url;
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });
      final gateway = AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: client,
      );

      final result = await gateway.health();

      expect(requested?.path, '/v1/health');
      expect(result.reachable, isTrue);
      expect(result.status, 'ok');
    });

    test('a server that is slow to wake is waited for, not failed', () async {
      // The free-tier host sleeps when idle and takes tens of seconds to
      // answer its first request. A five-second timeout reported a correctly
      // configured backend as unreachable — the one answer this call exists
      // to rule out.
      //
      // Seven seconds rather than a realistic thirty: it is past the limit
      // that used to fail while costing the suite as little as a real timer
      // allows.
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(seconds: 7));
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });
      final gateway = AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: client,
      );

      final result = await gateway.health();

      expect(result.reachable, isTrue);
      expect(result.status, 'ok');
    });

    test('a genuinely unreachable server is reported, not thrown', () async {
      final client = MockClient((request) async {
        throw http.ClientException('Load failed');
      });
      final gateway = AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: client,
      );

      final result = await gateway.health();

      expect(result.reachable, isFalse);
      expect(result.status, 'unreachable');
    });
  });

  group('every other call also reaches a route the server serves', () {
    // `health()` was the one that skipped the prefix, and it was the one with
    // no test asserting the URL. The rest were correct by luck rather than by
    // test, so the gap that let it ship was still open for four endpoints.
    //
    // The expected paths here are the deployed server's own route list
    // (`GET /openapi.json`), not a restatement of what the client does.

    late Uri requested;
    late String method;

    AiGateway gatewayReturning(Object body) {
      final client = MockClient((request) async {
        requested = request.url;
        method = request.method;
        return http.Response(jsonEncode(body), 200);
      });
      return AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: client,
      );
    }

    ScanImage image() =>
        ScanImage(bytes: Uint8List.fromList([1, 2, 3]), mimeType: 'image/jpeg');

    test('scanGarment posts to v1/scan/garment', () async {
      await gatewayReturning({
        'result': {
          'type': {
            'value': 'tShirt',
            'confidence': 0.9,
            'source': 'aiInference',
          },
        },
      }).scanGarment([image()]);

      expect(requested.path, '/v1/scan/garment');
      expect(method, 'POST');
    });

    test('scanCareTag posts to v1/scan/care-tag', () async {
      // Hyphenated, not `care_tag` or `careTag` — a shape the rest of the
      // client never uses, so it is the likeliest of these to drift.
      await gatewayReturning({
        'result': {'instructions': <String, Object?>{}, 'confidence': 0.8},
      }).scanCareTag(image());

      expect(requested.path, '/v1/scan/care-tag');
      expect(method, 'POST');
    });

    test('scanPile posts to v1/scan/pile', () async {
      await gatewayReturning({
        'result': {'items': <Object?>[]},
      }).scanPile(image());

      expect(requested.path, '/v1/scan/pile');
      expect(method, 'POST');
    });

    test('cutout posts to v1/image/cutout', () async {
      // Under `image/`, not `scan/`: it turns pixels into other pixels rather
      // than into facts, and it is the only call whose reply is not JSON.
      final client = MockClient((request) async {
        requested = request.url;
        method = request.method;
        return http.Response.bytes([0x89, 0x50, 0x4E, 0x47], 200);
      });
      final gateway = AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: client,
      );

      await gateway.cutout(image());

      expect(requested.path, '/v1/image/cutout');
      expect(method, 'POST');
    });

    test(
      'a base URL without a trailing slash still resolves correctly',
      () async {
        // What someone actually types into Settings. `resolve` replaces the last
        // path segment, so a missing slash is a real way to lose the prefix.
        final client = MockClient((request) async {
          requested = request.url;
          return http.Response(jsonEncode({'status': 'ok'}), 200);
        });
        final gateway = AiGateway(
          baseUrl: Uri.parse('https://washing-advice.onrender.com'),
          client: client,
        );

        await gateway.health();

        expect(
          requested.toString(),
          'https://washing-advice.onrender.com/v1/health',
        );
      },
    );
  });

  group('identifying a washer or dryer', () {
    // Brand and model text, not a photo — the request has no file to upload,
    // which is why AiGateway needed a second POST shape (_postJson) alongside
    // the multipart one every other call uses.

    late Uri requested;
    late String method;
    late Map<String, Object?> sentBody;

    AiGateway gatewayReturning(Object body) {
      final client = MockClient((request) async {
        requested = request.url;
        method = request.method;
        sentBody = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(jsonEncode(body), 200);
      });
      return AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: client,
      );
    }

    test('identifyWasher posts brand and model to v1/machine/washer', () async {
      await gatewayReturning({
        'result': {
          'id': 'ai.washer.samsung.wf45t6000aw',
          'brand': 'Samsung',
          'model': 'WF45T6000AW',
          'capacityKg': 9.0,
          'programs': <Object?>[],
        },
      }).identifyWasher(brand: 'Samsung', model: 'WF45T6000AW');

      expect(requested.path, '/v1/machine/washer');
      expect(method, 'POST');
      expect(sentBody, {'brand': 'Samsung', 'model': 'WF45T6000AW'});
    });

    test('identifyDryer posts brand and model to v1/machine/dryer', () async {
      await gatewayReturning({
        'result': {
          'id': 'ai.dryer.lg.dlex3900w',
          'brand': 'LG',
          'model': 'DLEX3900W',
          'capacityKg': 7.5,
          'programs': <Object?>[],
        },
      }).identifyDryer(brand: 'LG', model: 'DLEX3900W');

      expect(requested.path, '/v1/machine/dryer');
      expect(sentBody, {'brand': 'LG', 'model': 'DLEX3900W'});
    });

    test('a recognised washer decodes into a real WasherProfile', () async {
      // Captured directly from a run of the real server (fake provider), not
      // hand-written — this is the actual shape it sends, not a guess at it.
      const captured = '''
        {"result":{"id":"ai.washer.samsung-wf45t6000aw","brand":"Samsung",
        "model":"WF45T6000AW","capacityKg":11.0,"programs":[{"id":
        "ai.washer.samsung-wf45t6000aw.program-0","displayName":"Cotton",
        "kind":"cotton","availableTempsC":[0,30,40,60],"defaultTempC":40,
        "agitation":"normal","spinSpeedsRpm":[0,600,800,1200],"suitableFor":
        ["normal","heavy"],"maxLoadFraction":1.0,"typicalDurationMinutes":120}],
        "options":[],"isVerifiedModel":false},
        "diagnostics":{"stagesRun":["fake"],"stageAnswered":"fake",
        "servedFromCache":false,"elapsedMs":0}}
      ''';
      final client = MockClient(
        (request) async => http.Response(captured, 200),
      );
      final gateway = AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: client,
      );

      final profile = await gateway.identifyWasher(
        brand: 'Samsung',
        model: 'WF45T6000AW',
      );

      expect(profile.brand, 'Samsung');
      expect(profile.model, 'WF45T6000AW');
      expect(profile.programs, hasLength(1));
      expect(profile.programs.single.displayName, 'Cotton');
      expect(profile.isVerifiedModel, isFalse);
    });

    test('a machine the model does not recognise is a ScanFailure', () async {
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'error': 'machine_not_identified',
            'detail': 'no reliable knowledge of this exact make and model',
            'hint': 'Try just the brand, or use the generic profile instead.',
          }),
          422,
        ),
      );
      final gateway = AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: client,
      );

      await expectLater(
        gateway.identifyWasher(brand: 'Nonesuch', model: 'XY9000'),
        throwsA(
          isA<ScanFailure>().having(
            (f) => f.message,
            'message',
            contains('no reliable knowledge'),
          ),
        ),
      );
    });
  });
}

/// The wire format between the two halves of the streaming stain flow.
///
/// The server writes server-sent events and this decodes them, and nothing
/// either side of that boundary would notice if the framing were wrong — the
/// controller would simply be handed no steps. Worth its own tests because SSE
/// framing is easy to get almost right: the events are separated by blank
/// lines, a chunk can split anywhere including mid-frame, and a `data:` line
/// carrying something this build has never heard of has to be survivable.
void _streamingStainAdvice() {
  const frames =
      'data: {"type": "identified", "identifiedAs": "red wine"}\n'
      '\n'
      'data: {"type": "step", "step": {"instruction": "Blot it.",'
      ' "abrades": true, "isMachineWash": false}}\n'
      '\n'
      'data: {"type": "step", "step": {"instruction": "Soak it.",'
      ' "temperatureC": 40, "bleach": "oxygen", "isMachineWash": false,'
      ' "abrades": false}}\n'
      '\n'
      'data: {"type": "done", "diagnostics": {"stagesRun": ["gemini"],'
      ' "stageAnswered": "gemini", "elapsedMs": 900}}\n'
      '\n';

  /// A gateway whose server sends [frames] in chunks of [size] bytes.
  AiGateway gatewayFor(String body, {int size = 4096}) {
    final client = MockClient.streaming((request, _) async {
      final bytes = utf8.encode(body);
      return http.StreamedResponse(
        Stream.fromIterable([
          for (var at = 0; at < bytes.length; at += size)
            bytes.sublist(
              at,
              at + size > bytes.length ? bytes.length : at + size,
            ),
        ]),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    return AiGateway(
      baseUrl: Uri.parse('http://test.invalid/'),
      client: client,
    );
  }

  Future<List<StainStreamEvent>> collect(AiGateway gateway) => gateway
      .streamStainAdvice(
        substance: 'red wine',
        fabric: '100% Cotton',
        care: 'Machine wash, up to 40°C.',
      )
      .toList();

  group('streaming stain advice', () {
    test('the events decode in order', () async {
      final events = await collect(gatewayFor(frames));

      expect(events.map((e) => e.runtimeType.toString()), [
        'StainIdentified',
        'StainStep',
        'StainStep',
        'StainDone',
      ]);
    });

    test('the structured fields survive the wire', () async {
      // These are what the safety check reads. A step that arrived with its
      // temperature dropped would be vetted as one that names no temperature.
      final events = await collect(gatewayFor(frames));
      final soak = events.whereType<StainStep>().last.step;

      expect(soak.temperatureC, 40);
      expect(soak.bleach, BleachUse.oxygen);
    });

    test('a frame split across chunks still decodes', () async {
      // A network hands over whatever has arrived, not whole events.
      final events = await collect(gatewayFor(frames, size: 7));

      expect(events.whereType<StainStep>(), hasLength(2));
      expect(events.last, isA<StainDone>());
    });

    test('an event type this build does not know is skipped', () async {
      // A newer server may send more. Dropping one costs nothing; throwing
      // would lose a treatment the user is halfway through following.
      const withExtra =
          'data: {"type": "pondering", "note": "hmm"}\n'
          '\n'
          'data: {"type": "step", "step": {"instruction": "Blot it.",'
          ' "abrades": true, "isMachineWash": false}}\n'
          '\n';

      final events = await collect(gatewayFor(withExtra));
      expect(events, hasLength(1));
      expect(events.single, isA<StainStep>());
    });

    test('a stream with no done event simply ends', () async {
      // The gateway reports it by omission; deciding what that means is the
      // controller's job, and it is not the same as a failure.
      const truncated =
          'data: {"type": "step", "step": {"instruction": "Blot it.",'
          ' "abrades": true, "isMachineWash": false}}\n'
          '\n';

      final events = await collect(gatewayFor(truncated));
      expect(events.whereType<StainDone>(), isEmpty);
    });

    test('diagnostics from the done event are recorded', () async {
      final gateway = gatewayFor(frames);
      await collect(gateway);

      expect(gateway.lastDiagnostics?.elapsedMs, 900);
    });

    test('a rejected request is an ordinary failure', () async {
      final client = MockClient.streaming((request, _) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"detail": "substance is required"}')),
          422,
        );
      });
      final gateway = AiGateway(
        baseUrl: Uri.parse('http://test.invalid/'),
        client: client,
      );

      await expectLater(collect(gateway), throwsA(isA<ScanFailure>()));
    });
  });
}
