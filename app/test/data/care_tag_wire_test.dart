/// The care-tag reply, as the real server actually sends it.
///
/// Captured from a run of the server (fake provider), not hand-written. The
/// unit tests either side of this boundary each use their own idea of the
/// shape, so a field the server renames and the client still looks for would
/// pass both and fail only on a phone.
///
/// Worth having for the two fields added most recently — the fibre content and
/// where the garment was made — since both are optional, and an optional field
/// that silently never arrives looks exactly like a label that did not state
/// it.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/api/scan_dto.dart';

const _captured = r'''
{
  "instructions": {
    "method": "machine",
    "maxTempC": 30,
    "washTemperature": "cold",
    "agitation": "normal",
    "bleach": "none",
    "tumbleDryAllowed": true,
    "tumbleDryHeat": "low",
    "ironTemperature": "low",
    "doNotDryClean": true,
    "warnings": [
      "washInsideOut",
      "doNotIronDecoration"
    ]
  },
  "confidence": 0.92,
  "composition": {
    "value": {
      "cotton": 95,
      "elastane": 5
    },
    "confidence": 0.96,
    "source": "tagScan"
  },
  "countryOfOrigin": {
    "value": "Portugal",
    "confidence": 0.94,
    "source": "tagScan"
  },
  "symbolsFound": [
    "wash.30",
    "bleach.none",
    "iron.low"
  ],
  "unreadableSymbolCount": 0,
  "rawText": "95% COTTON 5% ELASTANE / MACHINE WASH COLD",
  "language": "en"
}
''';

void main() {
  late CareTagScanResult result;

  setUp(() {
    result = careTagResultFromJson(
      jsonDecode(_captured) as Map<String, Object?>,
    );
  });

  test('the fibre content survives the wire', () {
    expect(result.composition, isNotNull);
    expect(result.composition!.value.percentOf(Fiber.cotton), 95);
    // The wire key is the enum name, which the display rename did not touch.
    // If it had, this would decode as an unknown fibre or throw.
    expect(result.composition!.value.percentOf(Fiber.elastane), 5);
    expect(result.composition!.source, Provenance.tagScan);
  });

  test('and reads back in the words the app shows', () {
    expect(result.composition!.value.label, contains('Spandex'));
  });

  test('where it was made survives the wire', () {
    expect(result.countryOfOrigin?.value, 'Portugal');
    expect(result.countryOfOrigin?.source, Provenance.tagScan);
  });

  test('the instructions still decode as they always did', () {
    // The rest of the payload, so a change that broke the old fields while
    // adding the new ones would not slip through.
    expect(result.instructions.maxTempC, 30);
    expect(result.instructions.doNotDryClean, isTrue);
    expect(result.instructions.warnings, contains(CareWarning.washInsideOut));
  });
}
