/// A named set of items worn together.
///
/// An outfit is deliberately a *reference* to items, never a copy of them. If
/// a jumper is edited or leaves the wardrobe, every outfit containing it must
/// reflect that immediately — a snapshot would let outfits quietly describe
/// clothes the user no longer owns.
library;

import '../../shared/ids.dart';
import '../../wardrobe/model/item_attributes.dart';
import '../../wardrobe/model/ownership.dart';
import 'occasion.dart';

/// The role an item plays in an outfit.
///
/// Coarser than [ItemCategory] because the question here is "what still needs
/// covering", and for that purpose leggings and jeans are the same answer.
enum OutfitSlot {
  top('Top'),
  bottom('Bottom'),
  fullBody('One-piece'),
  outerwear('Layer'),
  footwear('Shoes'),
  accessory('Accessory');

  const OutfitSlot(this.label);

  final String label;

  /// The slot an item of [category] fills, or null if it plays no part in an
  /// outfit — underwear and household linen are worn or used, not styled.
  static OutfitSlot? of(ItemCategory category) => switch (category) {
        ItemCategory.top => OutfitSlot.top,
        ItemCategory.bottom => OutfitSlot.bottom,
        ItemCategory.fullBody => OutfitSlot.fullBody,
        ItemCategory.outerwear => OutfitSlot.outerwear,
        ItemCategory.footwear => OutfitSlot.footwear,
        ItemCategory.accessory => OutfitSlot.accessory,
        // Activewear covers both halves of the body depending on the garment, so
        // it is resolved from the type rather than the category by [ofType].
        ItemCategory.activewear ||
        ItemCategory.legwear ||
        ItemCategory.sleepwear ||
        ItemCategory.swimwear ||
        ItemCategory.underwear ||
        ItemCategory.household =>
          null,
      };

  /// The slot an item of [type] fills, resolving the categories that span more
  /// than one slot.
  static OutfitSlot? ofType(ItemType type) => switch (type) {
        ItemType.activewearTop => OutfitSlot.top,
        ItemType.activewearBottom => OutfitSlot.bottom,
        ItemType.pajamas || ItemType.robe => OutfitSlot.fullBody,
        _ => OutfitSlot.of(type.category),
      };
}

/// A saved combination.
final class Outfit {
  Outfit({
    required this.id,
    required this.name,
    required Iterable<ItemId> itemIds,
    required this.createdAt,
    required this.updatedAt,
    this.occasion = Occasion.everyday,
    this.seasons = const {},
    this.usage = const UsageStats.none(),
    this.isFavorite = false,
    this.notes,
  }) : _itemIds = List.unmodifiable(itemIds);

  final OutfitId id;
  final String name;
  final List<ItemId> _itemIds;

  final Occasion occasion;

  /// When the outfit works. Empty means no season was stated, which is treated
  /// as "any" — the same absent-versus-declared distinction the care model
  /// uses, rather than pretending an unanswered question means "never".
  final Set<Season> seasons;

  final UsageStats usage;
  final bool isFavorite;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  List<ItemId> get itemIds => _itemIds;

  int get size => _itemIds.length;

  bool contains(ItemId id) => _itemIds.contains(id);

  bool suitsSeason(Season season) =>
      seasons.isEmpty ||
      seasons.contains(season) ||
      seasons.contains(Season.allSeason) ||
      season == Season.allSeason;

  Outfit copyWith({
    String? name,
    Iterable<ItemId>? itemIds,
    Occasion? occasion,
    Set<Season>? seasons,
    UsageStats? usage,
    bool? isFavorite,
    String? notes,
    DateTime? updatedAt,
  }) =>
      Outfit(
        id: id,
        name: name ?? this.name,
        itemIds: itemIds ?? _itemIds,
        occasion: occasion ?? this.occasion,
        seasons: seasons ?? this.seasons,
        usage: usage ?? this.usage,
        isFavorite: isFavorite ?? this.isFavorite,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// The outfit without [id], for when an item is deleted or swapped out.
  Outfit without(ItemId id) => copyWith(itemIds: [
        for (final i in _itemIds)
          if (i != id) i
      ]);

  Map<String, Object?> toJson() => {
        'id': id.value,
        'name': name,
        'itemIds': [for (final i in _itemIds) i.value],
        'occasion': occasion.name,
        // Sorted so two identical outfits encode identically — an unordered set
        // serialised in iteration order makes sync see phantom changes.
        'seasons': [for (final s in seasons) s.name]..sort(),
        'usage': usage.toJson(),
        'isFavorite': isFavorite,
        if (notes != null) 'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static Outfit fromJson(Map<String, Object?> json) => Outfit(
        id: OutfitId(json['id']! as String),
        name: json['name']! as String,
        itemIds: [
          for (final id in json['itemIds']! as List<Object?>)
            ItemId(id! as String),
        ],
        occasion: Occasion.values.byName(json['occasion']! as String),
        seasons: {
          for (final s in (json['seasons'] as List<Object?>?) ?? const [])
            Season.values.byName(s! as String),
        },
        usage: UsageStats.fromJson(json['usage']! as Map<String, Object?>),
        isFavorite: json['isFavorite'] as bool? ?? false,
        notes: json['notes'] as String?,
        createdAt: DateTime.parse(json['createdAt']! as String),
        updatedAt: DateTime.parse(json['updatedAt']! as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Outfit && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Outfit($name, ${_itemIds.length} items)';
}
