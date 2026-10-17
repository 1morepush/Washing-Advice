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
import 'package:washing_advice/data/api/scan_dto.dart';
import 'package:washing_advice/data/api/stain_dto.dart';

import '../support/fixtures.dart';

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
      }).scanCareTag([image()]);

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
  _askingForOutfits();
  _askingAQuestion();
  _describingAListing();
  _pricingAListing();
}

/// Asking for outfit ideas.
///
/// The one endpoint whose `result` is an array rather than an object, which is
/// the sort of thing that is correct by luck until somebody refactors the
/// unwrapping. It is also the only call that sends the wardrobe up, so what
/// goes *into* the request is worth asserting: a stylist told nothing about
/// colour would be guessing.
void _askingForOutfits() {
  group('proposeOutfits', () {
    late Uri requested;
    late Map<String, Object?> sent;

    AiGateway gatewayReturning(Object body) {
      final client = MockClient((request) async {
        requested = request.url;
        sent = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(jsonEncode(body), 200);
      });
      return AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: client,
      );
    }

    WardrobeItem item(String id, {String? brand}) {
      final built = WardrobeItem(
        id: ItemId(id),
        name: 'Oxford shirt',
        type: Confident(
          ItemType.dressShirt,
          confidence: 0.9,
          source: Provenance.aiInference,
        ),
        brand: brand == null ? null : Confident.fromUser(brand),
        composition: Confident(
          FabricComposition(const {Fiber.cotton: 100}),
          confidence: 0.9,
          source: Provenance.tagScan,
        ),
        colors: Confident(
          ColorPalette([ItemColor.fromHex('#FFFFFF', name: 'white')]),
          confidence: 0.9,
          source: Provenance.aiInference,
        ),
        care: const CareProfile.unknown(),
        addedAt: DateTime.utc(2026, 8, 5),
        updatedAt: DateTime.utc(2026, 8, 5),
      );
      return built.copyWith(care: const CareResolver().forItem(built).profile);
    }

    /// Captured from a run of the real server with the fake stylist, not
    /// hand-written — this is the shape it actually sends.
    const captured =
        '{"result":[{"itemIds":["shirt","chinos","shoes"],"rationale":'
        '"The stone chinos keep the oxford shirt from reading as formal, '
        'which suits Everyday."},{"itemIds":["shirt","tee","chinos"],'
        '"rationale":"Two tops at once, which is not a thing."}],'
        '"diagnostics":{"stagesRun":["fake"],"stageAnswered":"fake",'
        '"servedFromCache":false,"elapsedMs":0}}';

    test('posts to v1/style/outfits', () async {
      await gatewayReturning(
        jsonDecode(captured),
      ).proposeOutfits(wardrobe: [item('shirt')], occasion: 'Everyday');

      expect(requested.path, '/v1/style/outfits');
    });

    test('a result array decodes into proposals', () async {
      // `_decodeResult` insists on an object and every other endpoint returns
      // one. This is the exception, and reading it through the ordinary path
      // would throw on a perfectly good answer.
      final client = MockClient(
        (request) async => http.Response(captured, 200),
      );
      final gateway = AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: client,
      );

      final proposals = await gateway.proposeOutfits(
        wardrobe: [item('shirt')],
        occasion: 'Everyday',
      );

      expect(proposals.outfits, hasLength(2));
      expect(proposals.outfits.first.itemIds, [
        const ItemId('shirt'),
        const ItemId('chinos'),
        const ItemId('shoes'),
      ]);
      expect(proposals.outfits.first.rationale, contains('stone chinos'));
    });

    test('the stylist is told what each garment looks like', () async {
      await gatewayReturning(jsonDecode(captured)).proposeOutfits(
        wardrobe: [item('shirt', brand: 'Uniqlo')],
        occasion: 'Everyday',
        season: 'Summer',
        count: 3,
        note: '  it will be cold  ',
      );

      expect(sent['occasion'], 'Everyday');
      expect(sent['season'], 'Summer');
      expect(sent['count'], 3);
      expect(sent['note'], 'it will be cold');

      final garment = (sent['wardrobe']! as List).single as Map;
      expect(garment['id'], 'shirt');
      expect(garment['type'], 'Dress shirt');
      expect(garment['category'], 'Tops');
      expect(garment['colors'], ['white']);
      expect(garment['fabric'], '100% Cotton');
      expect(garment['brand'], 'Uniqlo');
    });

    test('nothing the stylist has no use for is sent', () async {
      // Not tidiness. Every field is tokens spent on each request and one more
      // thing to keep in step across two languages, and a stylist has no use
      // for wash temperatures or wear counts.
      await gatewayReturning(
        jsonDecode(captured),
      ).proposeOutfits(wardrobe: [item('shirt')], occasion: 'Everyday');

      final garment = (sent['wardrobe']! as List).single as Map;
      expect(garment.keys, isNot(contains('care')));
      expect(garment.keys, isNot(contains('usage')));
      expect(garment.keys, isNot(contains('lifecycle')));
      // Absent rather than null: an unbranded garment says nothing about its
      // brand rather than saying its brand is nothing.
      expect(garment.keys, isNot(contains('brand')));
    });

    test('a malformed proposal is dropped, not thrown on', () async {
      // One bad entry in a batch of three is not a reason to show none, and
      // the vetting downstream would refuse it anyway.
      final proposals = await gatewayReturning({
        'result': [
          {'itemIds': <String>[], 'rationale': 'nothing to wear'},
          {
            'itemIds': ['shirt', 'chinos'],
            'rationale': '   ',
          },
          {
            'itemIds': ['shirt', 'chinos'],
            'rationale': 'this one is fine',
          },
        ],
      }).proposeOutfits(wardrobe: [item('shirt')], occasion: 'Everyday');

      expect(proposals.outfits.single.rationale, 'this one is fine');
    });

    test('the gaps are not asked for unless they were requested', () async {
      // Opt-in on the wire too, not merely unshown. The flag and the type
      // vocabulary both stay off the request until somebody ticks the box.
      await gatewayReturning(
        jsonDecode(captured),
      ).proposeOutfits(wardrobe: [item('shirt')], occasion: 'Everyday');

      expect(sent.containsKey('suggestGaps'), isFalse);
      expect(sent.containsKey('stylableTypes'), isFalse);
    });

    test(
      'asking for them sends the vocabulary the core resolves against',
      () async {
        // Sent rather than held on the server, so the list the model may name
        // from and the list GapVetting parses back cannot drift apart.
        await gatewayReturning(jsonDecode(captured)).proposeOutfits(
          wardrobe: [item('shirt')],
          occasion: 'Everyday',
          suggestGaps: true,
        );

        expect(sent['suggestGaps'], isTrue);
        expect(sent['stylableTypes'], contains('Jeans'));
        // The vocabulary is the core's, so what it excludes is excluded here.
        expect(sent['stylableTypes'], isNot(contains('Pajamas')));
      },
    );

    test('a pieces array decodes into proposals', () async {
      final answer =
          await gatewayReturning({
            'result': [
              {
                'itemIds': ['shirt', 'chinos'],
                'rationale': 'fine',
              },
            ],
            'pieces': [
              {
                'type': 'Jeans',
                'colors': ['dark blue'],
                'pairsWith': ['shirt'],
                'rationale': 'Something with body under the oxford.',
              },
            ],
          }).proposeOutfits(
            wardrobe: [item('shirt')],
            occasion: 'Everyday',
            suggestGaps: true,
          );

      expect(answer.pieces, hasLength(1));
      expect(answer.pieces.single.type, 'Jeans');
      expect(answer.pieces.single.colors, ['dark blue']);
      expect(answer.pieces.single.pairsWithIds, [const ItemId('shirt')]);
    });

    test('a server that has never heard of pieces is not a failure', () async {
      // The shape this has to survive most. An older backend answers the outfit
      // question perfectly well and simply says nothing about gaps; treating
      // the missing key as an error would break a working deployment.
      final answer = await gatewayReturning(jsonDecode(captured))
          .proposeOutfits(
            wardrobe: [item('shirt')],
            occasion: 'Everyday',
            suggestGaps: true,
          );

      expect(answer.outfits, isNotEmpty);
      expect(answer.pieces, isEmpty);
    });

    test('a piece with no reason is dropped rather than shown blank', () async {
      final answer =
          await gatewayReturning({
            'result': [
              {
                'itemIds': ['shirt', 'chinos'],
                'rationale': 'fine',
              },
            ],
            'pieces': [
              {
                'type': 'Jeans',
                'pairsWith': ['shirt'],
                'rationale': '   ',
              },
              {
                'type': 'Blazer',
                'pairsWith': ['shirt'],
                'rationale': 'this one is fine',
              },
            ],
          }).proposeOutfits(
            wardrobe: [item('shirt')],
            occasion: 'Everyday',
            suggestGaps: true,
          );

      expect(answer.pieces.single.type, 'Blazer');
    });

    test('a result that is not a list is a contract error', () async {
      await expectLater(
        gatewayReturning({
          'result': {'itemIds': <String>[]},
        }).proposeOutfits(wardrobe: [item('shirt')], occasion: 'Everyday'),
        throwsA(isA<ScanContractError>()),
      );
    });

    test('an empty wardrobe never reaches the server', () async {
      // A round trip to be told what the app already knows, and the answer is
      // a sentence rather than an error.
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return http.Response(captured, 200);
      });

      await expectLater(
        AiGateway(
          baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
          client: client,
        ).proposeOutfits(wardrobe: const [], occasion: 'Everyday'),
        throwsA(
          isA<ScanFailure>().having((f) => f.isRetryable, 'retryable', isFalse),
        ),
      );
      expect(called, isFalse);
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

/// Asking a question in words.
///
/// Its own function rather than more tests bolted onto another group: this is
/// the only call that carries a *conversation*, and the cap on that is the one
/// thing here with a sharp edge. The server refuses a longer history with a
/// 422, which this client classes as not retryable — so an uncapped thread
/// does not slow down, it stops working for good.
void _askingAQuestion() {
  group('askQuestion', () {
    late Map<String, Object?> sent;

    AiGateway gateway() {
      final client = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(jsonEncode({'reply': 'Cold wash.'}), 200);
      });
      return AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: client,
      );
    }

    List<({bool fromUser, String text})> turns(int count) => [
      for (var i = 0; i < count; i++) (fromUser: i.isEven, text: 'turn $i'),
    ];

    test('a short conversation goes up whole', () async {
      await gateway().askQuestion(
        question: 'and the black one?',
        wardrobe: const [],
        history: turns(4),
      );

      expect((sent['history']! as List), hasLength(4));
    });

    test('a long one is trimmed to the cap', () async {
      // The server refuses more than this with a 422, and a 422 is classed
      // here as *not* retryable. Uncapped, a long conversation would not
      // degrade — it would die: every further question failing for good, with
      // the only way out a Clear button nobody would connect to the cause.
      await gateway().askQuestion(
        question: 'and the black one?',
        wardrobe: const [],
        history: turns(200),
      );

      expect((sent['history']! as List), hasLength(AiGateway.historyLimit));
    });

    test('and it is the most recent turns that survive', () async {
      // The end of a conversation, not the start of it. "And the black one?"
      // is unanswerable without the turn above it; the opening exchange of a
      // long thread is the part that can be spared.
      await gateway().askQuestion(
        question: 'and the black one?',
        wardrobe: const [],
        history: turns(200),
      );

      final history = (sent['history']! as List).cast<Map<String, Object?>>();
      expect(history.last['text'], 'turn 199');
    });

    test('an empty history is left out rather than sent empty', () async {
      await gateway().askQuestion(question: 'hello', wardrobe: const []);

      expect(sent.containsKey('history'), isFalse);
    });

    test('a question with no wardrobe is still a question', () async {
      // Plenty of them are not about the user's clothes at all.
      final answer = await gateway().askQuestion(
        question: 'what does the triangle mean?',
        wardrobe: const [],
      );

      expect(answer, 'Cold wash.');
    });

    test('an empty question never reaches the server', () async {
      await expectLater(
        gateway().askQuestion(question: '   ', wardrobe: const []),
        throwsA(isA<ScanFailure>()),
      );
    });
  });
}

/// Drafting a listing from photographs.
///
/// The server is what reads them, so what is held here is the wire: the path,
/// the form fields the server looks for, the cap on photographs, and what each
/// way of going wrong turns into. A field named `image` where the server reads
/// `images` is a request that succeeds and describes nothing, which no fake
/// standing in for the gateway would ever notice.
void _describingAListing() {
  group('describeListing', () {
    late http.Request sent;
    var requests = 0;

    AiGateway gatewayReturning(Object body, {int status = 200}) {
      requests = 0;
      final client = MockClient((request) async {
        requests++;
        sent = request;
        return http.Response(jsonEncode(body), status);
      });
      return AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: client,
      );
    }

    /// A photograph that is one letter, so its place in the form is readable.
    ScanImage photo(String mark, {String mimeType = 'image/jpeg'}) =>
        ScanImage(bytes: utf8.encode(mark), mimeType: mimeType);

    List<_Part> parts() => _partsOf(sent);

    List<_Part> images() => [
      for (final part in parts())
        if (part.name == 'images') part,
    ];

    test('posts to v1/sell/describe', () async {
      await gatewayReturning(_described).describeListing([photo('A')]);

      expect(sent.url.path, '/v1/sell/describe');
      expect(sent.method, 'POST');
      expect(sent.headers['content-type'], startsWith('multipart/form-data'));
    });

    test('sends every photograph as an images part, in order', () async {
      await gatewayReturning(_described).describeListing([
        photo('A'),
        photo('B', mimeType: 'image/png'),
        photo('C'),
      ]);

      expect(images().map((part) => part.text), ['A', 'B', 'C']);
      expect(images().map((part) => part.contentType), [
        'image/jpeg',
        'image/png',
        'image/jpeg',
      ]);
      expect(images().map((part) => part.filename), [
        'upload.jpeg',
        'upload.png',
        'upload.jpeg',
      ]);
    });

    test('sends no more than four, and the first four', () async {
      // The caller picks which photographs are worth the server's reading by
      // putting them first. A fifth is not an error, it is just not sent.
      await gatewayReturning(_described).describeListing([
        for (final mark in ['A', 'B', 'C', 'D', 'E', 'F']) photo(mark),
      ]);

      expect(AiGateway.describePhotoLimit, 4);
      expect(images().map((part) => part.text), ['A', 'B', 'C', 'D']);
    });

    test('sends exactly four when there are exactly four', () async {
      await gatewayReturning(_described).describeListing([
        for (final mark in ['A', 'B', 'C', 'D']) photo(mark),
      ]);

      expect(images(), hasLength(4));
    });

    test('sends nothing but photographs when there is no context', () async {
      await gatewayReturning(_described).describeListing([photo('A')]);

      expect(parts().map((part) => part.name), ['images']);
    });

    test('sends what the wardrobe knows as a context field of JSON', () async {
      final known = {
        'known': {
          'itemType': 'sweatshirt',
          'brand': 'Nike',
          'colors': ['Grey'],
          'sizeLabel': 'M',
        },
        // Characters that a careless encoding would break.
        'notes': 'Bought in "2019", worn twice. Béis bag, 100% — still good.',
      };

      await gatewayReturning(
        _described,
      ).describeListing([photo('A')], context: known);

      final context = parts().singleWhere((part) => part.name == 'context');
      expect(context.filename, isNull);
      expect(jsonDecode(context.text), known);
    });

    test(
      'the context the core writes for a garment goes up as it is',
      () async {
        final item = confidentItem(id: 'sweat', name: 'Grey crewneck').copyWith(
          brand: Confident.fromUser('Nike'),
          sizeLabel: 'M',
          notes: 'Bought in 2019',
        );
        final context = describeContextForItem(item);

        await gatewayReturning(
          _described,
        ).describeListing([photo('A')], context: context);

        final sentContext = parts().singleWhere((p) => p.name == 'context');
        expect(jsonDecode(sentContext.text), context);
        expect((jsonDecode(sentContext.text) as Map)['known'], isNotEmpty);
      },
    );

    test('a context with nothing in it is still valid JSON', () async {
      // The contract allows `{}`: nothing is known, and that is not the same
      // as not having been asked.
      await gatewayReturning(
        _described,
      ).describeListing([photo('A')], context: const {});

      final context = parts().singleWhere((part) => part.name == 'context');
      expect(jsonDecode(context.text), <String, Object?>{});
    });

    test('with no photographs it fails without asking the server', () async {
      final gateway = gatewayReturning(_described);

      await expectLater(
        gateway.describeListing(const []),
        throwsA(
          isA<ScanFailure>().having((f) => f.isRetryable, 'isRetryable', false),
        ),
      );
      expect(requests, 0);
    });

    test('reads the draft the server returns', () async {
      final facts = await gatewayReturning(
        _described,
      ).describeListing([photo('A')]);

      expect(facts.title, 'Nike vintage crewneck sweatshirt grey');
      expect(facts.itemType, ItemType.sweatshirt);
      expect(facts.brand!.value, 'Nike');
      expect(facts.sizeOnTag!.value, 'M');
      expect(facts.colors, ['Grey']);
      expect(facts.material, '80% cotton, 20% polyester');
      expect(facts.era, '90s');
      expect(facts.visibleFlaws, ['small mark on the left cuff']);
      expect(
        facts.searchQueries.retail,
        'Nike Club Fleece crew sweatshirt grey',
      );
    });

    test('and remembers how the reading was arrived at', () async {
      final gateway = gatewayReturning(_described);

      await gateway.describeListing([photo('A')]);

      expect(gateway.lastDiagnostics!.stageAnswered, 'gemini');
      expect(gateway.lastDiagnostics!.elapsedMs, 2140);
    });

    test('a draft with only a title is a draft', () async {
      // Everything else absent means the photographs did not show it.
      final facts = await gatewayReturning({
        'result': {
          'title': 'Grey crewneck sweatshirt',
          'itemType': 'sweatshirt',
          'colors': <Object?>[],
          'styleWords': <Object?>[],
          'visibleFlaws': <Object?>[],
          'searchQueries': {
            'depop': 'grey crewneck sweatshirt',
            'retail': 'grey crewneck sweatshirt',
          },
        },
      }).describeListing([photo('A')]);

      expect(facts.title, 'Grey crewneck sweatshirt');
      expect(facts.brand, isNull);
      expect(facts.sizeOnTag, isNull);
      expect(facts.material, isNull);
    });

    test('a response with no title is one the app cannot read', () async {
      await expectLater(
        gatewayReturning({
          'result': {'itemType': 'sweatshirt', 'colors': <Object?>[]},
        }).describeListing([photo('A')]),
        throwsA(isA<ScanContractError>()),
      );
    });

    test('a response with no result is one the app cannot read', () async {
      await expectLater(
        gatewayReturning({
          'diagnostics': <String, Object?>{},
        }).describeListing([photo('A')]),
        throwsA(isA<ScanContractError>()),
      );
    });

    test('a 503 is a ScanFailure that is worth retrying', () async {
      await expectLater(
        gatewayReturning({
          'detail': 'Reading photographs is unavailable.',
        }, status: 503).describeListing([photo('A')]),
        throwsA(
          isA<ScanFailure>()
              .having((f) => f.message, 'message', contains('unavailable'))
              .having((f) => f.isRetryable, 'isRetryable', true),
        ),
      );
    });

    test('a photograph the server refuses is not worth retrying', () async {
      await expectLater(
        gatewayReturning({
          'detail': 'That is not a photograph.',
        }, status: 422).describeListing([photo('A')]),
        throwsA(
          isA<ScanFailure>()
              .having((f) => f.message, 'message', 'That is not a photograph.')
              .having((f) => f.isRetryable, 'isRetryable', false),
        ),
      );
    });

    test('a server that cannot be reached is a ScanFailure', () async {
      final gateway = AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: MockClient((_) async => throw http.ClientException('offline')),
      );

      await expectLater(
        gateway.describeListing([photo('A')]),
        throwsA(
          isA<ScanFailure>().having(
            (f) => f.message,
            'message',
            contains('Could not reach the server'),
          ),
        ),
      );
    });
  });
}

/// Looking up what something sells for.
///
/// What is pinned most firmly is the one thing that looks like a bug and is
/// not: a search that found nothing, or could not search, comes back as data.
/// Everything else the screen does about prices rests on being able to ask and
/// be told "no key", "no allowance left" or "not just now" without an
/// exception.
void _pricingAListing() {
  group('searchPrices', () {
    late http.Request sent;
    var requests = 0;

    AiGateway gatewayReturning(Object body, {int status = 200}) {
      requests = 0;
      final client = MockClient((request) async {
        requests++;
        sent = request;
        return http.Response(jsonEncode(body), status);
      });
      return AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: client,
      );
    }

    final request = priceSearchRequestJson(
      queries: const SearchQueries(
        depop: 'Nike vintage crewneck sweatshirt grey',
        retail: 'Nike Club Fleece crew sweatshirt grey',
      ),
      itemType: ItemType.sweatshirt,
      title: 'Nike vintage crewneck sweatshirt grey',
      brand: 'Nike',
      colors: const ['Grey'],
    );

    Map<String, Object?> answer(
      String status, {
      List<Object?> comparables = const [],
      List<Object?> retail = const [],
    }) => {
      'result': {
        'status': status,
        if (status == 'ok') 'searchedAt': '2026-10-17T14:05:00Z',
        if (status == 'ok') 'provider': 'tavily',
        'queries': request['queries'],
        'comparables': comparables,
        'retail': retail,
        'excluded': {'notUsd': 0, 'unverifiedPrice': 0, 'notComparable': 0},
      },
      'diagnostics': {'stagesRun': <Object?>[], 'elapsedMs': 0},
    };

    test('posts the request as JSON to v1/sell/prices', () async {
      await gatewayReturning(answer('ok')).searchPrices(request);

      expect(sent.url.path, '/v1/sell/prices');
      expect(sent.method, 'POST');
      expect(sent.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(sent.body), request);
    });

    test('sends the phrases to search for, and what the garment is', () async {
      await gatewayReturning(answer('ok')).searchPrices(request);

      final body = jsonDecode(sent.body) as Map<String, Object?>;
      expect(body['queries'], {
        'depop': 'Nike vintage crewneck sweatshirt grey',
        'retail': 'Nike Club Fleece crew sweatshirt grey',
      });
      expect(body['itemType'], 'sweatshirt');
      expect(body['title'], 'Nike vintage crewneck sweatshirt grey');
      expect(body['brand'], 'Nike');
      expect(body['colors'], ['Grey']);
    });

    test(
      'reads comparables, what it costs new, and what was left out',
      () async {
        final search = await gatewayReturning({
          'result': {
            'status': 'ok',
            'searchedAt': '2026-10-17T14:05:00Z',
            'provider': 'tavily',
            'queries': request['queries'],
            'comparables': [
              {
                'title': 'Vintage Nike grey crewneck sweatshirt',
                'url': 'https://www.depop.com/products/example-1/',
                'price': 32.0,
                'currency': 'USD',
                'sold': true,
                'condition': 'Used - Excellent',
                'match': 'same',
                'why': 'Same 90s Nike crewneck, also grey',
              },
              {
                'title': 'Nike crewneck sweatshirt grey size M',
                'url': 'https://www.depop.com/products/example-2/',
                'price': 28.0,
                'currency': 'USD',
                'sold': false,
                'match': 'same',
              },
              {
                'title': 'Champion reverse weave crewneck grey',
                'url': 'https://www.depop.com/products/example-3/',
                'price': 35.5,
                'currency': 'USD',
                'match': 'similar',
              },
            ],
            'retail': [
              {
                'title': 'Nike Sportswear Club Fleece Crew',
                'url': 'https://www.nike.com/t/sportswear-club-fleece-crew',
                'price': 60.0,
                'currency': 'USD',
                'seller': 'nike.com',
                'match': 'similar',
              },
            ],
            'excluded': {'notUsd': 2, 'unverifiedPrice': 1, 'notComparable': 4},
          },
          'diagnostics': {
            'stagesRun': ['tavily', 'gemini'],
            'elapsedMs': 3920,
          },
        }).searchPrices(request);

        expect(search.status, PriceSearchStatus.ok);
        expect(search.provider, 'tavily');
        expect(search.searchedAt, DateTime.utc(2026, 10, 17, 14, 5));
        // In cents, to the nearest, whatever the dollars looked like.
        expect(search.comparables.map((c) => c.priceCents), [3200, 2800, 3550]);
        expect(search.comparables.map((c) => c.sold), [true, false, null]);
        expect(search.comparables.map((c) => c.match), [
          ComparableMatch.same,
          ComparableMatch.same,
          ComparableMatch.similar,
        ]);
        expect(search.comparables.first.url.host, 'www.depop.com');
        expect(search.retail.single.priceCents, 6000);
        expect(search.retail.single.seller, 'nike.com');
        expect(search.excluded.notUsd, 2);
        expect(search.excluded.total, 7);
      },
    );

    group('a search that found nothing is data, not an error', () {
      for (final (name, status) in [
        ('notConfigured', PriceSearchStatus.notConfigured),
        ('quotaExceeded', PriceSearchStatus.quotaExceeded),
        ('unavailable', PriceSearchStatus.unavailable),
      ]) {
        test(name, () async {
          final search = await gatewayReturning(
            answer(name),
          ).searchPrices(request);

          expect(search.status, status);
          expect(search.comparables, isEmpty);
          expect(search.retail, isEmpty);
          expect(search.searchedAt, isNull);
          // The phrases that were tried survive, so a second look-up starts
          // from them.
          expect(search.queries.depop, 'Nike vintage crewneck sweatshirt grey');
          expect(
            search.queries.retail,
            'Nike Club Fleece crew sweatshirt grey',
          );
        });
      }

      test('ok', () async {
        final search = await gatewayReturning(
          answer('ok'),
        ).searchPrices(request);

        // A search can succeed and find nothing usable, which is a result too.
        expect(search.status, PriceSearchStatus.ok);
        expect(search.comparables, isEmpty);
      });

      test(
        'a status this build has not heard of reads as unavailable',
        () async {
          final search = await gatewayReturning(
            answer('rateLimited'),
          ).searchPrices(request);

          expect(search.status, PriceSearchStatus.unavailable);
        },
      );
    });

    test(
      'a comparable the app cannot use is left out, not thrown on',
      () async {
        final search = await gatewayReturning(
          answer(
            'ok',
            comparables: [
              {
                'title': 'Not a link to open',
                'url': 'http://www.depop.com/products/plain-http/',
                'price': 30.0,
                'currency': 'USD',
                'match': 'same',
              },
              {
                'title': 'In euros',
                'url': 'https://www.depop.com/products/in-euros/',
                'price': 30.0,
                'currency': 'EUR',
                'match': 'same',
              },
              {
                'title': 'Usable',
                'url': 'https://www.depop.com/products/usable/',
                'price': 30.0,
                'currency': 'USD',
                'match': 'same',
              },
            ],
          ),
        ).searchPrices(request);

        expect(search.comparables.map((c) => c.title), ['Usable']);
      },
    );

    test('a 503 is a ScanFailure that is worth retrying', () async {
      await expectLater(
        gatewayReturning({
          'detail': 'Price search is unavailable.',
        }, status: 503).searchPrices(request),
        throwsA(
          isA<ScanFailure>()
              .having((f) => f.message, 'message', contains('unavailable'))
              .having((f) => f.isRetryable, 'isRetryable', true),
        ),
      );
    });

    test('a 503 with nothing readable in it still says something', () async {
      final client = MockClient(
        (_) async => http.Response('<html>Bad gateway</html>', 503),
      );
      final gateway = AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: client,
      );

      await expectLater(
        gateway.searchPrices(request),
        throwsA(
          isA<ScanFailure>().having(
            (f) => f.message,
            'message',
            isNot(contains('html')),
          ),
        ),
      );
    });

    test('a server that cannot be reached is a ScanFailure', () async {
      final gateway = AiGateway(
        baseUrl: Uri.parse('https://washing-advice.onrender.com/'),
        client: MockClient((_) async => throw http.ClientException('offline')),
      );

      await expectLater(
        gateway.searchPrices(request),
        throwsA(isA<ScanFailure>()),
      );
    });

    test('asks once', () async {
      final gateway = gatewayReturning(answer('ok'));

      await gateway.searchPrices(request);

      expect(requests, 1);
    });
  });
}

/// What the server returns for a described photograph, as the contract's
/// example does.
const _described = {
  'result': {
    'title': 'Nike vintage crewneck sweatshirt grey',
    'itemType': 'sweatshirt',
    'brand': {'value': 'Nike', 'confidence': 0.93, 'source': 'aiInference'},
    'colors': ['Grey'],
    'material': '80% cotton, 20% polyester',
    'sizeOnTag': {'value': 'M', 'confidence': 0.9, 'source': 'aiInference'},
    'styleWords': ['vintage', 'crewneck', 'embroidered logo', '90s'],
    'era': '90s',
    'visibleFlaws': ['small mark on the left cuff'],
    'searchQueries': {
      'depop': 'Nike vintage crewneck sweatshirt grey',
      'retail': 'Nike Club Fleece crew sweatshirt grey',
    },
  },
  'diagnostics': {
    'stagesRun': ['gemini'],
    'stageAnswered': 'gemini',
    'elapsedMs': 2140,
  },
};

/// One part of a multipart form, as the server reads it.
class _Part {
  _Part({
    required this.name,
    required this.bytes,
    this.filename,
    this.contentType,
  });

  final String name;
  final String? filename;
  final String? contentType;
  final List<int> bytes;

  String get text => utf8.decode(bytes);
}

/// The parts of a multipart [request], in the order they were sent.
///
/// Read from the bytes on the wire, not from the request the gateway built: a
/// field the gateway adds to a `MultipartRequest` and one the server receives
/// are only the same thing if nothing between them changed it.
List<_Part> _partsOf(http.Request request) {
  final boundary = RegExp(
    r'boundary=([^;]+)',
  ).firstMatch(request.headers['content-type']!)!.group(1)!;
  // Latin-1, which maps each byte to one character and back, so that splitting
  // the text splits the bytes.
  final body = latin1.decode(request.bodyBytes);

  final parts = <_Part>[];
  for (final raw in body.split('--$boundary')) {
    final blank = raw.indexOf('\r\n\r\n');
    // The preamble, and the closing `--`.
    if (blank < 0) continue;
    final head = raw.substring(0, blank);
    // Each part is followed by a line break before the next boundary.
    final content = raw.substring(blank + 4, raw.length - 2);
    parts.add(
      _Part(
        name: RegExp(r'name="([^"]*)"').firstMatch(head)!.group(1)!,
        filename: RegExp(r'filename="([^"]*)"').firstMatch(head)?.group(1),
        contentType: RegExp(
          r'content-type: ([^\r\n]+)',
          caseSensitive: false,
        ).firstMatch(head)?.group(1),
        bytes: latin1.encode(content),
      ),
    );
  }
  return parts;
}
