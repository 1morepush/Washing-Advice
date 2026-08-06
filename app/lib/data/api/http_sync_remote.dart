/// [SyncRemote] over HTTP.
///
/// The counterpart to `/v1/sync` on the server, and deliberately the dumbest
/// object in the sync story: it serialises, sends, decodes, and has no opinion
/// about conflicts. Every reconciliation rule lives in `SyncEngine` and runs on
/// the device, because that is the copy that has to work when there is no
/// network at all.
///
/// It throws on failure rather than returning a result type. `SyncEngine.sync`
/// already catches and turns that into a `SyncReport` — the network being down
/// is the expected case for an offline-first app, and the engine is the one
/// place that should have to say so.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:wardrobe_core/wardrobe_core.dart';

/// A sync could not be completed.
class SyncFailure implements Exception {
  const SyncFailure(this.message, {this.isRetryable = true});

  final String message;

  /// Whether trying again later is worth it.
  ///
  /// A dropped connection is retryable; a rejected token is not, and telling
  /// someone to try again when their credential is wrong wastes their evening.
  final bool isRetryable;

  @override
  String toString() => message;
}

class HttpSyncRemote implements SyncRemote {
  HttpSyncRemote({
    required this.baseUrl,
    required this.token,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final Uri baseUrl;

  /// The bearer credential. Whoever holds it owns the wardrobe.
  final String token;

  final http.Client _client;

  Uri get _endpoint => baseUrl.resolve('v1/sync');

  /// The credential goes in a header, never in the URL.
  ///
  /// Query strings are logged by proxies, written to server access logs and
  /// kept in browser history. A bearer token in one is a token in all three.
  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  @override
  Future<SyncPayload> pull({DateTime? since}) async {
    final uri = since == null
        ? _endpoint
        : _endpoint.replace(
            queryParameters: {'since': since.toUtc().toIso8601String()},
          );

    final response = await _send(() => _client.get(uri, headers: _headers));
    final body = _decode(response);

    return SyncPayload(
      items: [
        for (final raw in (body['items'] as List<Object?>? ?? const []))
          WardrobeItem.fromJson(raw! as Map<String, Object?>),
      ],
      events: [
        for (final raw in (body['events'] as List<Object?>? ?? const []))
          WardrobeEvent.fromJson(raw! as Map<String, Object?>),
      ],
    );
  }

  @override
  Future<DateTime> push(SyncPayload payload) async {
    final response = await _send(
      () => _client.post(
        _endpoint,
        headers: _headers,
        body: jsonEncode({
          'items': [for (final item in payload.items) item.toJson()],
          'events': [for (final event in payload.events) event.toJson()],
        }),
      ),
    );

    final accepted = _decode(response)['acceptedAt'];
    if (accepted is! String) {
      throw const SyncFailure(
        'The server did not say when it accepted the changes.',
        // Not retryable: the same request will get the same malformed answer,
        // and advancing the cursor without a real timestamp would skip data.
        isRetryable: false,
      );
    }
    return DateTime.parse(accepted).toUtc();
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    final http.Response response;
    try {
      response = await request();
    } on Exception catch (error) {
      throw SyncFailure('Could not reach the server: $error');
    }

    return switch (response.statusCode) {
      >= 200 && < 300 => response,
      401 => const SyncFailure(
        'The sync token was rejected. Check it in Settings.',
        isRetryable: false,
      ).throwIt(),
      404 => const SyncFailure(
        'This server does not offer sync.',
        isRetryable: false,
      ).throwIt(),
      413 => const SyncFailure(
        'Too many changes to send at once. This will resolve itself as the '
        'backlog clears.',
      ).throwIt(),
      // 5xx is the server's problem and is worth retrying; anything else in
      // the 4xx range is this client sending something wrong, and retrying an
      // identical bad request forever is how a battery gets flattened. The
      // body is not included: it may quote back what was sent.
      final code when code >= 500 => SyncFailure(
        'The server had a problem (HTTP $code).',
      ).throwIt(),
      final code => SyncFailure(
        'The server refused the request (HTTP $code).',
        isRetryable: false,
      ).throwIt(),
    };
  }

  Map<String, Object?> _decode(http.Response response) {
    try {
      return jsonDecode(response.body) as Map<String, Object?>;
    } on Exception {
      throw const SyncFailure(
        'The server sent something this app could not read.',
        isRetryable: false,
      );
    }
  }

  void close() => _client.close();
}

extension on SyncFailure {
  /// Lets a `switch` expression arm throw while still being an expression.
  Never throwIt() => throw this;
}
