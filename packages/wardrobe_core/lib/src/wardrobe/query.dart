/// How the app asks for a subset of the wardrobe.
///
/// A value type rather than a string, so filtering is a domain concept the core
/// owns and a storage layer merely honours. Two consequences follow, and both
/// were the point:
///
/// * SQL stays out of the domain. `WardrobeRepository` speaks in queries; only
///   the Drift implementation knows what a `WHERE` clause is.
/// * "Show me all blue hoodies" becomes a *translation* problem. A natural
///   language parser produces one of these, and everything downstream is
///   already built and tested. Without it, natural-language search would have
///   to generate SQL, which is a far worse place to put a language model.
library;

import '../wardrobe/model/fabric.dart';
import '../wardrobe/model/item_attributes.dart';
import '../wardrobe/model/item_color.dart';
import '../wardrobe/model/lifecycle.dart';

/// How to order results.
enum WardrobeSort {
  /// Most recently added first. The default, because it is what a user expects
  /// after adding something.
  recentlyAdded('Recently added'),

  recentlyWorn('Recently worn'),

  /// Longest-unworn first — the "what am I not wearing?" view.
  leastRecentlyWorn('Least recently worn'),

  mostWorn('Most worn'),
  nameAscending('Name'),

  /// Grouped by where things were made, alphabetically. Items with no country
  /// recorded sort last, since an absence is not a place.
  countryOfOrigin('Where it was made'),

  /// Cheapest per wear first. Items with no price sort last, since a null is
  /// not a good score.
  costPerWear('Cost per wear');

  const WardrobeSort(this.label);

  final String label;
}

/// A request for part of the wardrobe.
///
/// Every field is optional and they combine with AND. An empty query means
/// "everything currently owned", which is the wardrobe screen's default.
final class WardrobeQuery {
  const WardrobeQuery({
    this.kinds = const {},
    this.categories = const {},
    this.types = const {},
    this.colorClasses = const {},
    this.brands = const {},
    this.countries = const {},
    this.seasons = const {},
    this.fibers = const {},
    this.lifecycleStates = const {},
    this.tags = const {},
    this.text,
    this.favoritesOnly = false,
    this.neverWorn = false,
    this.needsCareTagScan = false,
    this.wornSince,
    this.notWornSince,
    this.sort = WardrobeSort.recentlyAdded,
    this.limit,
    this.offset = 0,
  });

  /// Everything the user still owns. The wardrobe screen's default view.
  const WardrobeQuery.owned()
      : this(lifecycleStates: const {
          LifecycleState.active,
          LifecycleState.stored,
          LifecycleState.inLaundry,
          LifecycleState.beingWashed,
          LifecycleState.beingDried,
          LifecycleState.beingRepaired,
        });

  /// Items available to put in a laundry plan.
  const WardrobeQuery.launderable()
      : this(lifecycleStates: const {
          LifecycleState.active,
          LifecycleState.inLaundry,
        });

  final Set<ItemKind> kinds;
  final Set<ItemCategory> categories;
  final Set<ItemType> types;
  final Set<ColorClass> colorClasses;

  /// Matched case-insensitively; a storage layer is expected to normalise.
  final Set<String> brands;

  /// Where the garment was made, matched case-insensitively against the words
  /// printed on the label.
  final Set<String> countries;

  final Set<Season> seasons;

  /// Matches an item any of these fibres genuinely describes — see
  /// [FabricComposition.isDescribedBy], which is a lower bar than the care
  /// threshold on purpose.
  final Set<Fiber> fibers;

  final Set<LifecycleState> lifecycleStates;
  final Set<String> tags;

  /// Free text over name, brand and any text printed on the garment.
  final String? text;

  final bool favoritesOnly;

  /// Only items never worn — the "why do I own this?" view.
  final bool neverWorn;

  /// Only items whose care is too uncertain to act on. Drives the prompt to go
  /// and scan a label.
  final bool needsCareTagScan;

  /// Worn at or after this instant.
  final DateTime? wornSince;

  /// *Not* worn since this instant, including never worn at all.
  final DateTime? notWornSince;

  final WardrobeSort sort;
  final int? limit;
  final int offset;

  /// Whether this query constrains anything at all.
  bool get isUnfiltered =>
      kinds.isEmpty &&
      categories.isEmpty &&
      types.isEmpty &&
      colorClasses.isEmpty &&
      brands.isEmpty &&
      countries.isEmpty &&
      seasons.isEmpty &&
      fibers.isEmpty &&
      lifecycleStates.isEmpty &&
      tags.isEmpty &&
      (text == null || text!.trim().isEmpty) &&
      !favoritesOnly &&
      !neverWorn &&
      !needsCareTagScan &&
      wornSince == null &&
      notWornSince == null;

  /// How many filters are active, for a "3 filters" badge on the UI.
  int get activeFilterCount => [
        kinds.isNotEmpty,
        categories.isNotEmpty,
        types.isNotEmpty,
        colorClasses.isNotEmpty,
        brands.isNotEmpty,
        countries.isNotEmpty,
        seasons.isNotEmpty,
        fibers.isNotEmpty,
        tags.isNotEmpty,
        text != null && text!.trim().isNotEmpty,
        favoritesOnly,
        neverWorn,
        needsCareTagScan,
        wornSince != null,
        notWornSince != null,
      ].where((active) => active).length;

  WardrobeQuery copyWith({
    Set<ItemKind>? kinds,
    Set<ItemCategory>? categories,
    Set<ItemType>? types,
    Set<ColorClass>? colorClasses,
    Set<String>? brands,
    Set<String>? countries,
    Set<Season>? seasons,
    Set<Fiber>? fibers,
    Set<LifecycleState>? lifecycleStates,
    Set<String>? tags,
    String? text,
    bool? favoritesOnly,
    bool? neverWorn,
    bool? needsCareTagScan,
    DateTime? wornSince,
    DateTime? notWornSince,
    WardrobeSort? sort,
    int? limit,
    int? offset,
  }) =>
      WardrobeQuery(
        kinds: kinds ?? this.kinds,
        categories: categories ?? this.categories,
        types: types ?? this.types,
        colorClasses: colorClasses ?? this.colorClasses,
        brands: brands ?? this.brands,
        countries: countries ?? this.countries,
        seasons: seasons ?? this.seasons,
        fibers: fibers ?? this.fibers,
        lifecycleStates: lifecycleStates ?? this.lifecycleStates,
        tags: tags ?? this.tags,
        text: text ?? this.text,
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
        neverWorn: neverWorn ?? this.neverWorn,
        needsCareTagScan: needsCareTagScan ?? this.needsCareTagScan,
        wornSince: wornSince ?? this.wornSince,
        notWornSince: notWornSince ?? this.notWornSince,
        sort: sort ?? this.sort,
        limit: limit ?? this.limit,
        offset: offset ?? this.offset,
      );

  /// Clears every filter, keeping sort and paging.
  WardrobeQuery cleared() => WardrobeQuery(
        sort: sort,
        limit: limit,
        offset: offset,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WardrobeQuery &&
          _setEquals(other.kinds, kinds) &&
          _setEquals(other.categories, categories) &&
          _setEquals(other.types, types) &&
          _setEquals(other.colorClasses, colorClasses) &&
          _setEquals(other.brands, brands) &&
          _setEquals(other.seasons, seasons) &&
          _setEquals(other.fibers, fibers) &&
          _setEquals(other.lifecycleStates, lifecycleStates) &&
          _setEquals(other.tags, tags) &&
          other.text == text &&
          other.favoritesOnly == favoritesOnly &&
          other.neverWorn == neverWorn &&
          other.needsCareTagScan == needsCareTagScan &&
          other.wornSince == wornSince &&
          other.notWornSince == notWornSince &&
          other.sort == sort &&
          other.limit == limit &&
          other.offset == offset;

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(kinds),
        Object.hashAllUnordered(categories),
        Object.hashAllUnordered(types),
        Object.hashAllUnordered(colorClasses),
        Object.hashAllUnordered(brands),
        Object.hashAllUnordered(seasons),
        Object.hashAllUnordered(fibers),
        Object.hashAllUnordered(lifecycleStates),
        Object.hashAllUnordered(tags),
        text,
        favoritesOnly,
        neverWorn,
        needsCareTagScan,
        wornSince,
        notWornSince,
        sort,
        limit,
        offset,
      );

  @override
  String toString() =>
      'WardrobeQuery($activeFilterCount filters, sort=${sort.name})';
}

bool _setEquals<T>(Set<T> a, Set<T> b) =>
    a.length == b.length && a.containsAll(b);
