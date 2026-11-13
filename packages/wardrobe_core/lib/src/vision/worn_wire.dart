/// Decoding the worn-photo scan from the server's JSON.
///
/// The garment facts inside each detection are decoded by the caller, passed in
/// as [decodeScan], because the garment decoder lives with the app's other
/// scan decoders and one copy of it is the point. What is decoded here is what
/// is new: the box, the cutout and how it was made.
///
/// A cutout the server did not send stays null, and so does its kind. A kind
/// this build does not know is treated as `box`, the cautious reading: the
/// review screen then says the picture may include background, which is true
/// of a box and merely unnecessary of an outline.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'vision_port.dart';

/// Reads a `wornScanResult` (the `result` of a worn scan response).
WornScanResult wornScanResultFromJson(
  Map<String, Object?> result, {
  required GarmentScanResult Function(Map<String, Object?> scan) decodeScan,
}) {
  final raw = result['detections'];
  if (raw is! List<Object?>) {
    throw const FormatException('worn scan is missing "detections"');
  }
  return WornScanResult(
    detections: [
      for (final entry in raw)
        wornDetectionFromJson(
          entry! as Map<String, Object?>,
          decodeScan: decodeScan,
        ),
    ],
  );
}

/// Reads one `wornDetection`.
WornDetection wornDetectionFromJson(
  Map<String, Object?> json, {
  required GarmentScanResult Function(Map<String, Object?> scan) decodeScan,
}) {
  final cutout = json['cutout'];
  final kind = json['cutoutKind'];

  return WornDetection(
    scan: decodeScan(json['scan']! as Map<String, Object?>),
    boundingBox:
        BoundingBox.fromJson(json['boundingBox']! as Map<String, Object?>),
    detectionConfidence: (json['detectionConfidence']! as num).toDouble(),
    cutout: cutout is String ? Uint8List.fromList(base64Decode(cutout)) : null,
    cutoutKind: cutout is String
        ? CutoutKind.values.asNameMap()[kind] ?? CutoutKind.box
        : null,
  );
}
