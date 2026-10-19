/// The text of a Depop listing: what a buyer reads, and the tags they find it by.
///
/// Composed from the listing's own fields and never typed by hand, so that what
/// the person edits is facts — a brand, a size, a flaw — and what they paste is
/// the same facts laid out the same way every time. A description written
/// fresh for each listing leaves things out; one assembled from fields cannot
/// forget the size, because the size line is simply not there when the field is
/// empty and the editor shows that it is.
///
/// Written for a buyer, in US English: "Color", not "Colour".
///
/// ## What it will not do
///
/// It never says a garment has no flaws. An empty list of flaws means none were
/// listed, not that none exist, and "no flaws" in a seller's voice is a
/// promise the app has no way to keep — the photographs it read the listing
/// from said only that nothing was *visible*. With no flaws listed the
/// condition line is just the condition.
///
/// ## When it is too long
///
/// Depop takes [depopDescriptionLimit] characters. Past that it gives things up
/// in the order they matter least to a buyer, and stops as soon as it fits:
///
/// 1. the person's own notes — an afterthought beside facts;
/// 2. all but the first flaw, with "and others" saying there were more;
/// 3. the style-word hashtags, keeping brand, type and era;
/// 4. every hashtag.
///
/// The flaws go late and are cut short only, never dropped: telling a buyer
/// what is wrong is the part of the description that costs the seller most to
/// leave out. If it still does not fit — a title of two thousand characters —
/// it is cut at the limit and ends in an ellipsis, because a listing Depop
/// refuses is worse than one that stops short.
library;

import '../wardrobe/model/item_attributes.dart';
import 'depop.dart';
import 'listing.dart';

/// How many hashtags and how many characters a description has, against what
/// Depop allows.
///
/// For the counters under the text box: "312 / 1,000" and "5 / 5".
final class DescriptionCheck {
  const DescriptionCheck({required this.length, required this.hashtagCount});

  /// Characters, counted as Dart counts a string: in UTF-16 code units, so an
  /// emoji is two. The same count is used to keep a composed description within
  /// [depopDescriptionLimit], so the two never disagree about its length.
  final int length;

  /// Words that start with `#`.
  final int hashtagCount;

  bool get overLimit => length > depopDescriptionLimit;

  bool get tooManyHashtags => hashtagCount > depopHashtagLimit;
}

/// Counts the characters and the hashtags in [text].
///
/// A hashtag is a `#` followed by letters, digits or underscores, and not
/// itself in the middle of a word — `#nike` and `(#nike)` count, `item#4` and a
/// link's `#section` do not. Every occurrence counts, repeats included: five
/// tags written is five used, whether or not two of them are the same.
DescriptionCheck checkDescription(String text) => DescriptionCheck(
      length: text.length,
      hashtagCount: _hashtagPattern.allMatches(text).length,
    );

final RegExp _hashtagPattern = RegExp(
  r'(?<![\p{L}\p{N}_])#[\p{L}\p{N}_]+',
  unicode: true,
);

/// The hashtags for [listing], at most [depopHashtagLimit] of them.
///
/// From, in this order: the brand, the words of the item type, the era, and the
/// style words. That is the order a buyer searches in: the brand first because
/// it is what they know, the thing second, and only then the adjectives. Lower
/// case and letters and digits only, since a tag with an apostrophe in it
/// ("levi's") is not one Depop will match — it becomes `#levis`. A brand or a
/// style word of several words is run together (`#calvinklein`), as people
/// write them.
///
/// Each appears once, however many ways it was reached, and nothing that is
/// left empty by the cleaning ("&&") becomes a bare `#`.
List<String> hashtagsFor(Listing listing) =>
    _hashtags(listing, styleWords: true);

List<String> _hashtags(
  Listing listing, {
  required bool styleWords,
  int limit = depopHashtagLimit,
  Set<String> alreadyUsed = const {},
}) {
  final brand = listing.brand;
  final era = listing.era;

  final words = <String>[
    if (brand != null) brand,
    if (listing.itemType != ItemType.other)
      ...listing.itemType.label.split(RegExp(r'\s+')),
    if (era != null) era,
    if (styleWords) ...listing.styleWords,
  ];

  final seen = {...alreadyUsed};
  final tags = <String>[];
  for (final word in words) {
    if (tags.length >= limit) break;

    final tag = _tagText(word);
    if (tag.isEmpty || !seen.add(tag)) continue;
    tags.add('#$tag');
  }
  return tags;
}

/// [word] as the text of a hashtag: lower case, letters and digits only.
String _tagText(String word) =>
    word.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// The listing as a description, ready to paste, never longer than Depop takes.
///
/// ```
/// Nike vintage crewneck sweatshirt grey
///
/// Brand: Nike
/// Size: M
/// Measurements: pit to pit 21", length 27"
/// Condition: Used - Excellent. Flaws: small mark on the left cuff (see photos).
/// Color: Grey
/// Material: 80% cotton, 20% polyester
///
/// #nike #sweatshirt #vintage #crewneck #90s
/// ```
///
/// Each line is left out when its value is missing, and so is each block, with
/// no gaps where they were. "(see photos)" is added to the flaws only when a
/// photograph of a flaw is on the listing: a description that sends a buyer to
/// the photographs for something that is not in them is a description that
/// ends in a dispute.
///
/// Hashtags the person typed into their notes count towards Depop's five, so
/// the generated ones fill only what is left, and repeat none of them.
String composeDescription(Listing listing) {
  for (final plan in _plans) {
    final text = _compose(listing, plan);
    if (text.length <= depopDescriptionLimit) return text;
  }
  return _cut(_compose(listing, _plans.last), depopDescriptionLimit);
}

/// What is kept at each stage of shortening a description.
final class _Plan {
  const _Plan({
    this.notes = true,
    this.allFlaws = true,
    this.styleHashtags = true,
    this.hashtags = true,
  });

  final bool notes;
  final bool allFlaws;
  final bool styleHashtags;
  final bool hashtags;
}

/// From everything to the least that is still a description.
const List<_Plan> _plans = [
  _Plan(),
  _Plan(notes: false),
  _Plan(notes: false, allFlaws: false),
  _Plan(notes: false, allFlaws: false, styleHashtags: false),
  _Plan(
    notes: false,
    allFlaws: false,
    styleHashtags: false,
    hashtags: false,
  ),
];

String _compose(Listing listing, _Plan plan) {
  final blocks = <String>[];

  final title = listing.title.trim();
  if (title.isNotEmpty) blocks.add(title);

  final details = _detailLines(listing, allFlaws: plan.allFlaws);
  if (details.isNotEmpty) blocks.add(details.join('\n'));

  if (plan.notes) {
    final notes = listing.notes?.trim();
    if (notes != null && notes.isNotEmpty) blocks.add(notes);
  }

  if (plan.hashtags) {
    // Tags already written into the text use up some of the five, and the
    // generated ones must not repeat them.
    final written = blocks.join('\n\n');
    final taken = _hashtagPattern.allMatches(written).toList();
    final room = depopHashtagLimit - taken.length;
    final tags = room <= 0
        ? <String>[]
        : _hashtags(
            listing,
            styleWords: plan.styleHashtags,
            limit: room,
            alreadyUsed: {
              for (final m in taken) m[0]!.substring(1).toLowerCase(),
            },
          );
    if (tags.isNotEmpty) blocks.add(tags.join(' '));
  }

  return blocks.join('\n\n');
}

List<String> _detailLines(Listing listing, {required bool allFlaws}) {
  final brand = listing.brand?.trim();
  final size = listing.sizeLabel?.trim();
  final material = listing.material?.trim();
  final measurements = [
    for (final m in listing.measurements.given)
      '${m.label} ${formatInches(m.inches)}"',
  ];
  final colours = [for (final c in listing.colours) c.label];
  final condition = _conditionLine(listing, allFlaws: allFlaws);

  return [
    if (brand != null && brand.isNotEmpty) 'Brand: $brand',
    if (size != null && size.isNotEmpty) 'Size: $size',
    if (measurements.isNotEmpty) 'Measurements: ${measurements.join(', ')}',
    if (condition != null) condition,
    if (colours.isNotEmpty) 'Color: ${colours.join(', ')}',
    if (material != null && material.isNotEmpty) 'Material: $material',
  ];
}

/// The condition and the flaws, on one line.
///
/// `Condition: Used - Excellent.` alone when no flaws are listed — and never
/// anything that sounds like "no flaws". `Flaws: …` alone when there is no
/// condition yet, because leaving a flaw out of the text until somebody has
/// picked a grade would be exactly the omission this line exists to prevent.
String? _conditionLine(Listing listing, {required bool allFlaws}) {
  final condition = listing.condition;
  final flaws = [
    for (final flaw in listing.flaws)
      if (_withoutFullStop(flaw) case final String text) text,
  ];

  final parts = <String>[
    if (condition != null) '${condition.label}.',
    if (flaws.isNotEmpty) _flawsSentence(listing, flaws, allFlaws: allFlaws),
  ];
  if (parts.isEmpty) return null;

  return condition == null ? parts.join(' ') : 'Condition: ${parts.join(' ')}';
}

String _flawsSentence(
  Listing listing,
  List<String> flaws, {
  required bool allFlaws,
}) {
  final shown = allFlaws || flaws.length == 1 ? flaws : [flaws.first];
  final more = shown.length < flaws.length ? ', and others' : '';
  final pictured = listing.photos.any((p) => p.shot == ListingShot.flaw);

  return 'Flaws: ${shown.join('; ')}$more${pictured ? ' (see photos)' : ''}.';
}

/// A flaw without the full stop it might have been typed with, so that the
/// sentence around it does not end `..`; null when nothing is left.
String? _withoutFullStop(String flaw) {
  final text = flaw.trim().replaceFirst(RegExp(r'\.+$'), '').trimRight();
  return text.isEmpty ? null : text;
}

/// A measurement without trailing zeros: `21`, `27.5`, `27.25`.
///
/// How the description writes one, and so how the editor's box should show it.
String formatInches(double inches) {
  final text = inches.toStringAsFixed(2);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// [text] cut to [limit] characters, ending in an ellipsis.
///
/// Not through the middle of a character that is two code units long: half of
/// an emoji is not text, and the app's text field would show a box.
String _cut(String text, int limit) {
  if (text.length <= limit) return text;

  var end = limit - 1;
  final last = text.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) end--;

  return '${text.substring(0, end).trimRight()}…';
}
