/// What a garment already in the wardrobe can honestly say to a buyer.
///
/// Internal to `selling/`, and deliberately not exported: these are the few
/// places where "what the wardrobe knows" has to be turned into something a
/// listing or a request can carry, and more than one file needs the same
/// answer. A copy in each would eventually disagree about, say, whether a
/// guessed fabric is worth printing in front of a buyer.
library;

import '../shared/confidence.dart';
import '../wardrobe/model/item_attributes.dart';
import '../wardrobe/model/wardrobe_item.dart';
import 'depop.dart';

/// How many times something was worn, as a phrase: `once`, `12 times`.
///
/// Zero is not handled here — "worn 0 times" is not a thing anyone says, and
/// what to say about a garment never worn depends on who is being told.
String timesWornPhrase(int times) => times == 1 ? 'once' : '$times times';

/// The garment's composition as a label would print it, when a label or the
/// person stated it; otherwise null.
///
/// A fabric guessed from a photograph is not something to sell a garment on.
/// The scan contract says as much of a listing's material — "absent unless a
/// label was photographed" — and the same holds here: a composition that is
/// only a model's reading of the picture would put "100% cotton" in front of a
/// buyer on no better evidence than the look of the cloth, and a listing that
/// is wrong about its fabric is the kind that comes back.
///
/// A label read by a scan counts, and so does anything the person typed. An
/// unknown composition is nothing, not "Unknown composition".
String? statedMaterial(WardrobeItem item) {
  final composition = item.composition;
  if (composition.value.isEmpty) return null;

  final stated = composition.source == Provenance.tagScan ||
      composition.source == Provenance.userEdited;
  return stated ? composition.value.label : null;
}

/// The names of the garment's colours, dominant first, leaving out any that
/// are not names.
///
/// The item editor names a typed hex colour after itself (`#1F2A44`), and a
/// hex code is a perfectly good colour for a swatch and no use at all to a
/// buyer or a search box.
List<String> colourNamesOf(WardrobeItem item) => [
      for (final colour in item.colors.value.colors)
        if (colour.name?.trim() case final String name
            when name.isNotEmpty && !name.startsWith('#'))
          name,
    ];

/// The Depop department the garment's cut points to, or null when it does not.
///
/// A men's or women's cut says which side of the shop it is found on.
/// Unisex and children's clothes could go either way or elsewhere, so they are
/// left for the person to choose rather than assumed.
DepopDepartment? departmentOf(WardrobeItem item) => switch (item.styleCut) {
      StyleCut.mens => DepopDepartment.men,
      StyleCut.womens => DepopDepartment.women,
      StyleCut.unisex || StyleCut.kids || null => null,
    };
