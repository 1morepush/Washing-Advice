/// A garment being sold on Depop, from first draft to sold.
///
/// Depop has no API, so the app cannot post a listing. What it can do is fill
/// everything in and keep track: a [Listing] is the person's working copy of a
/// Depop listing — the description's ingredients, the photographs, a price they
/// chose and the evidence behind it — plus where it has got to ([ListingStatus]).
///
/// A listing is stored on the phone beside the wardrobe and is not synced, and
/// it is deliberately a copy rather than a view of the garment it came from. A
/// listing is a statement made to a buyer on a particular day; editing the
/// garment afterwards must not quietly rewrite what was promised, and a listing
/// for something that was never in the wardrobe is just as valid.
///
/// Everything here is a plain immutable value. The decisions somebody acts on —
/// the price, the description, the condition — are made by the functions that
/// take a listing, not by the listing itself.
library;

import '../shared/confidence.dart';
import '../shared/ids.dart';
import '../wardrobe/model/item_attributes.dart';
import '../wardrobe/model/photo.dart';
import '../wardrobe/model/wardrobe_item.dart';
import 'condition_suggestion.dart';
import 'depop.dart';
import 'garment_facts.dart';
import 'lenient_json.dart';

/// How long a listing can sit before it is worth refreshing.
///
/// Depop shows recently listed things first, so a listing that has sat for a
/// fortnight has sunk below everything posted since. Refreshing or relisting it
/// is the standard advice, and this is when to say so.
const Duration listingRefreshAfter = Duration(days: 14);

bool _sameList<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// How alike a comparable is to the thing being sold.
///
/// Judged by the server from a description of the photographs, never from the
/// pictures themselves — there is no free visual search to ask — so it is a
/// claim to check, and the link beside every comparable is how.
enum ComparableMatch {
  /// The same product: the same brand and model.
  same,

  /// The same kind of thing from a comparable brand.
  similar,
}

/// A listing on Depop for the same or a similar item.
///
/// Every one came back from a web search made for this request, and its price
/// was found in the text of that page. A comparable the server cannot point to
/// is dropped before it gets here.
final class SaleComparable {
  const SaleComparable({
    required this.title,
    required this.url,
    required this.priceCents,
    required this.match,
    this.sold,
    this.condition,
    this.why,
  });

  final String title;
  final Uri url;

  /// In US cents. Only US dollars are carried.
  final int priceCents;

  /// True when the page says it has sold, false when it is still for sale,
  /// null when the page does not say.
  ///
  /// Three states because a sold price is what somebody paid and an asking
  /// price is what somebody hopes for, and the price suggestion weighs them
  /// differently. "Does not say" is treated as asking: nothing is called sold
  /// without the page saying so.
  final bool? sold;

  /// The condition as that listing states it, verbatim.
  final String? condition;

  final ComparableMatch match;

  /// One line on why it counts, in the server's words.
  final String? why;

  Map<String, Object?> toJson() => {
        'title': title,
        'url': url.toString(),
        'priceCents': priceCents,
        if (sold != null) 'sold': sold,
        if (condition != null) 'condition': condition,
        'match': match.name,
        if (why != null) 'why': why,
      };

  /// Reads one stored comparable, or null when it is not readable.
  ///
  /// Null rather than an error because comparables are read as a list, and one
  /// damaged entry is not a reason to lose the rest.
  static SaleComparable? tryFromJson(Map<String, Object?> json) {
    final title = readTrimmed(json['title']);
    final url = Uri.tryParse(readString(json['url']) ?? '');
    final price = readInt(json['priceCents']);
    if (title == null || url == null || !url.hasScheme || price == null) {
      return null;
    }

    return SaleComparable(
      title: title,
      url: url,
      priceCents: price,
      sold: readBool(json['sold']),
      condition: readTrimmed(json['condition']),
      match: readEnum(ComparableMatch.values, json['match']) ??
          ComparableMatch.similar,
      why: readTrimmed(json['why']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaleComparable &&
          other.title == title &&
          other.url == url &&
          other.priceCents == priceCents &&
          other.sold == sold &&
          other.condition == condition &&
          other.match == match &&
          other.why == why;

  @override
  int get hashCode =>
      Object.hash(title, url, priceCents, sold, condition, match, why);

  @override
  String toString() => 'SaleComparable($title, ${priceCents}c)';
}

/// What the same or a similar item costs new, from a shop.
///
/// Never from a resale site: this is the ceiling a used price is held under.
final class RetailReference {
  const RetailReference({
    required this.title,
    required this.url,
    required this.priceCents,
    required this.match,
    this.seller,
  });

  final String title;
  final Uri url;

  /// In US cents.
  final int priceCents;

  /// The shop, as its domain: `nike.com`.
  final String? seller;

  final ComparableMatch match;

  Map<String, Object?> toJson() => {
        'title': title,
        'url': url.toString(),
        'priceCents': priceCents,
        if (seller != null) 'seller': seller,
        'match': match.name,
      };

  /// Reads one stored reference, or null when it is not readable.
  static RetailReference? tryFromJson(Map<String, Object?> json) {
    final title = readTrimmed(json['title']);
    final url = Uri.tryParse(readString(json['url']) ?? '');
    final price = readInt(json['priceCents']);
    if (title == null || url == null || !url.hasScheme || price == null) {
      return null;
    }

    return RetailReference(
      title: title,
      url: url,
      priceCents: price,
      seller: readTrimmed(json['seller']),
      match: readEnum(ComparableMatch.values, json['match']) ??
          ComparableMatch.similar,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetailReference &&
          other.title == title &&
          other.url == url &&
          other.priceCents == priceCents &&
          other.seller == seller &&
          other.match == match;

  @override
  int get hashCode => Object.hash(title, url, priceCents, seller, match);

  @override
  String toString() => 'RetailReference($title, ${priceCents}c)';
}

/// How a price search went.
///
/// None of these is an error. Every status but [ok] comes with no results, and
/// a listing can be written and priced by hand without any of them.
enum PriceSearchStatus {
  /// Searched.
  ok,

  /// This server has no search key. The app falls back to links and to prices
  /// the person types in.
  notConfigured,

  /// The search service's free allowance is used up for now.
  quotaExceeded,

  /// The search service failed or timed out.
  unavailable,
}

/// The two phrases a price search runs: one for Depop, one for the price new.
///
/// Written from the photographs and editable before prices are looked up, so a
/// wrong guess about the brand is a typo to fix rather than a wasted search.
final class SearchQueries {
  const SearchQueries({required this.depop, required this.retail});

  /// The shortest phrase the server accepts.
  static const int minLength = 3;

  /// The longest phrase the server accepts.
  static const int maxLength = 120;

  /// For Depop's listings: how a seller would title this.
  final String depop;

  /// For shops selling it new: brand, model and colour.
  final String retail;

  /// Whether both phrases are long enough to search with.
  bool get isSearchable =>
      depop.trim().length >= minLength && retail.trim().length >= minLength;

  SearchQueries copyWith({String? depop, String? retail}) => SearchQueries(
        depop: depop ?? this.depop,
        retail: retail ?? this.retail,
      );

  Map<String, Object?> toJson() => {'depop': depop, 'retail': retail};

  factory SearchQueries.fromJson(Map<String, Object?> json) => SearchQueries(
        depop: readTrimmed(json['depop']) ?? '',
        retail: readTrimmed(json['retail']) ?? '',
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchQueries && other.depop == depop && other.retail == retail;

  @override
  int get hashCode => Object.hash(depop, retail);

  @override
  String toString() => 'SearchQueries($depop | $retail)';
}

/// What a search found and would not show, by reason.
///
/// Shown to the person so that an empty list reads as "nothing usable" and not
/// as "nothing looked".
final class ExcludedCounts {
  const ExcludedCounts({
    this.notUsd = 0,
    this.unverifiedPrice = 0,
    this.notComparable = 0,
  });

  static const ExcludedCounts none = ExcludedCounts();

  /// Priced in another currency. Excluded rather than converted: a comparable
  /// built on an invented exchange rate looks like evidence and is not.
  final int notUsd;

  /// A price the server could not find in the text of the page.
  final int unverifiedPrice;

  /// Not alike enough to count.
  final int notComparable;

  int get total => notUsd + unverifiedPrice + notComparable;

  Map<String, Object?> toJson() => {
        'notUsd': notUsd,
        'unverifiedPrice': unverifiedPrice,
        'notComparable': notComparable,
      };

  factory ExcludedCounts.fromJson(Map<String, Object?> json) => ExcludedCounts(
        notUsd: readInt(json['notUsd']) ?? 0,
        unverifiedPrice: readInt(json['unverifiedPrice']) ?? 0,
        notComparable: readInt(json['notComparable']) ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExcludedCounts &&
          other.notUsd == notUsd &&
          other.unverifiedPrice == unverifiedPrice &&
          other.notComparable == notComparable;

  @override
  int get hashCode => Object.hash(notUsd, unverifiedPrice, notComparable);

  @override
  String toString() => 'ExcludedCounts($total)';
}

/// The result of one price search, kept with the listing it was made for.
///
/// Kept rather than thrown away so that reopening a listing shows the evidence
/// its price was built on, and when it was gathered — a price checked three
/// weeks ago should say so.
///
/// This is the *stored* form, in cents. The server's own form, in dollars and
/// vetted on the way in, is read by `priceSearchFromJson`.
final class PriceSearch {
  PriceSearch({
    required this.status,
    required this.queries,
    this.searchedAt,
    this.provider,
    List<SaleComparable> comparables = const [],
    List<RetailReference> retail = const [],
    this.excluded = ExcludedCounts.none,
  })  : comparables = List<SaleComparable>.unmodifiable(comparables),
        retail = List<RetailReference>.unmodifiable(retail);

  final PriceSearchStatus status;

  /// When the search ran. Present when [status] is [PriceSearchStatus.ok].
  final DateTime? searchedAt;

  /// Which search service answered, e.g. `tavily`.
  final String? provider;

  final SearchQueries queries;
  final List<SaleComparable> comparables;
  final List<RetailReference> retail;
  final ExcludedCounts excluded;

  Map<String, Object?> toJson() => {
        'status': status.name,
        if (searchedAt != null) 'searchedAt': searchedAt!.toIso8601String(),
        if (provider != null) 'provider': provider,
        'queries': queries.toJson(),
        'comparables': [for (final c in comparables) c.toJson()],
        'retail': [for (final r in retail) r.toJson()],
        'excluded': excluded.toJson(),
      };

  factory PriceSearch.fromJson(Map<String, Object?> json) => PriceSearch(
        status: readEnum(PriceSearchStatus.values, json['status']) ??
            PriceSearchStatus.unavailable,
        searchedAt: readDateTime(json['searchedAt']),
        provider: readTrimmed(json['provider']),
        queries:
            SearchQueries.fromJson(readObject(json['queries']) ?? const {}),
        comparables: readObjects(json['comparables'])
            .map(SaleComparable.tryFromJson)
            .whereType<SaleComparable>()
            .toList(),
        retail: readObjects(json['retail'])
            .map(RetailReference.tryFromJson)
            .whereType<RetailReference>()
            .toList(),
        excluded:
            ExcludedCounts.fromJson(readObject(json['excluded']) ?? const {}),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PriceSearch &&
          other.status == status &&
          other.searchedAt == searchedAt &&
          other.provider == provider &&
          other.queries == queries &&
          _sameList(other.comparables, comparables) &&
          _sameList(other.retail, retail) &&
          other.excluded == excluded;

  @override
  int get hashCode => Object.hash(
        status,
        searchedAt,
        provider,
        queries,
        Object.hashAll(comparables),
        Object.hashAll(retail),
        excluded,
      );

  @override
  String toString() => 'PriceSearch(${status.name}, '
      '${comparables.length} comparables, ${retail.length} retail)';
}

/// What the photographs showed, as a draft of what a buyer needs to know.
///
/// A proposal and nothing more. Every optional field follows the scan
/// contract's rule: absent means the photographs did not show it, never a guess
/// presented as a reading. A brand and a size are wrapped in [Confident]
/// because a brand guessed from a swoosh-shaped print and one read off the neck
/// label are different claims to put in front of a buyer.
///
/// Its JSON is the contract's own, so the same shape is stored and received.
final class ListingFacts {
  ListingFacts({
    required this.title,
    required this.itemType,
    required this.searchQueries,
    this.brand,
    List<String> colors = const [],
    this.material,
    this.sizeOnTag,
    List<String> styleWords = const [],
    this.era,
    List<String> visibleFlaws = const [],
  })  : colors = List<String>.unmodifiable(colors),
        styleWords = List<String>.unmodifiable(styleWords),
        visibleFlaws = List<String>.unmodifiable(visibleFlaws);

  /// Brand, item and the words a buyer searches for, most important first:
  /// `Nike vintage crewneck sweatshirt grey`. Becomes the first line of the
  /// description.
  final String title;

  final ItemType itemType;

  /// Read from a logo or a brand label.
  final Confident<String>? brand;

  /// Plain colour names, dominant first.
  final List<String> colors;

  /// As a composition label states it. Absent unless a label was photographed.
  final String? material;

  /// The size printed on the size label, exactly as printed. Absent unless a
  /// size label was photographed.
  final Confident<String>? sizeOnTag;

  /// Search words a buyer would use: cut, style, print. No brand.
  final List<String> styleWords;

  /// Only when the photographs show it: `90s`, `Y2K`.
  final String? era;

  /// What a buyer would complain about, said plainly. Empty when none is
  /// visible, which is not a promise that none exists.
  final List<String> visibleFlaws;

  final SearchQueries searchQueries;

  Map<String, Object?> toJson() => {
        'title': title,
        'itemType': itemType.name,
        if (brand != null) 'brand': brand!.toJson((b) => b),
        'colors': colors,
        if (material != null) 'material': material,
        if (sizeOnTag != null) 'sizeOnTag': sizeOnTag!.toJson((s) => s),
        'styleWords': styleWords,
        if (era != null) 'era': era,
        'visibleFlaws': visibleFlaws,
        'searchQueries': searchQueries.toJson(),
      };

  /// Reads the contract's shape, tolerating what a writer might leave out.
  ///
  /// Without search phrases the title stands in for both: it is already what a
  /// buyer would type.
  factory ListingFacts.fromJson(Map<String, Object?> json) {
    final title = readTrimmed(json['title']) ?? '';
    final queries = readObject(json['searchQueries']);

    return ListingFacts(
      title: title,
      itemType: readEnum(ItemType.values, json['itemType']) ?? ItemType.other,
      brand: readConfidentString(json['brand']),
      colors: readStrings(json['colors']),
      material: readTrimmed(json['material']),
      sizeOnTag: readConfidentString(json['sizeOnTag']),
      styleWords: readStrings(json['styleWords']),
      era: readTrimmed(json['era']),
      visibleFlaws: readStrings(json['visibleFlaws']),
      searchQueries: queries == null
          ? SearchQueries(depop: title, retail: title)
          : SearchQueries.fromJson(queries),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListingFacts &&
          other.title == title &&
          other.itemType == itemType &&
          other.brand == brand &&
          _sameList(other.colors, colors) &&
          other.material == material &&
          other.sizeOnTag == sizeOnTag &&
          _sameList(other.styleWords, styleWords) &&
          other.era == era &&
          _sameList(other.visibleFlaws, visibleFlaws) &&
          other.searchQueries == searchQueries;

  @override
  int get hashCode => Object.hash(
        title,
        itemType,
        brand,
        Object.hashAll(colors),
        material,
        sizeOnTag,
        Object.hashAll(styleWords),
        era,
        Object.hashAll(visibleFlaws),
        searchQueries,
      );

  @override
  String toString() => 'ListingFacts($title)';
}

/// A garment's measurements in inches, as Depop buyers ask for them.
///
/// Flat measurements, the way a seller takes them with a tape on a table: pit
/// to pit across the chest, length from the collar down, sleeve, waist and
/// inseam. Every one is optional, since which ones matter depends on what the
/// garment is, and a measurement of zero is no measurement at all.
final class Measurements {
  const Measurements({
    this.pitToPitIn,
    this.lengthIn,
    this.sleeveIn,
    this.waistIn,
    this.inseamIn,
  });

  static const Measurements none = Measurements();

  final double? pitToPitIn;
  final double? lengthIn;
  final double? sleeveIn;
  final double? waistIn;
  final double? inseamIn;

  /// The measurements that were given, in the order a buyer reads them, with
  /// the words used for each in a description.
  List<({String label, double inches})> get given => [
        if (pitToPitIn case final double inches when _usable(inches))
          (label: 'pit to pit', inches: inches),
        if (lengthIn case final double inches when _usable(inches))
          (label: 'length', inches: inches),
        if (sleeveIn case final double inches when _usable(inches))
          (label: 'sleeve', inches: inches),
        if (waistIn case final double inches when _usable(inches))
          (label: 'waist', inches: inches),
        if (inseamIn case final double inches when _usable(inches))
          (label: 'inseam', inches: inches),
      ];

  bool get isEmpty => given.isEmpty;

  static bool _usable(double inches) => inches.isFinite && inches > 0;

  /// Like the rest of the core's `copyWith`, a null leaves the value alone;
  /// the `clear` flags take one back.
  Measurements copyWith({
    double? pitToPitIn,
    double? lengthIn,
    double? sleeveIn,
    double? waistIn,
    double? inseamIn,
    bool clearPitToPit = false,
    bool clearLength = false,
    bool clearSleeve = false,
    bool clearWaist = false,
    bool clearInseam = false,
  }) =>
      Measurements(
        pitToPitIn: clearPitToPit ? null : (pitToPitIn ?? this.pitToPitIn),
        lengthIn: clearLength ? null : (lengthIn ?? this.lengthIn),
        sleeveIn: clearSleeve ? null : (sleeveIn ?? this.sleeveIn),
        waistIn: clearWaist ? null : (waistIn ?? this.waistIn),
        inseamIn: clearInseam ? null : (inseamIn ?? this.inseamIn),
      );

  Map<String, Object?> toJson() => {
        if (pitToPitIn != null) 'pitToPitIn': pitToPitIn,
        if (lengthIn != null) 'lengthIn': lengthIn,
        if (sleeveIn != null) 'sleeveIn': sleeveIn,
        if (waistIn != null) 'waistIn': waistIn,
        if (inseamIn != null) 'inseamIn': inseamIn,
      };

  factory Measurements.fromJson(Map<String, Object?> json) => Measurements(
        pitToPitIn: readDouble(json['pitToPitIn']),
        lengthIn: readDouble(json['lengthIn']),
        sleeveIn: readDouble(json['sleeveIn']),
        waistIn: readDouble(json['waistIn']),
        inseamIn: readDouble(json['inseamIn']),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Measurements &&
          other.pitToPitIn == pitToPitIn &&
          other.lengthIn == lengthIn &&
          other.sleeveIn == sleeveIn &&
          other.waistIn == waistIn &&
          other.inseamIn == inseamIn;

  @override
  int get hashCode =>
      Object.hash(pitToPitIn, lengthIn, sleeveIn, waistIn, inseamIn);

  @override
  String toString() => 'Measurements($given)';
}

/// Where a listing has got to.
enum ListingStatus {
  /// Being written. Not on Depop yet.
  draft,

  /// Posted on Depop, and not sold.
  listed,

  /// Sold.
  sold,
}

/// What a photograph on a listing is of.
///
/// The shots a Depop buyer looks for, which is not the same list as the
/// wardrobe's [PhotoRole]s: the wardrobe photographs a garment to recognise it
/// and read its label, while a listing photographs it to answer the questions a
/// buyer is about to ask.
enum ListingShot {
  cover(
    'Cover',
    'The first thing a buyer sees — lay it flat, or wear it.',
  ),
  back(
    'Back',
    'Buyers check the back for marks.',
  ),
  brandTag(
    'Brand tag',
    'Proves the brand, and the brand is what buyers search for.',
  ),
  sizeLabel(
    'Size label',
    'Size questions are the most common message.',
  ),
  careLabel(
    'Care label',
    'Shows the fabric and how to wash it, which saves a question.',
  ),
  flaw(
    'Flaw',
    'A pictured flaw is a disclosed flaw, not a return.',
  ),
  other(
    'Other',
    'Any other angle or detail that helps a buyer decide.',
  );

  const ListingShot(this.label, this.why);

  final String label;

  /// One line on why a buyer wants this photograph, shown beside the request
  /// for it.
  final String why;

  /// Whether the photo checklist always asks for this one.
  ///
  /// Cover, back, brand tag and size label are asked for on every listing. A
  /// flaw is asked for only when flaws are listed — a request for a photograph
  /// of a flaw on a garment with none would be a request to go looking — which
  /// is [Listing.missingShots]' job to decide.
  bool get isChecklist => switch (this) {
        ListingShot.cover ||
        ListingShot.back ||
        ListingShot.brandTag ||
        ListingShot.sizeLabel =>
          true,
        ListingShot.careLabel || ListingShot.flaw || ListingShot.other => false,
      };

  /// The listing shot a wardrobe photograph already is.
  ///
  /// So a listing made from a garment starts with the photographs the garment
  /// has instead of asking for them again. Exhaustive: a new wardrobe role has
  /// to be placed before it can appear on a listing.
  static ListingShot fromPhotoRole(PhotoRole role) => switch (role) {
        PhotoRole.front => ListingShot.cover,
        PhotoRole.back => ListingShot.back,
        PhotoRole.brandTag => ListingShot.brandTag,
        PhotoRole.careTag => ListingShot.careLabel,
        PhotoRole.condition => ListingShot.flaw,
        PhotoRole.logo ||
        PhotoRole.detail ||
        PhotoRole.worn =>
          ListingShot.other,
      };
}

/// One photograph on a listing.
final class ListingPhoto {
  const ListingPhoto({required this.uri, required this.shot});

  /// The same opaque image-store URI an [ItemPhoto] holds.
  ///
  /// So a listing made from a garment points at that garment's stored images
  /// instead of copying their bytes, and a photograph taken for a listing is
  /// stored the way any other is.
  final String uri;

  final ListingShot shot;

  ListingPhoto copyWith({String? uri, ListingShot? shot}) =>
      ListingPhoto(uri: uri ?? this.uri, shot: shot ?? this.shot);

  Map<String, Object?> toJson() => {'uri': uri, 'shot': shot.name};

  /// Reads one stored photograph, or null when it is not readable.
  static ListingPhoto? tryFromJson(Map<String, Object?> json) {
    final uri = readString(json['uri']);
    if (uri == null || uri.isEmpty) return null;

    return ListingPhoto(
      uri: uri,
      shot: readEnum(ListingShot.values, json['shot']) ?? ListingShot.other,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListingPhoto && other.uri == uri && other.shot == shot;

  @override
  int get hashCode => Object.hash(uri, shot);

  @override
  String toString() => 'ListingPhoto(${shot.name}, $uri)';
}

/// A garment being sold.
///
/// ## Three ways a listing starts
///
/// * [Listing.fromFacts] — from photographs, with what the server read off
///   them.
/// * [Listing.fromGarment] — from a garment already owned, where the wardrobe
///   knows more than any photograph shows.
/// * [Listing.empty] — written by hand, for when the server cannot be reached.
///
/// The app calls whichever applies and adds nothing of its own, so the rule for
/// which source wins is stated once, here.
final class Listing {
  Listing({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    this.itemId,
    this.status = ListingStatus.draft,
    this.listedAt,
    this.soldAt,
    this.soldPriceCents,
    this.department,
    this.title = '',
    this.itemType = ItemType.other,
    this.brand,
    this.sizeLabel,
    this.condition,
    List<DepopColour> colours = const [],
    this.material,
    this.measurements = Measurements.none,
    List<String> flaws = const [],
    List<String> styleWords = const [],
    this.era,
    this.notes,
    this.priceCents,
    this.priceSearch,
    this.facts,
    List<ListingPhoto> photos = const [],
    List<int> typedComparableCents = const [],
    this.typedComparablesSold = false,
  })  : colours = List<DepopColour>.unmodifiable(colours),
        flaws = List<String>.unmodifiable(flaws),
        styleWords = List<String>.unmodifiable(styleWords),
        photos = List<ListingPhoto>.unmodifiable(photos),
        typedComparableCents = List<int>.unmodifiable(typedComparableCents);

  /// A draft from what the photographs showed.
  ///
  /// Takes the title, type, brand, size off the tag, colours, material, flaws,
  /// style words and era as read. Nothing is graded and nothing is priced: the
  /// photographs cannot say how worn something is, and the price comes from
  /// evidence the person looks at.
  factory Listing.fromFacts({
    required ListingId id,
    required DateTime now,
    required ListingFacts facts,
    List<ListingPhoto> photos = const [],
  }) =>
      Listing(
        id: id,
        createdAt: now,
        updatedAt: now,
        title: facts.title,
        itemType: facts.itemType,
        brand: facts.brand?.value,
        sizeLabel: facts.sizeOnTag?.value,
        colours: depopColoursFor(facts.colors),
        material: facts.material,
        flaws: facts.visibleFlaws,
        styleWords: facts.styleWords,
        era: facts.era,
        facts: facts,
        photos: photos.take(depopPhotoLimit).toList(),
      );

  /// A blank draft, for writing a listing by hand.
  ///
  /// For when the server cannot be reached or the photographs could not be
  /// read. Blank is a valid draft: the editor asks for a title, and nothing is
  /// filled in that nobody said.
  factory Listing.empty({
    required ListingId id,
    required DateTime now,
    List<ListingPhoto> photos = const [],
  }) =>
      Listing(
        id: id,
        createdAt: now,
        updatedAt: now,
        photos: photos.take(depopPhotoLimit).toList(),
      );

  /// A draft from a garment already owned.
  ///
  /// **What the wardrobe knows wins.** Its type, brand, size label, colours and
  /// fabric are taken as they are; [facts], when there are some, only fill what
  /// the wardrobe lacks, and supply what it never has — a title, style words,
  /// an era, and flaws visible in the photographs. A brand somebody typed is
  /// not second-guessed from a picture of a sweatshirt.
  ///
  /// Two parts of that are narrower than "the wardrobe's word is final":
  ///
  /// * The **fabric** is used only when a label or the person stated it. A
  ///   composition that is only a model's guess from a photograph is not
  ///   something to sell on, and it is left for the facts, which read it off a
  ///   label or not at all.
  /// * The **department** comes from the garment's cut when that says men's or
  ///   women's, and is otherwise left for the person.
  ///
  /// The condition and the flaws come from [suggestCondition], with the facts'
  /// visible flaws added to them without repeats. Both are suggestions for the
  /// person to confirm.
  ///
  /// The photographs are the garment's own, display photo first, at most
  /// [depopPhotoLimit] of them. Originals, not cutouts: a buyer should see the
  /// garment, not a silhouette on transparency.
  ///
  /// Works when the description could not be fetched, with [facts] null: the
  /// title is then built from the brand, the type and the first colour.
  factory Listing.fromGarment({
    required ListingId id,
    required DateTime now,
    required WardrobeItem item,
    ListingFacts? facts,
  }) {
    final suggestion = suggestCondition(item);
    final colourNames = colourNamesOf(item);
    final type = item.type.value;
    final brand = _tidy(item.brand?.value) ?? facts?.brand?.value;

    var colours = depopColoursFor(colourNames);
    if (colours.isEmpty && facts != null) {
      colours = depopColoursFor(facts.colors);
    }

    return Listing(
      id: id,
      itemId: item.id,
      createdAt: now,
      updatedAt: now,
      department: departmentOf(item),
      title: _tidy(facts?.title) ??
          _titleFrom(brand: brand, type: type, colour: colourNames.firstOrNull),
      itemType: type,
      brand: brand,
      sizeLabel: _tidy(item.sizeLabel) ?? facts?.sizeOnTag?.value,
      condition: suggestion.condition,
      colours: colours,
      material: statedMaterial(item) ?? facts?.material,
      flaws: _withoutRepeats([
        ...suggestion.flaws,
        ...?facts?.visibleFlaws,
      ]),
      styleWords: facts?.styleWords ?? const [],
      era: facts?.era,
      facts: facts,
      photos: _photosOf(item),
    );
  }

  final ListingId id;

  /// The wardrobe garment this came from, when it came from one.
  ///
  /// How "Sell this" finds the listing already made for a garment instead of
  /// making a second, and how marking a listing sold can mark the garment.
  final ItemId? itemId;

  final ListingStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// When it was last posted or refreshed. Null for a draft.
  final DateTime? listedAt;

  final DateTime? soldAt;

  /// What it actually sold for, in US cents. Not necessarily the asking price:
  /// offers are the normal way things sell.
  final int? soldPriceCents;

  final DepopDepartment? department;

  /// Brand, item and the words a buyer searches for. The first line of the
  /// description.
  final String title;

  final ItemType itemType;
  final String? brand;

  /// As printed on the garment: `M`, `W32 L30`, `UK 10`.
  final String? sizeLabel;

  /// Null until somebody has graded it. Never filled in silently.
  final DepopCondition? condition;

  /// Up to [depopColourLimit].
  final List<DepopColour> colours;

  /// As a composition label states it.
  final String? material;

  final Measurements measurements;

  /// Everything a buyer should be told is wrong with it, one line each.
  ///
  /// The description always says what is here, and never claims there is
  /// nothing: an empty list means none were listed, not that none exist.
  final List<String> flaws;

  /// Search words: cut, style, print.
  final List<String> styleWords;

  /// `90s`, `Y2K`. Only when known.
  final String? era;

  /// Anything else the person wants a buyer to read.
  final String? notes;

  /// The asking price the person chose, in US cents. Null until they have.
  final int? priceCents;

  /// The last price search, with the evidence it found.
  final PriceSearch? priceSearch;

  /// What the photographs showed, as the server read it. Kept so the editor can
  /// show how sure the reading was.
  final ListingFacts? facts;

  /// Cover first, at most [depopPhotoLimit].
  final List<ListingPhoto> photos;

  /// Prices the person typed after following the links, in US cents.
  ///
  /// The search will not find everything — a Depop page that is not indexed is
  /// invisible to it — so the price suggestion also takes what the person saw
  /// themselves.
  final List<int> typedComparableCents;

  /// Whether those typed prices were what things sold for. Sold prices outrank
  /// asking prices, so the person is asked which they are.
  final bool typedComparablesSold;

  // --- Derived ------------------------------------------------------------

  /// The photographs the checklist still wants.
  ///
  /// The always-asked shots with no photograph — see [ListingShot.isChecklist]
  /// — and a photograph of the flaw when flaws are listed and none is
  /// pictured. In the order the checklist shows them.
  Set<ListingShot> get missingShots {
    bool pictured(ListingShot shot) => photos.any((p) => p.shot == shot);

    return {
      for (final shot in ListingShot.values)
        if (shot.isChecklist && !pictured(shot)) shot,
      if (flaws.isNotEmpty && !pictured(ListingShot.flaw)) ListingShot.flaw,
    };
  }

  /// Whether it has sat long enough to be worth refreshing.
  ///
  /// Listed, not sold, and posted [listingRefreshAfter] or more ago. A draft
  /// has not been posted to go stale and a sold listing is finished.
  bool needsRefresh(DateTime now) {
    final posted = listedAt;
    if (status != ListingStatus.listed || posted == null) return false;
    return !now.isBefore(posted.add(listingRefreshAfter));
  }

  /// How long it was, or has been, on sale.
  ///
  /// For a listing still up it is the time since it was posted. For a sold one
  /// the clock stopped when it sold, so it is how long it took. A draft has
  /// not been on sale, and the answer is null.
  Duration? listedFor(DateTime now) {
    final posted = listedAt;
    if (posted == null) return null;

    final until = switch (status) {
      ListingStatus.draft => null,
      ListingStatus.listed => now,
      ListingStatus.sold => soldAt ?? now,
    };
    if (until == null) return null;

    final elapsed = until.difference(posted);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  /// What to search with: the phrases of the last search, else those the
  /// photographs produced, else words built from the listing itself.
  ///
  /// Null when there is too little to search on. The last search comes first
  /// because the person may have corrected its phrases, and a second look-up
  /// should start from the corrected ones.
  SearchQueries? get searchQueries {
    final searched = priceSearch?.queries;
    if (searched != null && searched.isSearchable) return searched;

    final read = facts?.searchQueries;
    if (read != null && read.isSearchable) return read;

    return _queriesFromWords();
  }

  /// Whether a price search can be run for this listing.
  ///
  /// The server needs a title of at least three characters and two search
  /// phrases; this is the check so that a screen does not have to know that.
  bool get canLookUpPrices =>
      title.trim().length >= SearchQueries.minLength &&
      (searchQueries?.isSearchable ?? false);

  SearchQueries? _queriesFromWords() {
    final typeWord =
        itemType == ItemType.other ? null : itemType.label.toLowerCase();
    final colourWord =
        colours.isEmpty ? null : colours.first.label.toLowerCase();
    final brandWord = _tidy(brand);

    String join(List<String?> words) =>
        words.whereType<String>().where((w) => w.isNotEmpty).join(' ');

    final typed = title.trim();
    final depop = typed.length >= SearchQueries.minLength
        ? typed
        : join([brandWord, colourWord, typeWord]);
    final retail = join([brandWord, typeWord, colourWord]);

    final built = SearchQueries(
      depop: _clip(depop),
      retail: _clip(retail.length >= SearchQueries.minLength ? retail : depop),
    );
    return built.isSearchable ? built : null;
  }

  // --- Changes ------------------------------------------------------------

  /// A copy with some fields changed.
  ///
  /// A null argument leaves the field alone, as in the rest of the core, so the
  /// `clear` flags exist for the nullable fields somebody can take back: the
  /// department, brand, size, condition, material, era, notes, asking price,
  /// price search and facts, and the three lifecycle dates and the sold price.
  /// Which listing it is ([id]), where it came from ([itemId]) and when it was
  /// created do not change.
  ///
  /// [updatedAt] is not touched unless given: the caller owns the clock.
  Listing copyWith({
    ListingStatus? status,
    DateTime? listedAt,
    DateTime? soldAt,
    int? soldPriceCents,
    DepopDepartment? department,
    String? title,
    ItemType? itemType,
    String? brand,
    String? sizeLabel,
    DepopCondition? condition,
    List<DepopColour>? colours,
    String? material,
    Measurements? measurements,
    List<String>? flaws,
    List<String>? styleWords,
    String? era,
    String? notes,
    int? priceCents,
    PriceSearch? priceSearch,
    ListingFacts? facts,
    List<ListingPhoto>? photos,
    List<int>? typedComparableCents,
    bool? typedComparablesSold,
    DateTime? updatedAt,
    bool clearListedAt = false,
    bool clearSoldAt = false,
    bool clearSoldPrice = false,
    bool clearDepartment = false,
    bool clearBrand = false,
    bool clearSizeLabel = false,
    bool clearCondition = false,
    bool clearMaterial = false,
    bool clearEra = false,
    bool clearNotes = false,
    bool clearPrice = false,
    bool clearPriceSearch = false,
    bool clearFacts = false,
  }) =>
      Listing(
        id: id,
        itemId: itemId,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        listedAt: clearListedAt ? null : (listedAt ?? this.listedAt),
        soldAt: clearSoldAt ? null : (soldAt ?? this.soldAt),
        soldPriceCents:
            clearSoldPrice ? null : (soldPriceCents ?? this.soldPriceCents),
        department: clearDepartment ? null : (department ?? this.department),
        title: title ?? this.title,
        itemType: itemType ?? this.itemType,
        brand: clearBrand ? null : (brand ?? this.brand),
        sizeLabel: clearSizeLabel ? null : (sizeLabel ?? this.sizeLabel),
        condition: clearCondition ? null : (condition ?? this.condition),
        colours: colours ?? this.colours,
        material: clearMaterial ? null : (material ?? this.material),
        measurements: measurements ?? this.measurements,
        flaws: flaws ?? this.flaws,
        styleWords: styleWords ?? this.styleWords,
        era: clearEra ? null : (era ?? this.era),
        notes: clearNotes ? null : (notes ?? this.notes),
        priceCents: clearPrice ? null : (priceCents ?? this.priceCents),
        priceSearch:
            clearPriceSearch ? null : (priceSearch ?? this.priceSearch),
        facts: clearFacts ? null : (facts ?? this.facts),
        photos: photos ?? this.photos,
        typedComparableCents: typedComparableCents ?? this.typedComparableCents,
        typedComparablesSold: typedComparablesSold ?? this.typedComparablesSold,
      );

  /// Records that it was posted on Depop at [at].
  ///
  /// Doing it again is how a refresh is recorded: it restarts the clock that
  /// [needsRefresh] watches. A listing that had been marked sold and is now
  /// back on sale — a buyer who never paid — loses its sale.
  Listing markListed(DateTime at) => copyWith(
        status: ListingStatus.listed,
        listedAt: at,
        clearSoldAt: true,
        clearSoldPrice: true,
        updatedAt: at,
      );

  /// Records that it sold at [at], for [priceCents] if given.
  ///
  /// The price defaults to the asking price: the common case is that it sold
  /// for what it was listed at, and the person is asked only when it did not.
  /// With neither, the sold price is unknown and stays unknown rather than
  /// becoming zero.
  Listing markSold(DateTime at, {int? priceCents}) {
    final paid = priceCents ?? this.priceCents;

    return copyWith(
      status: ListingStatus.sold,
      soldAt: at,
      soldPriceCents: paid,
      clearSoldPrice: paid == null,
      updatedAt: at,
    );
  }

  /// Takes it back to a draft, forgetting when it was posted and any sale.
  ///
  /// For a listing taken down, or "It sold" tapped by mistake. Pass [at] to
  /// stamp the change; without it [updatedAt] is left as it was.
  Listing backToDraft({DateTime? at}) => copyWith(
        status: ListingStatus.draft,
        clearListedAt: true,
        clearSoldAt: true,
        clearSoldPrice: true,
        updatedAt: at,
      );

  // --- Storage ------------------------------------------------------------

  /// The storage form, with a version so a later shape can recognise this one.
  Map<String, Object?> toJson() => {
        'v': _storageVersion,
        'id': id.value,
        if (itemId != null) 'itemId': itemId!.value,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (listedAt != null) 'listedAt': listedAt!.toIso8601String(),
        if (soldAt != null) 'soldAt': soldAt!.toIso8601String(),
        if (soldPriceCents != null) 'soldPriceCents': soldPriceCents,
        if (department != null) 'department': department!.name,
        'title': title,
        'itemType': itemType.name,
        if (brand != null) 'brand': brand,
        if (sizeLabel != null) 'sizeLabel': sizeLabel,
        if (condition != null) 'condition': condition!.name,
        'colours': [for (final c in colours) c.name],
        if (material != null) 'material': material,
        'measurements': measurements.toJson(),
        'flaws': flaws,
        'styleWords': styleWords,
        if (era != null) 'era': era,
        if (notes != null) 'notes': notes,
        if (priceCents != null) 'priceCents': priceCents,
        if (priceSearch != null) 'priceSearch': priceSearch!.toJson(),
        if (facts != null) 'facts': facts!.toJson(),
        'photos': [for (final p in photos) p.toJson()],
        'typedComparableCents': typedComparableCents,
        'typedComparablesSold': typedComparablesSold,
      };

  /// Reads the storage form.
  ///
  /// Tolerant by design, because it will be reading what an earlier build
  /// wrote. Unknown keys are ignored; an optional key that is missing is
  /// absent; a name this build does not know (a status, a colour or a
  /// condition added later) falls back to the safe reading and not an error. A
  /// field added to a later version therefore cannot make an older stored
  /// listing unreadable.
  ///
  /// Only a listing with no id or no creation time is refused, with a
  /// [FormatException]: it cannot be found or ordered, and pretending
  /// otherwise would store a listing nobody can reopen.
  factory Listing.fromJson(Map<String, Object?> json) {
    final id = readTrimmed(json['id']);
    if (id == null) {
      throw const FormatException('a stored listing has no id');
    }
    final createdAt = readDateTime(json['createdAt']);
    if (createdAt == null) {
      throw FormatException('stored listing $id has no creation time');
    }

    final itemId = readTrimmed(json['itemId']);
    final priceSearch = readObject(json['priceSearch']);
    final facts = readObject(json['facts']);

    return Listing(
      id: ListingId(id),
      itemId: itemId == null ? null : ItemId(itemId),
      status:
          readEnum(ListingStatus.values, json['status']) ?? ListingStatus.draft,
      createdAt: createdAt,
      updatedAt: readDateTime(json['updatedAt']) ?? createdAt,
      listedAt: readDateTime(json['listedAt']),
      soldAt: readDateTime(json['soldAt']),
      soldPriceCents: readInt(json['soldPriceCents']),
      department: readEnum(DepopDepartment.values, json['department']),
      title: readString(json['title']) ?? '',
      itemType: readEnum(ItemType.values, json['itemType']) ?? ItemType.other,
      brand: readString(json['brand']),
      sizeLabel: readString(json['sizeLabel']),
      condition: readEnum(DepopCondition.values, json['condition']),
      colours: readStrings(json['colours'])
          .map((name) => DepopColour.values.asNameMap()[name])
          .whereType<DepopColour>()
          .toList(),
      material: readString(json['material']),
      measurements:
          Measurements.fromJson(readObject(json['measurements']) ?? const {}),
      flaws: readStrings(json['flaws']),
      styleWords: readStrings(json['styleWords']),
      era: readString(json['era']),
      notes: readString(json['notes']),
      priceCents: readInt(json['priceCents']),
      priceSearch:
          priceSearch == null ? null : PriceSearch.fromJson(priceSearch),
      facts: facts == null ? null : ListingFacts.fromJson(facts),
      photos: readObjects(json['photos'])
          .map(ListingPhoto.tryFromJson)
          .whereType<ListingPhoto>()
          .toList(),
      typedComparableCents: [
        if (json['typedComparableCents'] case final List<Object?> prices)
          for (final price in prices)
            if (readInt(price) case final int cents) cents,
      ],
      typedComparablesSold: readBool(json['typedComparablesSold']) ?? false,
    );
  }

  // --- Equality -----------------------------------------------------------

  /// By value, unlike [WardrobeItem], which is its id.
  ///
  /// A garment is one physical thing whose copies may be stale; a listing is a
  /// document being edited, and the question a screen asks is "has this
  /// changed since it was saved?". Equal by id would answer no to every edit.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Listing &&
          other.id == id &&
          other.itemId == itemId &&
          other.status == status &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.listedAt == listedAt &&
          other.soldAt == soldAt &&
          other.soldPriceCents == soldPriceCents &&
          other.department == department &&
          other.title == title &&
          other.itemType == itemType &&
          other.brand == brand &&
          other.sizeLabel == sizeLabel &&
          other.condition == condition &&
          _sameList(other.colours, colours) &&
          other.material == material &&
          other.measurements == measurements &&
          _sameList(other.flaws, flaws) &&
          _sameList(other.styleWords, styleWords) &&
          other.era == era &&
          other.notes == notes &&
          other.priceCents == priceCents &&
          other.priceSearch == priceSearch &&
          other.facts == facts &&
          _sameList(other.photos, photos) &&
          _sameList(other.typedComparableCents, typedComparableCents) &&
          other.typedComparablesSold == typedComparablesSold;

  @override
  int get hashCode => Object.hashAll([
        id,
        itemId,
        status,
        createdAt,
        updatedAt,
        listedAt,
        soldAt,
        soldPriceCents,
        department,
        title,
        itemType,
        brand,
        sizeLabel,
        condition,
        Object.hashAll(colours),
        material,
        measurements,
        Object.hashAll(flaws),
        Object.hashAll(styleWords),
        era,
        notes,
        priceCents,
        priceSearch,
        facts,
        Object.hashAll(photos),
        Object.hashAll(typedComparableCents),
        typedComparablesSold,
      ]);

  @override
  String toString() => 'Listing(${id.value}, ${status.name}, $title)';
}

/// The version written into a stored listing.
const int _storageVersion = 1;

/// [text] trimmed, or null when nothing is left.
String? _tidy(String? text) {
  final trimmed = text?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// [text] cut to the longest search phrase the server takes.
String _clip(String text) {
  final runes = text.runes.toList();
  if (runes.length <= SearchQueries.maxLength) return text;
  return String.fromCharCodes(runes.take(SearchQueries.maxLength)).trimRight();
}

/// `Nike sweatshirt grey`: what a title is when nobody has read the photographs.
///
/// The type is left out when it is [ItemType.other] — "Nike other grey" is not
/// a title.
String _titleFrom({
  required String? brand,
  required ItemType type,
  required String? colour,
}) =>
    [
      if (brand != null) brand,
      if (type != ItemType.other) type.label.toLowerCase(),
      if (colour != null) colour.toLowerCase(),
    ].join(' ');

/// [lines] without any that repeat an earlier one, ignoring case and spacing.
List<String> _withoutRepeats(List<String> lines) {
  final seen = <String>{};
  return [
    for (final line in lines)
      if (_tidy(line) case final String text)
        if (seen.add(text.toLowerCase())) text,
  ];
}

/// The garment's photographs as listing photographs, display photo first.
List<ListingPhoto> _photosOf(WardrobeItem item) {
  final shown = item.photos.displayPhoto;

  final ordered = [
    if (shown != null) shown,
    for (final photo in item.photos.photos)
      if (photo.uri != shown?.uri) photo,
  ];

  return [
    for (final photo in ordered.take(depopPhotoLimit))
      ListingPhoto(uri: photo.uri, shot: ListingShot.fromPhotoRole(photo.role)),
  ];
}
