/// The demo wardrobe, as the screenshots see it.
///
/// Most of its tops and bottoms are staged into the laundry piles so that those
/// screens have something to show, and a garment in the wash is not offered
/// for an outfit. With every bottom in the wash the Outfits screen showed its
/// empty state in the screenshots. This keeps a clean top and bottom in the
/// wardrobe so that it shows an outfit.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/main_demo.dart';

void main() {
  test('the demo wardrobe can put together an outfit', () {
    final clean = [
      for (final item in demoWardrobe())
        if (item.lifecycle == LifecycleState.active) item,
    ];

    final suggestions = const OutfitBuilder().suggest(
      clean,
      const OutfitRequest(),
    );

    expect(suggestions, isNotEmpty);
    final categories = {
      for (final item in suggestions.first.items) item.type.value.category,
    };
    expect(categories, contains(ItemCategory.bottom));
  });
}
