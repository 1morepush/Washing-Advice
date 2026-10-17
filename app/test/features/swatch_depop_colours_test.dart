/// Every colour the item editor offers is one a listing can say.
///
/// A garment's colours come from its photographs or from the swatches in the
/// item editor, and a listing built from it turns them into Depop's short list
/// with `depopColoursFor` in the core. The core pins the swatch names it
/// expects by hand, because the editor's list is private to the app and it
/// cannot read it. That is half of an agreement. This is the other half: it
/// reads the editor's own list, so a swatch added there that the core does not
/// know fails here, instead of quietly leaving the colour off every listing of
/// a garment that is that colour.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/features/wardrobe/edit_item_fields.dart'
    show swatchNames;

void main() {
  test('there are swatches to hold, so the rest is not vacuous', () {
    expect(swatchNames, isNotEmpty);
    expect(swatchNames.toSet(), hasLength(swatchNames.length));
  });

  for (final name in swatchNames) {
    test('$name is a colour Depop has', () {
      expect(
        depopColoursFor([name]),
        isNotEmpty,
        reason:
            '"$name" is offered by the item editor but has no Depop colour, '
            'so a listing of a garment of that colour would leave it out. Add '
            'it to the colour table in wardrobe_core/lib/src/selling/depop.dart.',
      );
    });
  }
}
