/// The selling contract, read and written: `contracts/listing.schema.json`.
///
/// Two calls cross the wire. *Describe* sends photographs and gets back a draft
/// listing's facts; *prices* sends search phrases and gets back comparables.
/// The server is Python and the app is Dart, so the agreement is the schema and
/// the golden fixtures in `contracts/examples/listing/`, which tests on both
/// sides parse. Nothing here decides anything: the response is a proposal to
/// show a person, and the arithmetic that turns it into a price is
/// [suggestPrice].
///
/// ## How strictly the response is read
///
/// The server vets its own answer before sending it, and this vets it again.
/// The two checks are not redundant: a price shown on a screen is a number
/// somebody acts on, and the cost of trusting the other end of a wire is
/// borne by the person holding the phone.
///
/// * A comparable that cannot be used — a link that is not `https`, a price
///   that is missing, zero or not in US dollars — is **skipped**, not thrown
///   on. One bad entry in twelve is not a reason to show none, and an entry
///   the app cannot link to or price is one it should not show.
/// * A response that cannot be read *at all* — a description with no title —
///   is thrown on, as a [FormatException], so the app can fall back to writing
///   the listing by hand.
///
/// Item types travel under their Dart names, as in the scan contract; a type
/// this build does not know is [ItemType.other].
///
/// ## How requests are written
///
/// Absent means unknown, the contract's one rule: a key is left out when there
/// is nothing to say, never sent empty or null. Text is trimmed and cut to the
/// schema's lengths, because a request the server rejects for being a
/// character too long helps nobody.
library;

import '../wardrobe/model/item_attributes.dart';
import '../wardrobe/model/wardrobe_item.dart';
import 'garment_facts.dart';
import 'lenient_json.dart';
import 'listing.dart';

/// Reads the `result` of a describe response.
///
/// Throws a [FormatException] if it has no title, which is the one thing a
/// draft cannot do without. Everything else absent is read as unknown.
ListingFacts listingFactsFromJson(Map<String, Object?> result) {
  if (readTrimmed(result['title']) == null) {
    throw const FormatException('the description response has no title');
  }
  return ListingFacts.fromJson(result);
}

/// Reads the `result` of a prices response.
///
/// Prices arrive in dollars and are held in cents, rounded to the nearest. A
/// status this build does not know is [PriceSearchStatus.unavailable]: the safe
/// reading of a result nobody can interpret is that there is none.
PriceSearch priceSearchFromJson(Map<String, Object?> result) => PriceSearch(
      status: readEnum(PriceSearchStatus.values, result['status']) ??
          PriceSearchStatus.unavailable,
      searchedAt: readDateTime(result['searchedAt'])?.toUtc(),
      provider: readTrimmed(result['provider']),
      queries:
          SearchQueries.fromJson(readObject(result['queries']) ?? const {}),
      comparables: [
        for (final entry in readObjects(result['comparables']))
          if (_comparableFromWire(entry) case final SaleComparable c) c,
      ],
      retail: [
        for (final entry in readObjects(result['retail']))
          if (_retailFromWire(entry) case final RetailReference r) r,
      ],
      excluded:
          ExcludedCounts.fromJson(readObject(result['excluded']) ?? const {}),
    );

/// The dearest price the contract carries, in dollars.
const int _maxPriceDollars = 100000;

SaleComparable? _comparableFromWire(Map<String, Object?> json) {
  final title = readTrimmed(json['title']);
  final url = _httpsUrl(json['url']);
  final cents = _usdCents(json);
  if (title == null || url == null || cents == null) return null;

  return SaleComparable(
    title: title,
    url: url,
    priceCents: cents,
    sold: readBool(json['sold']),
    condition: readTrimmed(json['condition']),
    match: _matchFromWire(json['match']),
    why: readTrimmed(json['why']),
  );
}

RetailReference? _retailFromWire(Map<String, Object?> json) {
  final title = readTrimmed(json['title']);
  final url = _httpsUrl(json['url']);
  final cents = _usdCents(json);
  if (title == null || url == null || cents == null) return null;

  return RetailReference(
    title: title,
    url: url,
    priceCents: cents,
    seller: readTrimmed(json['seller']),
    match: _matchFromWire(json['match']),
  );
}

/// A link that is safe to show and open: `https`, with a host.
///
/// Anything else — a `javascript:` link, plain `http`, a bare path — is not
/// something to put under a tap.
Uri? _httpsUrl(Object? raw) {
  final text = readTrimmed(raw);
  if (text == null) return null;

  final url = Uri.tryParse(text);
  if (url == null || url.scheme != 'https' || url.host.isEmpty) return null;
  return url;
}

/// The price in US cents, or null when it is not one the app should use.
///
/// Missing, zero, negative, not a number, beyond the contract's maximum, or in
/// any currency but US dollars. A price in another currency is not converted:
/// a comparable built on an invented exchange rate looks like evidence and is
/// not.
int? _usdCents(Map<String, Object?> json) {
  if (json['currency'] != 'USD') return null;

  final dollars = json['price'];
  if (dollars is! num || !dollars.isFinite) return null;
  if (dollars <= 0 || dollars > _maxPriceDollars) return null;

  final cents = (dollars * 100).round();
  return cents > 0 ? cents : null;
}

/// How alike, with the cautious reading of one this build has not heard of.
///
/// A new level of match from a newer server is not known to be the same
/// product, and "similar" is the one that does not overstate it.
ComparableMatch _matchFromWire(Object? raw) =>
    readEnum(ComparableMatch.values, raw) ?? ComparableMatch.similar;

// --- Requests -------------------------------------------------------------

// The schema's lengths. `contract_test.dart` checks each against the schema
// file, so that changing one side without the other fails a test.
const int _maxQuery = SearchQueries.maxLength;
const int _maxTitle = 80;
const int _maxBrand = 60;
const int _maxColour = 30;
const int _maxColours = 3;
const int _maxMaterial = 120;
const int _maxSize = 30;
const int _maxNotes = 300;

/// The body of `POST /v1/sell/prices`.
///
/// A phrase the server would reject for being too short is sent anyway:
/// there is nothing to cut it to. [Listing.canLookUpPrices] is the check to
/// make before asking.
Map<String, Object?> priceSearchRequestJson({
  required SearchQueries queries,
  required ItemType itemType,
  required String title,
  String? brand,
  List<String> colors = const [],
}) {
  final brandText = _bounded(brand, _maxBrand);
  final colourTexts = _colours(colors);

  return {
    'queries': {
      'depop': _bounded(queries.depop, _maxQuery) ?? '',
      'retail': _bounded(queries.retail, _maxQuery) ?? '',
    },
    'itemType': itemType.name,
    'title': _bounded(title, _maxTitle) ?? '',
    if (brandText != null) 'brand': brandText,
    if (colourTexts.isNotEmpty) 'colors': colourTexts,
  };
}

/// The `context` sent with the photographs to `POST /v1/sell/describe`, when
/// the garment is already in the wardrobe.
///
/// What the app already knows outranks a fresh reading: a brand the person
/// typed is not second-guessed from a photograph, so each thing known goes
/// under `known`, and the server's description is written around it. Only what
/// is known is sent. A key for something unknown would be a claim that it is
/// known to be nothing.
///
/// Empty (`{}`) when nothing is known, which the contract allows.
Map<String, Object?> describeContextJson({
  ItemType? itemType,
  String? brand,
  List<String> colors = const [],
  String? material,
  String? sizeLabel,
  String? notes,
}) {
  final brandText = _bounded(brand, _maxBrand);
  final colourTexts = _colours(colors);
  final materialText = _bounded(material, _maxMaterial);
  final sizeText = _bounded(sizeLabel, _maxSize);
  final notesText = _bounded(notes, _maxNotes);

  final known = <String, Object?>{
    if (itemType != null) 'itemType': itemType.name,
    if (brandText != null) 'brand': brandText,
    if (colourTexts.isNotEmpty) 'colors': colourTexts,
    if (materialText != null) 'material': materialText,
    if (sizeText != null) 'sizeLabel': sizeText,
  };

  return {
    if (known.isNotEmpty) 'known': known,
    if (notesText != null) 'notes': notesText,
  };
}

/// The describe `context` for a garment already owned.
///
/// What the wardrobe can honestly say about it:
///
/// * its type — except [ItemType.other], which says the wardrobe had no better
///   word, and is not something the photographs should be held to;
/// * its brand, colour names and size label, as the person or a scan left them;
/// * its fabric, only if a label or the person stated it. A composition that
///   is a model's guess from a photograph is not "known" in the sense this
///   field means, and sending it would hand the server its own guess back as a
///   fact;
/// * notes: how often it has been worn ("Worn 12 times."), then anything the
///   person typed in the garment's notes, cut to the 300 characters allowed.
///
/// Whatever is absent stays absent.
Map<String, Object?> describeContextForItem(WardrobeItem item) {
  final type = item.type.value;
  final worn = item.usage.timesWorn;
  final typed = item.notes?.trim();

  return describeContextJson(
    itemType: type == ItemType.other ? null : type,
    brand: item.brand?.value,
    colors: colourNamesOf(item),
    material: statedMaterial(item),
    sizeLabel: item.sizeLabel,
    notes: [
      if (worn > 0) 'Worn ${timesWornPhrase(worn)}.',
      if (typed != null && typed.isNotEmpty) typed,
    ].join(' '),
  );
}

/// [text] trimmed and cut to [max] characters, or null when nothing is left.
///
/// Cut by character and not by code unit, since the schema counts characters
/// and an emoji cut in half is not valid text.
String? _bounded(String? text, int max) {
  final trimmed = text?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;

  final runes = trimmed.runes;
  if (runes.length <= max) return trimmed;
  return String.fromCharCodes(runes.take(max)).trimRight();
}

/// Colour names, trimmed, empty ones dropped, and at most the three the
/// contract allows.
List<String> _colours(List<String> names) {
  final cleaned = <String>[];
  for (final name in names) {
    final text = _bounded(name, _maxColour);
    if (text != null) cleaned.add(text);
    if (cleaned.length == _maxColours) break;
  }
  return cleaned;
}
