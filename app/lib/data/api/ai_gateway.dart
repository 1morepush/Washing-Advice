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
import 'stain_dto.dart';

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

/// How long a request runs before it is worth saying the server is asleep.
///
/// A free-tier host stops itself when idle and takes tens of seconds to come
/// back. That is normal rather than broken, but a spinner cannot say so, and
/// a wait with no explanation reads as a hang. Past this point a screen should
/// say what is happening; before it, the request is simply in flight.
const wakingAfter = Duration(seconds: 8);

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

  /// Identifies a washing machine's real programme line-up from its brand and
  /// model alone — built once, from the AI's own knowledge of the appliance,
  /// rather than asked again for every garment. The result is stored exactly
  /// like a chosen brand archetype: same type, same [ProgramMatcher].
  Future<WasherProfile> identifyWasher({
    required String brand,
    required String model,
  }) async {
    final json = await _postJson('machine/washer', {
      'brand': brand,
      'model': model,
    });
    return WasherProfile.fromJson(json);
  }

  /// The dryer counterpart of [identifyWasher].
  Future<DryerProfile> identifyDryer({
    required String brand,
    required String model,
  }) async {
    final json = await _postJson('machine/dryer', {
      'brand': brand,
      'model': model,
    });
    return DryerProfile.fromJson(json);
  }

  /// How to get a stain out of one particular garment.
  ///
  /// The garment is described in the words the app already shows on its own
  /// screens rather than as a structure: the model reasons better about
  /// "70% Wool, 30% Polyester" than about an enum map, and it keeps the server
  /// from growing a second, drifting copy of the wardrobe model.
  ///
  /// What comes back is **unvetted**. Nothing here checks it against the
  /// garment's care — that is `StainSafety`'s job in the core, against the real
  /// values rather than the summary sent up. A caller that showed this
  /// directly would be showing a wool jumper a bleach soak.
  Future<StainAdvice> adviseOnStain({
    required String substance,
    required String fabric,
    required String care,
    String? color,
    String? note,
    ScanImage? photo,
  }) async {
    final json = await _postForm(
      'care/stain',
      fields: {
        'substance': substance,
        'fabric': fabric,
        'care': care,
        'color': ?color,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
      photo: photo,
    );
    return StainAdvice.fromJson(json);
  }

  /// The same advice, delivered as each step is written.
  ///
  /// Still **unvetted**, exactly as [adviseOnStain] is, and the streaming makes
  /// that more pressing rather than less: the vetting has to happen per step,
  /// as each one lands, because a caller that waited for the end to check
  /// anything would have given up the entire benefit.
  ///
  /// Ends without a [StainDone] if the connection dropped. The caller is
  /// expected to notice — a truncated treatment reads exactly like a short one,
  /// and the missing tail is usually the step about checking the mark before it
  /// goes near heat.
  Stream<StainStreamEvent> streamStainAdvice({
    required String substance,
    required String fabric,
    required String care,
    String? color,
    String? note,
    ScanImage? photo,
  }) async* {
    final request =
        http.MultipartRequest('POST', baseUrl.resolve('v1/care/stain/stream'))
          ..fields.addAll({
            'substance': substance,
            'fabric': fabric,
            'care': care,
            'color': ?color,
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          });

    if (photo != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          photo.bytes,
          filename: 'stain.${photo.mimeType.split('/').last}',
          contentType: _mediaType(photo.mimeType),
        ),
      );
    }

    final http.StreamedResponse streamed;
    try {
      streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 90));
    } on Exception catch (error) {
      throw ScanFailure('Could not reach the server. $error');
    }

    if (streamed.statusCode != 200) {
      // Still an ordinary failure: nothing has been shown yet, and the server
      // rejects a bad request before it starts streaming.
      throw _failureFor(await http.Response.fromStream(streamed));
    }

    await for (final line
        in streamed.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;

      final payload = line.substring('data:'.length).trim();
      if (payload.isEmpty) continue;

      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, Object?>) continue;

      if (StainStreamEvent.fromJson(decoded)
          case final StainStreamEvent event) {
        if (event is StainDone) lastDiagnostics = event.diagnostics;
        yield event;
      }
    }
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
  ///
  /// The timeout is generous because a free-tier host sleeps when idle and
  /// takes the better part of a minute to wake. Five seconds — long enough for
  /// any server that is actually running — reported a correctly configured
  /// backend as unreachable, which is the one answer this call exists to rule
  /// out. Waiting is the honest behaviour; [wakingAfter] is how the screen
  /// explains the wait.
  Future<({bool reachable, String status, String? problem})> health() async {
    try {
      final response = await _client
          .get(baseUrl.resolve('v1/health'))
          .timeout(const Duration(seconds: 60));
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
      // A cold start on a sleeping host can take most of a minute on its own,
      // before the model has been called at all. Sixty seconds covered the
      // model but not the wait in front of it, so a scan could time out having
      // never actually failed.
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 90));
      response = await http.Response.fromStream(streamed);
    } on Exception catch (error) {
      throw ScanFailure('Could not reach the server. $error');
    }

    return _decodeResult(response);
  }

  /// A form post with an optional file, for a call that is mostly text.
  ///
  /// Neither [_post] nor [_postJson] fits: the stain endpoint takes several
  /// text fields *and* a photograph that is usually absent, and sending the
  /// text as JSON would mean two request shapes for one endpoint depending on
  /// whether a picture was attached.
  Future<Map<String, Object?>> _postForm(
    String path, {
    required Map<String, String> fields,
    ScanImage? photo,
  }) async {
    final request = http.MultipartRequest('POST', baseUrl.resolve('v1/$path'))
      ..fields.addAll(fields);

    if (photo != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          photo.bytes,
          filename: 'stain.${photo.mimeType.split('/').last}',
          contentType: _mediaType(photo.mimeType),
        ),
      );
    }

    final http.Response response;
    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 90));
      response = await http.Response.fromStream(streamed);
    } on Exception catch (error) {
      throw ScanFailure('Could not reach the server. $error');
    }

    return _decodeResult(response);
  }

  /// The same request as [_post], for a call with no file to upload — brand
  /// and model text, not an image.
  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            baseUrl.resolve('v1/$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 90));
    } on Exception catch (error) {
      throw ScanFailure('Could not reach the server. $error');
    }

    return _decodeResult(response);
  }

  /// The tail every call shares once a response has actually arrived: fail on
  /// a bad status, record diagnostics, and hand back the `result` object.
  /// Factored out because [_postJson] needed it a second time — [_post] and
  /// [_postJson] differ only in how the request is built and sent.
  Map<String, Object?> _decodeResult(http.Response response) {
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
