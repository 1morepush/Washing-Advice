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

void main() {
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
}
