/// Links between items.
///
/// A wardrobe is a graph, not a list. Recording that a jacket and trousers form
/// a suit, or that two shirts are worn together often, is what later makes
/// outfit generation and packing tractable: those features become traversals
/// over recorded edges instead of fresh inference every time.
library;

import '../../shared/ids.dart';

/// The nature of a link between two items.
enum RelationKind {
  /// The two are parts of one garment sold together, like a suit. Should be
  /// washed and stored together so they age at the same rate.
  suitSet('Part of a set', symmetric: true, implies: true),

  /// They look good together. Recorded by the user or inferred from outfits.
  pairsWith('Pairs with', symmetric: true),

  /// Observed being worn together.
  wornWith('Worn with', symmetric: true),

  /// One replaced the other — the new white tee after the old one greyed.
  /// Directional: from the replacement to what it replaced.
  replaces('Replaces'),

  /// Near-identical duplicates, like a three-pack of the same socks. Lets the
  /// matcher stop agonising over which one it is looking at.
  duplicateOf('Duplicate of', symmetric: true),

  /// Belongs to a named outfit.
  partOfOutfit('Part of outfit', symmetric: true),

  /// Must be washed with the other, such as a removable liner.
  washTogetherWith('Wash together with', symmetric: true, implies: true);

  const RelationKind(this.label,
      {this.symmetric = false, this.implies = false});

  final String label;

  /// Whether the link reads the same in both directions.
  final bool symmetric;

  /// Whether this link constrains laundry — items so linked belong in one load.
  final bool implies;
}

/// A directed edge between two items.
///
/// Symmetric kinds are still stored as one edge; [involves] and [otherEnd]
/// handle traversal in either direction so the graph does not have to store
/// each link twice and risk the halves drifting apart.
final class ItemRelationship {
  const ItemRelationship({
    required this.from,
    required this.to,
    required this.kind,
    this.strength = 1.0,
    this.note,
  });

  final ItemId from;
  final ItemId to;
  final RelationKind kind;

  /// How strong the link is, `0..1`. Used for inferred edges such as
  /// [RelationKind.wornWith], where frequency matters.
  final double strength;

  final String? note;

  bool involves(ItemId id) => from == id || to == id;

  /// The item at the far end of this edge from [id], or null if [id] is not on
  /// this edge at all.
  ItemId? otherEnd(ItemId id) {
    if (from == id) return to;
    if (to == id && kind.symmetric) return from;
    return null;
  }

  ItemRelationship withStrength(double value) => ItemRelationship(
        from: from,
        to: to,
        kind: kind,
        strength: value.clamp(0.0, 1.0),
        note: note,
      );

  Map<String, Object?> toJson() => {
        'from': from.value,
        'to': to.value,
        'kind': kind.name,
        'strength': strength,
        if (note != null) 'note': note,
      };

  static ItemRelationship fromJson(Map<String, Object?> json) =>
      ItemRelationship(
        from: ItemId(json['from']! as String),
        to: ItemId(json['to']! as String),
        kind: RelationKind.values.byName(json['kind']! as String),
        strength: (json['strength'] as num?)?.toDouble() ?? 1.0,
        note: json['note'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ItemRelationship &&
          other.from == from &&
          other.to == to &&
          other.kind == kind &&
          other.strength == strength &&
          other.note == note;

  @override
  int get hashCode => Object.hash(from, to, kind, strength, note);

  @override
  String toString() => 'ItemRelationship(${from.value} -${kind.name}-> '
      '${to.value})';
}

/// The relationship graph for a wardrobe.
///
/// Deliberately a simple adjacency scan: a personal wardrobe is hundreds of
/// items, not millions, so clarity beats indexing here. If that assumption ever
/// breaks, this class is the only thing that needs to change.
final class RelationshipGraph {
  RelationshipGraph(List<ItemRelationship> edges)
      : _edges = List.unmodifiable(edges);

  RelationshipGraph.empty() : this(const []);

  final List<ItemRelationship> _edges;

  List<ItemRelationship> get edges => _edges;

  bool get isEmpty => _edges.isEmpty;

  Iterable<ItemRelationship> edgesFor(ItemId id) =>
      _edges.where((e) => e.involves(id));

  /// Items linked to [id], optionally filtered to one kind of link.
  Set<ItemId> neighbours(ItemId id, {RelationKind? kind}) => {
        for (final edge in edgesFor(id))
          if (kind == null || edge.kind == kind)
            if (edge.otherEnd(id) case final ItemId other) other,
      };

  /// Items that must share a wash load with [id], transitively.
  ///
  /// Follows only edges whose kind sets [RelationKind.implies] — a suit or a
  /// jacket with a zip-out liner. Traversal is transitive so a chain of such
  /// links resolves to one group, and the result excludes [id] itself.
  Set<ItemId> mustWashWith(ItemId id) {
    final found = <ItemId>{};
    final queue = <ItemId>[id];
    final seen = <ItemId>{id};

    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (final edge in edgesFor(current)) {
        if (!edge.kind.implies) continue;
        final other = edge.otherEnd(current);
        if (other == null || !seen.add(other)) continue;
        found.add(other);
        queue.add(other);
      }
    }
    return found;
  }

  RelationshipGraph add(ItemRelationship edge) =>
      RelationshipGraph([..._edges, edge]);

  /// Drops every edge touching [id], for when an item leaves the wardrobe.
  RelationshipGraph removeItem(ItemId id) => RelationshipGraph([
        for (final e in _edges)
          if (!e.involves(id)) e
      ]);

  List<Object?> toJson() => _edges.map((e) => e.toJson()).toList();

  static RelationshipGraph fromJson(List<Object?> json) => RelationshipGraph([
        for (final entry in json)
          ItemRelationship.fromJson(entry! as Map<String, Object?>),
      ]);

  @override
  String toString() => 'RelationshipGraph(${_edges.length} edges)';
}
