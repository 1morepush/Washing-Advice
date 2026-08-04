/// The append-only history of everything that happens to a wardrobe.
///
/// The event log is the source of truth. `WardrobeItem.usage` holds counters,
/// but they are a *cache* — a projection of these events, rebuildable at any
/// time. That distinction is what makes the history trustworthy: an incorrectly
/// incremented counter can be repaired by replaying, and questions nobody
/// anticipated ("how many times did I wear this before it started fading?")
/// remain answerable because the raw facts were never thrown away.
///
/// Events are sealed, so adding a new kind forces every projection to handle it
/// rather than silently ignoring it.
library;

import '../laundry/model/laundry_record.dart';
import '../shared/ids.dart';
import '../wardrobe/model/condition.dart';
import '../wardrobe/model/lifecycle.dart';
import '../wardrobe/model/ownership.dart';

/// Something that happened to one item.
sealed class WardrobeEvent {
  const WardrobeEvent({
    required this.id,
    required this.itemId,
    required this.occurredAt,
  });

  final EventId id;
  final ItemId itemId;

  /// When the event actually happened, which may be earlier than when it was
  /// recorded — people log yesterday's wash this morning.
  final DateTime occurredAt;

  /// Short machine-readable type name, used in storage and JSON.
  String get typeName;

  Map<String, Object?> toJson() => {
        'type': typeName,
        'id': id.value,
        'itemId': itemId.value,
        'occurredAt': occurredAt.toIso8601String(),
        ...payload,
      };

  /// Fields specific to this event type.
  Map<String, Object?> get payload => const {};

  /// Rebuilds an event from storage.
  static WardrobeEvent fromJson(Map<String, Object?> json) {
    final id = EventId(json['id']! as String);
    final itemId = ItemId(json['itemId']! as String);
    final occurredAt = DateTime.parse(json['occurredAt']! as String);

    return switch (json['type']! as String) {
      'purchased' => ItemPurchased(
          id: id,
          itemId: itemId,
          occurredAt: occurredAt,
          purchase: PurchaseInfo.fromJson(
            json['purchase']! as Map<String, Object?>,
          ),
        ),
      'added' => ItemAdded(id: id, itemId: itemId, occurredAt: occurredAt),
      'worn' => ItemWorn(
          id: id,
          itemId: itemId,
          occurredAt: occurredAt,
          occasion: json['occasion'] as String?,
        ),
      'washed' => ItemWashed(
          id: id,
          itemId: itemId,
          occurredAt: occurredAt,
          record: LaundryRecord.fromJson(
            json['record']! as Map<String, Object?>,
          ),
        ),
      'repaired' => ItemRepaired(
          id: id,
          itemId: itemId,
          occurredAt: occurredAt,
          description: json['description'] as String?,
        ),
      'conditionObserved' => ConditionObserved(
          id: id,
          itemId: itemId,
          occurredAt: occurredAt,
          observation: WearObservation.fromJson(
            json['observation']! as Map<String, Object?>,
          ),
        ),
      'lifecycleChanged' => LifecycleChanged(
          id: id,
          itemId: itemId,
          occurredAt: occurredAt,
          to: LifecycleState.values.byName(json['to']! as String),
          note: json['note'] as String?,
        ),
      final unknown => throw FormatException('Unknown event type "$unknown"'),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WardrobeEvent &&
          other.runtimeType == runtimeType &&
          other.id == id;

  @override
  int get hashCode => Object.hash(runtimeType, id);

  @override
  String toString() => '$typeName(${itemId.value} @ $occurredAt)';
}

/// The item was bought.
final class ItemPurchased extends WardrobeEvent {
  const ItemPurchased({
    required super.id,
    required super.itemId,
    required super.occurredAt,
    required this.purchase,
  });

  final PurchaseInfo purchase;

  @override
  String get typeName => 'purchased';

  @override
  Map<String, Object?> get payload => {'purchase': purchase.toJson()};
}

/// The item entered the wardrobe.
final class ItemAdded extends WardrobeEvent {
  const ItemAdded({
    required super.id,
    required super.itemId,
    required super.occurredAt,
  });

  @override
  String get typeName => 'added';
}

/// The item was worn.
final class ItemWorn extends WardrobeEvent {
  const ItemWorn({
    required super.id,
    required super.itemId,
    required super.occurredAt,
    this.occasion,
  });

  /// What it was worn for, when known — feeds outfit suggestions later.
  final String? occasion;

  @override
  String get typeName => 'worn';

  @override
  Map<String, Object?> get payload => {
        if (occasion != null) 'occasion': occasion,
      };
}

/// The item was washed, with the settings used.
final class ItemWashed extends WardrobeEvent {
  const ItemWashed({
    required super.id,
    required super.itemId,
    required super.occurredAt,
    required this.record,
  });

  final LaundryRecord record;

  @override
  String get typeName => 'washed';

  @override
  Map<String, Object?> get payload => {'record': record.toJson()};
}

/// The item was mended or altered.
final class ItemRepaired extends WardrobeEvent {
  const ItemRepaired({
    required super.id,
    required super.itemId,
    required super.occurredAt,
    this.description,
  });

  final String? description;

  @override
  String get typeName => 'repaired';

  @override
  Map<String, Object?> get payload => {
        if (description != null) 'description': description,
      };
}

/// Wear or damage was noticed.
final class ConditionObserved extends WardrobeEvent {
  const ConditionObserved({
    required super.id,
    required super.itemId,
    required super.occurredAt,
    required this.observation,
  });

  final WearObservation observation;

  @override
  String get typeName => 'conditionObserved';

  @override
  Map<String, Object?> get payload => {'observation': observation.toJson()};
}

/// The item moved to a new lifecycle state — stored, donated, discarded.
final class LifecycleChanged extends WardrobeEvent {
  const LifecycleChanged({
    required super.id,
    required super.itemId,
    required super.occurredAt,
    required this.to,
    this.note,
  });

  final LifecycleState to;
  final String? note;

  @override
  String get typeName => 'lifecycleChanged';

  @override
  Map<String, Object?> get payload => {
        'to': to.name,
        if (note != null) 'note': note,
      };
}
