/// Builders for the selling tests.
///
/// A listing has a lot of fields, and the interesting tests are about one of
/// them. [fullListing] fills in every field with something that is not its
/// default, so a field that a round trip or a copy drops cannot hide behind the
/// value it would have had anyway.
library;

import 'dart:convert';

import 'package:wardrobe_core/wardrobe_core.dart';

/// A fixed instant, so date assertions are exact.
final listingCreated = DateTime.utc(2026, 10, 1, 9);

SaleComparable comparable({
  int priceCents = 3200,
  bool? sold = true,
  ComparableMatch match = ComparableMatch.same,
  String title = 'Vintage Nike grey crewneck',
  String? condition = 'Used - Excellent',
  String? why = 'Same 90s Nike crewneck, also grey',
}) =>
    SaleComparable(
      title: title,
      url: Uri.parse('https://www.depop.com/products/example-1/'),
      priceCents: priceCents,
      sold: sold,
      condition: condition,
      match: match,
      why: why,
    );

RetailReference reference({
  int priceCents = 6000,
  ComparableMatch match = ComparableMatch.similar,
}) =>
    RetailReference(
      title: 'Nike Sportswear Club Fleece Crew',
      url: Uri.parse('https://www.nike.com/t/club-fleece-crew'),
      priceCents: priceCents,
      seller: 'nike.com',
      match: match,
    );

PriceSearch fullSearch() => PriceSearch(
      status: PriceSearchStatus.ok,
      searchedAt: DateTime.utc(2026, 10, 17, 14, 5),
      provider: 'tavily',
      queries: const SearchQueries(
        depop: 'Nike vintage crewneck sweatshirt grey',
        retail: 'Nike Club Fleece crew sweatshirt grey',
      ),
      comparables: [comparable(), comparable(priceCents: 2800, sold: false)],
      retail: [reference()],
      excluded: const ExcludedCounts(
        notUsd: 2,
        unverifiedPrice: 1,
        notComparable: 4,
      ),
    );

ListingFacts fullFacts() => ListingFacts(
      title: 'Nike vintage crewneck sweatshirt grey',
      itemType: ItemType.sweatshirt,
      brand: Confident(
        'Nike',
        confidence: 0.93,
        source: Provenance.aiInference,
      ),
      colors: const ['Grey'],
      material: '80% cotton, 20% polyester',
      sizeOnTag: Confident(
        'M',
        confidence: 0.9,
        source: Provenance.aiInference,
      ),
      styleWords: const ['vintage', 'crewneck', 'embroidered logo', '90s'],
      era: '90s',
      visibleFlaws: const ['small mark on the left cuff'],
      searchQueries: const SearchQueries(
        depop: 'Nike vintage crewneck sweatshirt grey',
        retail: 'Nike Club Fleece crew sweatshirt grey',
      ),
    );

/// A listing with every field filled in and none of them at its default.
Listing fullListing() => Listing(
      id: const ListingId('listing-1'),
      itemId: const ItemId('item-1'),
      status: ListingStatus.sold,
      createdAt: listingCreated,
      updatedAt: DateTime.utc(2026, 10, 20, 18, 30),
      listedAt: DateTime.utc(2026, 10, 2, 10),
      soldAt: DateTime.utc(2026, 10, 20, 18, 30),
      soldPriceCents: 2800,
      department: DepopDepartment.men,
      title: 'Nike vintage crewneck sweatshirt grey',
      itemType: ItemType.sweatshirt,
      brand: 'Nike',
      sizeLabel: 'M',
      condition: DepopCondition.usedExcellent,
      colours: const [DepopColour.grey, DepopColour.white],
      material: '80% cotton, 20% polyester',
      measurements: const Measurements(
        pitToPitIn: 21,
        lengthIn: 27.5,
        sleeveIn: 24,
        waistIn: 30,
        inseamIn: 32,
      ),
      flaws: const ['small mark on the left cuff', 'light pilling'],
      styleWords: const ['vintage', 'crewneck'],
      era: '90s',
      notes: 'Ships within 5 days.',
      priceCents: 3000,
      priceSearch: fullSearch(),
      facts: fullFacts(),
      photos: const [
        ListingPhoto(uri: 'store://cover.jpg', shot: ListingShot.cover),
        ListingPhoto(uri: 'store://cuff.jpg', shot: ListingShot.flaw),
      ],
      typedComparableCents: const [2500, 2900],
      typedComparablesSold: true,
    );

/// A bare draft with a title, for tests that are about something else.
Listing draftListing({
  String id = 'draft-1',
  String title = 'Nike crewneck',
  List<ListingPhoto> photos = const [],
  List<String> flaws = const [],
  DateTime? updatedAt,
  ItemId? itemId,
}) =>
    Listing(
      id: ListingId(id),
      itemId: itemId,
      createdAt: listingCreated,
      updatedAt: updatedAt ?? listingCreated,
      title: title,
      flaws: flaws,
      photos: photos,
    );

/// Sends JSON through real text, so a field that only survives as a Dart
/// object (a `Uri`, a `DateTime`) is caught.
Map<String, Object?> viaText(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;
