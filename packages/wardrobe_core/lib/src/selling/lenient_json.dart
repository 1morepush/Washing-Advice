/// Reading JSON written by somebody else, or by an older version of this app.
///
/// Internal to `selling/`, and deliberately not exported. A listing is stored
/// on the phone and outlives the build that wrote it, and the price and
/// description responses are written by another language entirely. In both
/// cases a key being absent, or holding something unexpected, is a fact about
/// the writer and not a reason to lose the whole listing — so these readers
/// answer "nothing" where the wardrobe's strict parsers would throw.
///
/// What is *required* is decided by the callers. A listing with no id cannot
/// be saved or found, so reading one is an error; a listing with no
/// `condition` is a draft nobody has graded yet.
library;

import '../shared/confidence.dart';

String? readString(Object? value) => value is String ? value : null;

/// A string with the whitespace trimmed off, or null when nothing is left.
String? readTrimmed(Object? value) {
  final trimmed = readString(value)?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

int? readInt(Object? value) => value is num ? value.toInt() : null;

double? readDouble(Object? value) => value is num ? value.toDouble() : null;

bool? readBool(Object? value) => value is bool ? value : null;

DateTime? readDateTime(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

Map<String, Object?>? readObject(Object? value) =>
    value is Map<String, Object?> ? value : null;

/// The strings in a list, trimmed, with anything else or empty left out.
List<String> readStrings(Object? value) => [
      if (value is List<Object?>)
        for (final entry in value)
          if (readTrimmed(entry) case final String text) text,
    ];

/// The objects in a list; anything that is not one is left out.
List<Map<String, Object?>> readObjects(Object? value) => [
      if (value is List<Object?>)
        for (final entry in value)
          if (entry is Map<String, Object?>) entry,
    ];

/// The enum member called [name], or null for a name this build has never
/// heard of — a value added by a newer version, or a typo in a fixture.
T? readEnum<T extends Enum>(List<T> values, Object? name) =>
    name is String ? values.asNameMap()[name] : null;

/// A `{value, confidence, source}` object holding a string.
///
/// Null when there is no usable value. A missing confidence reads as none at
/// all rather than as certainty: a value nobody vouches for should look
/// unvouched-for, and the one place this is used — a brand or a size read off
/// a photograph — is exactly where over-trusting a reading does harm.
Confident<String>? readConfidentString(Object? value) {
  final json = readObject(value);
  if (json == null) return null;

  final text = readTrimmed(json['value']);
  if (text == null) return null;

  return Confident(
    text,
    confidence:
        (readDouble(json['confidence']) ?? 0.0).clamp(0.0, 1.0).toDouble(),
    source:
        readEnum(Provenance.values, json['source']) ?? Provenance.aiInference,
  );
}
