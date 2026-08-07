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

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
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
}
