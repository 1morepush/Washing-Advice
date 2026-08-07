/// The backend client.
///
/// Implements [VisionPort], the core's own interface, so nothing downstream
/// knows a network is involved. Swapping this for an on-device pipeline later
/// is a change to one provider binding, not to any screen.
///
/// Deliberately thin: it uploads bytes and decodes the reply. Every decision
/// about which model to call, in what order, and whether the answer was already
/// known lives on the server, where it can be changed without shipping an app
/// update. That is the whole reason the pipeline is server-side.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'scan_dto.dart';

/// A scan could not be completed.
///
/// Carries whether retrying is worth the user's time, because "no internet" and
/// "that photo is not a care label" need different words on screen.
class ScanFailure implements Exception {
  const ScanFailure(this.message, {this.isRetryable = true});

  final String message;
  final bool isRetryable;

  @override
  String toString() => message;
}

class AiGateway implements VisionPort {
  AiGateway({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  /// Where the M2 server lives, e.g. `http://localhost:8000`.
  final Uri baseUrl;
  final http.Client _client;

  /// Diagnostics from the most recent scan.
  ///
  /// Kept here rather than returned alongside each result so the [VisionPort]
  /// signature stays the core's, unpolluted by transport concerns. The scan
  /// screen reads it to show that an answer came from memory in 4 ms rather
  /// than from a model call.
  ScanDiagnostics? lastDiagnostics;

  @override
  Future<GarmentScanResult> scanGarment(List<ScanImage> images) async {
    if (images.isEmpty) {
      throw const ScanFailure(
        'No photograph was provided.',
        isRetryable: false,
      );
    }
    final json = await _post(
      'scan/garment',
      files: [for (final image in images) ('images', image)],
    );
    return garmentResultFromJson(json);
  }

  @override
  Future<CareTagScanResult> scanCareTag(ScanImage image) async {
    final json = await _post('scan/care-tag', files: [('image', image)]);
    return careTagResultFromJson(json);
  }

  @override
  Future<PileScanResult> scanPile(ScanImage image) async {
    final json = await _post('scan/pile', files: [('image', image)]);
    return pileResultFromJson(json);
  }

  /// The garment with its background removed.
  ///
  /// Returns null when the server could not separate it — a plain refusal
  /// rather than an exception, because a missing cutout is a cosmetic loss and
  /// must never stop an item being saved. The wardrobe falls back to the
  /// colour swatch and the user is none the wiser.
  Future<Uint8List?> cutout(ScanImage image) async {
    final request = http.MultipartRequest(
      'POST',
      baseUrl.resolve('v1/image/cutout'),
    );
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        image.bytes,
        filename: 'garment.${image.mimeType.split('/').last}',
        contentType: _mediaType(image.mimeType),
      ),
    );

    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 45));
      if (streamed.statusCode != 200) {
        await streamed.stream.drain<void>();
        return null;
      }
      return Uint8List.fromList(await streamed.stream.toBytes());
    } on Exception {
      return null;
    }
  }

  /// Whether the server is reachable and configured.
  ///
  /// `/health` reports `degraded` at 200 rather than failing, so a
  /// misconfigured provider can be told apart from an unreachable host — which
  /// is the difference between "check your settings" and "check your wifi".
  Future<({bool reachable, String status, String? problem})> health() async {
    try {
      final response = await _client
          .get(baseUrl.resolve('v1/health'))
          .timeout(const Duration(seconds: 5));
      final json = jsonDecode(response.body) as Map<String, Object?>;
      return (
        reachable: true,
        status: json['status'] as String? ?? 'unknown',
        problem: json['problem'] as String?,
      );
    } on Exception catch (error) {
      return (reachable: false, status: 'unreachable', problem: '$error');
    }
  }

  void close() => _client.close();

  Future<Map<String, Object?>> _post(
    String path, {
    required List<(String, ScanImage)> files,
  }) async {
    final request = http.MultipartRequest('POST', baseUrl.resolve('v1/$path'));
    for (final (field, image) in files) {
      request.files.add(
        http.MultipartFile.fromBytes(
          field,
          image.bytes,
          filename: 'upload.${image.mimeType.split('/').last}',
          contentType: _mediaType(image.mimeType),
        ),
      );
    }

    final http.Response response;
    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 60));
      response = await http.Response.fromStream(streamed);
    } on Exception catch (error) {
      throw ScanFailure('Could not reach the server. $error');
    }

    if (response.statusCode != 200) {
      throw _failureFor(response);
    }

    final body = jsonDecode(response.body) as Map<String, Object?>;
    lastDiagnostics = body['diagnostics'] == null
        ? null
        : ScanDiagnostics.fromJson(
            body['diagnostics']! as Map<String, Object?>,
          );

    final result = body['result'];
    if (result is! Map<String, Object?>) {
      throw ScanContractError('the response had no "result"');
    }
    return result;
  }

  /// Turns an error response into something worth showing a user.
  ///
  /// The server's `detail` is written for people, so it is preferred when
  /// present. The status code decides whether retrying makes sense: a 422 means
  /// this photograph will never work, and telling someone to try again would
  /// waste their time.
  ScanFailure _failureFor(http.Response response) {
    String? detail;
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['detail'] is String) {
        detail = body['detail'] as String;
      }
    } on FormatException {
      // A non-JSON error body is a proxy or a crash. Nothing to salvage, and
      // it is deliberately not echoed — an error page can contain anything.
      detail = null;
    }

    return switch (response.statusCode) {
      413 => ScanFailure(
        detail ?? 'That photo is too large.',
        isRetryable: false,
      ),
      422 => ScanFailure(
        detail ?? 'That photo could not be read.',
        isRetryable: false,
      ),
      503 => ScanFailure(detail ?? 'Scanning is unavailable right now.'),
      _ => ScanFailure(detail ?? 'The scan failed (${response.statusCode}).'),
    };
  }
}

/// The content type to send a part as.
///
/// Returns null for anything malformed rather than throwing: the server sniffs
/// the magic bytes anyway and will reject a file that is not really an image,
/// so a missing header produces a clear 422 instead of a client-side crash.
MediaType? _mediaType(String mimeType) {
  final parts = mimeType.split('/');
  return parts.length == 2 ? MediaType(parts[0], parts[1]) : null;
}
