/// What this version of the app sends to the server, and what it needs back.
///
/// The server keeps answering every version of the app that can still be
/// chosen under "Use an earlier version", and a release that renames a field
/// would break the older ones without any test noticing: the Dart contract
/// tests only ever look at the *newest* app. So each release's wire format is
/// recorded under `contracts/compat/<version>/`, and the server's tests replay
/// every recorded version against the server (`server/tests/test_compat.py`).
///
/// This file is both halves of recording one, and the guard that the committed
/// record for *this* version is still true.
///
/// * **Requests.** The real [AiGateway] is driven through every call it makes
///   with a recording client, and what went over the wire is written down:
///   method, path, content type, fields, JSON, and which photograph was sent.
/// * **Required response fields.** The same calls are decoded against a sample
///   of what the server answers (`contracts/compat/samples/`), then again with
///   each field removed in turn. A field whose absence makes the app's decoder
///   throw is one this version *requires*, and goes on the list. Derived, never
///   hand-written, so it cannot be wrong in the direction of being generous.
///
/// Run on its own, with nothing set, it only checks: the requests the app
/// sends now must equal the committed ones, and the derived list must equal
/// the committed list. If this fails you changed what the app sends or needs;
/// if that was meant, record again (`app/tool/capture_compat.sh`).
///
/// Recording is `COMPAT_WRITE=requests|required` with `COMPAT_VERSION` and,
/// from another checkout, `COMPAT_DIR`; the script does that.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';

import '../support/fixtures.dart';

// --- Inputs -----------------------------------------------------------------

/// Where the fixtures live. The script points this at the main checkout when
/// it records an older release from a copy of it.
final _root = Directory(
  Platform.environment['COMPAT_DIR'] ?? '../contracts/compat',
);

Uint8List _asset(String name) =>
    Uint8List.fromList(File('${_root.path}/assets/$name').readAsBytesSync());

/// The photographs sent. Named so a request can say *which* it sent, and the
/// server can be sent the same bytes, rather than every fixture holding a copy.
Map<String, Uint8List> get _assets => {
  'photo.png': _asset('photo.png'),
  'cutout.png': _asset('cutout.png'),
};

ScanImage get _photo =>
    ScanImage(bytes: _assets['photo.png']!, mimeType: 'image/png');

ScanImage get _plain =>
    ScanImage(bytes: _assets['cutout.png']!, mimeType: 'image/png');

List<WardrobeItem> get _wardrobe => [
  confidentItem(id: 'a', name: 'Navy shirt', colorName: 'navy'),
  confidentItem(
    id: 'b',
    name: 'Grey jeans',
    type: ItemType.jeans,
    hex: '#808080',
  ),
];

// --- The calls --------------------------------------------------------------

/// What kind of answer an endpoint gives.
enum _Kind { json, sse, image }

class _Endpoint {
  const _Endpoint(this.id, this.kind, this.call, {this.worked});

  final String id;
  final _Kind kind;
  final Future<Object?> Function(AiGateway gateway) call;

  /// For a call that reports failure by returning rather than throwing.
  final bool Function(Object? result)? worked;
}

final _endpoints = <_Endpoint>[
  // @endpoint scan_garment
  _Endpoint('scan_garment', _Kind.json, (g) => g.scanGarment([_photo, _photo])),
  // @endpoint scan_care_tag
  _Endpoint('scan_care_tag', _Kind.json, (g) => g.scanCareTag([_photo])),
  // @endpoint scan_pile
  _Endpoint('scan_pile', _Kind.json, (g) => g.scanPile(_photo)),
  // @endpoint scan_worn
  _Endpoint('scan_worn', _Kind.json, (g) => g.scanWorn(_photo)),
  // @endpoint machine_washer
  _Endpoint(
    'machine_washer',
    _Kind.json,
    (g) => g.identifyWasher(brand: 'Miele', model: 'WWD 120'),
  ),
  // @endpoint machine_dryer
  _Endpoint(
    'machine_dryer',
    _Kind.json,
    (g) => g.identifyDryer(brand: 'Miele', model: 'TWF 720'),
  ),
  // @endpoint care_stain
  _Endpoint(
    'care_stain',
    _Kind.json,
    (g) => g.adviseOnStain(
      substance: 'red wine',
      fabric: '100% cotton',
      care: 'Machine wash 40C',
      color: 'white',
      note: 'on the cuff',
    ),
  ),
  // @endpoint care_stain_photo
  _Endpoint(
    'care_stain_photo',
    _Kind.json,
    (g) => g.adviseOnStain(
      substance: 'ink',
      fabric: '80% wool, 20% polyamide',
      care: 'Hand wash cold',
      photo: _photo,
    ),
  ),
  // @endpoint care_stain_stream
  _Endpoint(
    'care_stain_stream',
    _Kind.sse,
    (g) => g
        .streamStainAdvice(
          substance: 'red wine',
          fabric: '100% cotton',
          care: 'Machine wash 40C',
        )
        .toList(),
  ),
  // @endpoint care_condition
  _Endpoint(
    'care_condition',
    _Kind.json,
    (g) => g.readCondition(
      images: [_photo],
      garment: 'Navy shirt',
      fabric: '100% cotton',
      known: 'collar frayed',
    ),
  ),
  // @endpoint style_outfits
  _Endpoint(
    'style_outfits',
    _Kind.json,
    (g) => g.proposeOutfits(
      wardrobe: _wardrobe,
      occasion: 'Everyday',
      season: 'autumn',
      count: 3,
    ),
  ),
  // @endpoint style_outfits_gaps
  _Endpoint(
    'style_outfits_gaps',
    _Kind.json,
    (g) => g.proposeOutfits(
      wardrobe: _wardrobe,
      occasion: 'Work',
      note: 'smart casual',
      suggestGaps: true,
    ),
  ),
  // @endpoint chat_ask
  _Endpoint(
    'chat_ask',
    _Kind.json,
    (g) => g.askQuestion(
      question: 'What can I wear with the grey jeans?',
      wardrobe: _wardrobe,
      history: const [
        (fromUser: true, text: 'Hello'),
        (fromUser: false, text: 'Hi, what would you like to know?'),
      ],
    ),
  ),
  // @endpoint sell_describe
  _Endpoint(
    'sell_describe',
    _Kind.json,
    (g) => g.describeListing(
      [_photo],
      context: const {
        'known': {'itemType': 'sweatshirt', 'brand': 'Nike'},
        'notes': 'Bought in 2019',
      },
    ),
  ),
  // @endpoint sell_prices
  _Endpoint(
    'sell_prices',
    _Kind.json,
    (g) => g.searchPrices(const {
      'queries': {
        'depop': 'Nike vintage crewneck sweatshirt grey',
        'retail': 'Nike Club Fleece crew sweatshirt grey',
      },
      'itemType': 'sweatshirt',
      'title': 'Nike vintage crewneck sweatshirt grey',
      'brand': 'Nike',
      'colors': ['Grey'],
    }),
  ),
  // @endpoint image_cutout
  _Endpoint(
    'image_cutout',
    _Kind.image,
    (g) => g.cutout(_plain),
    worked: (result) => result != null,
  ),
  // @endpoint health
  _Endpoint(
    'health',
    _Kind.json,
    (g) => g.health(),
    worked: (result) =>
        (result as ({bool reachable, String status, String? problem}))
            .reachable,
  ),
  // @end
];

// --- Recording --------------------------------------------------------------

/// One request as it went over the wire, with the photographs named.
Map<String, Object?> _describe(
  http.BaseRequest request,
  List<int> body,
  Map<String, Uint8List> assets,
) {
  final contentType = request.headers['content-type'] ?? '';
  final record = <String, Object?>{
    'method': request.method,
    'path': request.url.path,
    if (request.url.queryParameters.isNotEmpty)
      'query': request.url.queryParameters,
  };

  if (contentType.startsWith('application/json')) {
    record['contentType'] = 'application/json';
    record['json'] = jsonDecode(utf8.decode(body));
  } else if (contentType.startsWith('multipart/form-data')) {
    record['contentType'] = 'multipart/form-data';
    final boundary = RegExp(
      'boundary=([^;]+)',
    ).firstMatch(contentType)!.group(1)!;
    final fields = <String, Object?>{};
    final files = <Map<String, Object?>>[];
    // Latin-1 keeps every byte as one character, so the photographs survive
    // being split as text and can be compared back to the assets exactly.
    final text = latin1.decode(body);
    for (final part in text.split('--$boundary').skip(1)) {
      if (part.startsWith('--')) break;
      final split = part.indexOf('\r\n\r\n');
      final head = part.substring(0, split);
      var content = part.substring(split + 4);
      if (content.endsWith('\r\n')) {
        content = content.substring(0, content.length - 2);
      }
      final name = RegExp('name="([^"]*)"').firstMatch(head)!.group(1)!;
      final filename = RegExp('filename="([^"]*)"').firstMatch(head)?.group(1);
      if (filename == null) {
        fields[name] = utf8.decode(latin1.encode(content));
        continue;
      }
      final bytes = latin1.encode(content);
      final asset = assets.entries
          .where((e) => _same(e.value, bytes))
          .map((e) => e.key)
          .firstOrNull;
      files.add({
        'field': name,
        'filename': filename,
        'contentType': RegExp(
          r'Content-Type: ([^\r\n]+)',
          caseSensitive: false,
        ).firstMatch(head)?.group(1),
        'asset': asset ?? (throw StateError('$filename is not a known asset')),
      });
    }
    if (fields.isNotEmpty) record['fields'] = fields;
    record['files'] = files;
  } else if (body.isNotEmpty) {
    throw StateError('Unrecognised request body type "$contentType".');
  }
  return record;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A gateway whose server is [answer]. The first request it gets is handed to
/// [record].
AiGateway _gateway(
  Future<http.StreamedResponse> Function(http.BaseRequest, List<int>) answer,
) => AiGateway(
  baseUrl: Uri.parse('https://example.test/'),
  client: MockClient.streaming((request, stream) async {
    return answer(request, await stream.toBytes());
  }),
);

http.StreamedResponse _respond(
  _Kind kind,
  List<int> body, {
  int status = 200,
}) => http.StreamedResponse(
  Stream.value(body),
  status,
  headers: {
    'content-type': switch (kind) {
      _Kind.json => 'application/json',
      _Kind.sse => 'text/event-stream',
      _Kind.image => 'image/png',
    },
  },
);

/// What was sent by [endpoint], whatever the app then made of the answer.
Future<Map<String, Object?>> _sent(_Endpoint endpoint) async {
  Map<String, Object?>? sent;
  final gateway = _gateway((request, body) async {
    sent ??= _describe(request, body, _assets);
    // Any well-formed answer will do: the decoder may well refuse it, and
    // that is fine, the request is what is being recorded.
    return _respond(
      endpoint.kind,
      endpoint.kind == _Kind.json ? utf8.encode('{}') : const [],
    );
  });
  try {
    await endpoint.call(gateway);
  } on Object {
    // Expected for most: see above.
  }
  return sent ?? (throw StateError('${endpoint.id} sent nothing'));
}

// --- Required fields --------------------------------------------------------

File? _sample(_Endpoint endpoint) {
  final ext = switch (endpoint.kind) {
    _Kind.json => 'json',
    _Kind.sse => 'sse',
    _Kind.image => 'png',
  };
  final file = File('${_root.path}/samples/${endpoint.id}.$ext');
  return file.existsSync() ? file : null;
}

/// Every key an object has anywhere in [node], as `a.b[].c`, `[]` standing for
/// "in every element of the list".
Set<String> _keyPaths(Object? node, [String prefix = '']) {
  final paths = <String>{};
  if (node is Map) {
    for (final entry in node.entries) {
      final path = prefix.isEmpty ? '${entry.key}' : '$prefix.${entry.key}';
      paths.add(path);
      paths.addAll(_keyPaths(entry.value, path));
    }
  } else if (node is List) {
    for (final element in node) {
      paths.addAll(_keyPaths(element, '$prefix[]'));
    }
  }
  return paths;
}

/// A copy of [node] with the key at [path] removed from every place it is.
Object? _without(Object? node, List<String> steps) {
  if (steps.isEmpty) return node;
  final step = steps.first;
  if (step == '[]') {
    return [for (final e in node! as List) _without(e, steps.skip(1).toList())];
  }
  final map = Map<String, Object?>.of(node! as Map<String, Object?>);
  if (steps.length == 1) {
    map.remove(step);
  } else if (map.containsKey(step)) {
    map[step] = _without(map[step], steps.skip(1).toList());
  }
  return map;
}

List<String> _steps(String path) => [
  for (final piece in path.split('.'))
    ...() {
      final out = <String>[];
      var rest = piece;
      while (rest.endsWith('[]')) {
        out.insert(0, '[]');
        rest = rest.substring(0, rest.length - 2);
      }
      return [if (rest.isNotEmpty) rest, ...out];
    }(),
];

Future<bool> _decodes(_Endpoint endpoint, Object? body, File sample) async {
  final bytes = endpoint.kind == _Kind.json
      ? utf8.encode(jsonEncode(body))
      : sample.readAsBytesSync();
  final gateway = _gateway((_, _) async => _respond(endpoint.kind, bytes));
  try {
    final result = await endpoint.call(gateway);
    return endpoint.worked?.call(result) ?? true;
  } on Object {
    return false;
  }
}

/// The fields this build's decoders cannot do without, or null when there is
/// no sample to ask them against.
Future<List<String>?> _required(_Endpoint endpoint) async {
  final sample = _sample(endpoint);
  if (sample == null) return null;
  if (endpoint.kind != _Kind.json) {
    if (!await _decodes(endpoint, null, sample)) {
      throw StateError('${endpoint.id}: the sample does not decode at all');
    }
    return const [];
  }
  final body = jsonDecode(sample.readAsStringSync());
  if (!await _decodes(endpoint, body, sample)) {
    throw StateError('${endpoint.id}: the sample does not decode at all');
  }
  final required = <String>[];
  for (final path in _keyPaths(body).toList()..sort()) {
    if (!await _decodes(endpoint, _without(body, _steps(path)), sample)) {
      required.add(path);
    }
  }
  return required;
}

// --- The test ---------------------------------------------------------------

String get _version {
  final fromEnv = Platform.environment['COMPAT_VERSION'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  final match = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync())!;
  return match.group(1)!;
}

const _json = JsonEncoder.withIndent('  ');

void main() {
  final write = Platform.environment['COMPAT_WRITE'];
  final dir = Directory('${_root.path}/$_version');

  group('what $_version sends', () {
    for (final endpoint in _endpoints) {
      test(endpoint.id, () async {
        if (write == 'required') return;
        final sent = await _sent(endpoint);
        final file = File('${dir.path}/requests/${endpoint.id}.json');
        if (write == 'requests') {
          file.createSync(recursive: true);
          file.writeAsStringSync('${_json.convert(sent)}\n');
          return;
        }
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'no record of ${endpoint.id} for $_version: run '
              'app/tool/capture_compat.sh $_version',
        );
        expect(
          sent,
          jsonDecode(file.readAsStringSync()),
          reason:
              'the app now sends something different to ${endpoint.id}. If '
              'that is meant, record it again with app/tool/capture_compat.sh '
              '— and know that every older app is still out there sending the '
              'old shape.',
        );
      });
    }
  });

  group('what $_version needs back', () {
    for (final endpoint in _endpoints) {
      test(endpoint.id, () async {
        if (write == 'requests') return;
        final required = await _required(endpoint);
        if (required == null) {
          // No sample yet: recording is in its first phase, or the sample
          // folder is not where this checkout looks.
          if (write == null) fail('no sample for ${endpoint.id}');
          return;
        }
        final body = {
          'kind': endpoint.kind.name,
          'status': 200,
          'paths': required,
        };
        final file = File('${dir.path}/required/${endpoint.id}.json');
        if (write == 'required') {
          file.createSync(recursive: true);
          file.writeAsStringSync('${_json.convert(body)}\n');
          return;
        }
        expect(
          body,
          jsonDecode(file.readAsStringSync()),
          reason:
              'the fields the app needs from ${endpoint.id} changed. If that '
              'is meant, record again with app/tool/capture_compat.sh.',
        );
      });
    }
  });
}
