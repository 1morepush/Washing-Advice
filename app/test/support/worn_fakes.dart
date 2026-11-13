/// Stand-ins for the worn-photo scan, shared by its tests.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';

/// A 1×1 PNG, so crops and cutouts decode real bytes.
const wornPng = ScanImage(
  bytes: [
    137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, //
    0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222,
    0, 0, 0, 12, 73, 68, 65, 84, 120, 156, 99, 248, 207, 192, 0, 0,
    3, 1, 1, 0, 201, 254, 146, 239, 0, 0, 0, 0, 73, 69, 78, 68,
    174, 66, 96, 130,
  ],
);

/// A cutout whose bytes are recognisably not the photo's.
final wornCutoutBytes = Uint8List.fromList([...wornPng.bytes, 0, 0, 7]);

/// One garment found on a person.
WornDetection wornDetection({
  ItemType type = ItemType.sweater,
  String hex = '#1F2A44',
  String colour = 'Navy',
  String name = 'Navy jumper',
  CutoutKind? kind = CutoutKind.outline,
  List<int>? cutout,
  double left = 0.1,
}) => WornDetection(
  scan: GarmentScanResult(
    type: Confident(type, confidence: 0.9, source: Provenance.aiInference),
    colors: Confident(
      ColorPalette([ItemColor.fromHex(hex, name: colour)]),
      confidence: 0.88,
      source: Provenance.aiInference,
    ),
    composition: Confident(
      FabricComposition(const {Fiber.cotton: 100}),
      confidence: 0.4,
      source: Provenance.aiInference,
    ),
    suggestedName: name,
  ),
  boundingBox: BoundingBox(left: left, top: 0.1, width: 0.5, height: 0.5),
  detectionConfidence: 0.9,
  cutout: kind == null ? null : (cutout ?? wornCutoutBytes),
  cutoutKind: kind,
);

/// A server that answers the worn scan from a script.
///
/// Each call takes the next entry: a list of detections, or a [ScanFailure] to
/// throw. Past the end of the script the last entry repeats.
class WornGateway extends AiGateway {
  WornGateway([List<Object> script = const []])
    : script = script.isEmpty
          ? [
              <WornDetection>[wornDetection()],
            ]
          : script,
      super(baseUrl: Uri.parse('http://test.invalid/'));

  final List<Object> script;
  int calls = 0;

  /// When set, each call waits on this before answering.
  Completer<void>? hold;

  @override
  Future<WornScanResult> scanWorn(ScanImage image) async {
    final entry = script[calls < script.length ? calls : script.length - 1];
    calls++;
    if (hold case final Completer<void> gate) await gate.future;
    if (entry is ScanFailure) throw entry;
    return WornScanResult(detections: entry as List<WornDetection>);
  }

  @override
  Future<Uint8List?> cutout(ScanImage image) async => null;
}

/// An image store that remembers every name it was asked to write.
class CountingImageStore extends MemoryImageStore {
  final List<String> saved = [];

  /// Every URI asked to be deleted.
  final List<String> deleted = [];

  @override
  Future<String> save(Uint8List bytes, {required String name}) {
    saved.add(name);
    return super.save(bytes, name: name);
  }

  @override
  Future<void> delete(String uri) {
    deleted.add(uri);
    return super.delete(uri);
  }
}
