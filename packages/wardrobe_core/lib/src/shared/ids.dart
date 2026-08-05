/// Typed identifiers.
///
/// Every entity gets its own id type rather than passing bare [String]s around.
/// Swapping an item id for an event id then fails to compile instead of
/// silently returning nothing at runtime.
library;

import 'dart:math' as math;

/// Source of new identifiers.
///
/// An interface rather than a bare function so tests can hand out predictable
/// ids — a scan test asserting on a random UUID would be untestable, and one
/// that reached for `DateTime.now().toString()` would collide the moment two
/// items were added in the same millisecond.
abstract interface class IdGenerator {
  String next();
}

/// Random ids, suitable for a local database that will later sync.
///
/// Deliberately not a sequence: two devices offline at the same time must not
/// mint the same id, and a counter guarantees they eventually will. This is a
/// UUID v4 in shape and entropy, generated from [math.Random.secure] where the
/// platform offers it.
final class RandomIdGenerator implements IdGenerator {
  RandomIdGenerator([math.Random? random])
      : _random = random ?? _secureOrFallback();

  final math.Random _random;

  static math.Random _secureOrFallback() {
    try {
      return math.Random.secure();
    } on UnsupportedError {
      // No secure source on this platform. Ids are not secrets — they only
      // need to not collide — so a seeded generator is an acceptable fallback,
      // and failing to create an item would not be.
      return math.Random(DateTime.now().microsecondsSinceEpoch);
    }
  }

  @override
  String next() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    // Version 4, variant 1, so the result is a well-formed UUID rather than
    // merely 32 random hex characters.
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    final hex = [
      for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
    ].join();

    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

/// Hands out `prefix-1`, `prefix-2`, … for tests.
final class SequentialIdGenerator implements IdGenerator {
  SequentialIdGenerator({this.prefix = 'id'});

  final String prefix;
  int _next = 0;

  @override
  String next() => '$prefix-${++_next}';
}

/// Base for all identifiers. Value semantics; the wrapped string is opaque.
abstract base class EntityId {
  const EntityId(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is EntityId &&
          other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => '$runtimeType($value)';
}

/// Identifies a single physical thing the user owns.
final class ItemId extends EntityId {
  const ItemId(super.value);
}

/// Identifies one entry in the append-only event log.
final class EventId extends EntityId {
  const EventId(super.value);
}

/// Identifies a configured washing machine.
final class WasherId extends EntityId {
  const WasherId(super.value);
}

/// Identifies a configured dryer.
final class DryerId extends EntityId {
  const DryerId(super.value);
}

/// Identifies one generated or recorded wash load.
final class LoadId extends EntityId {
  const LoadId(super.value);
}

/// Identifies a saved outfit.
final class OutfitId extends EntityId {
  const OutfitId(super.value);
}
