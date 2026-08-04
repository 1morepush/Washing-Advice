/// Typed identifiers.
///
/// Every entity gets its own id type rather than passing bare [String]s around.
/// Swapping an item id for an event id then fails to compile instead of
/// silently returning nothing at runtime.
library;

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
