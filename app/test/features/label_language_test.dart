/// Naming the language a care label was printed in.
///
/// Worth its own tests for the negative cases rather than the positive ones.
/// The instructions never depend on this — they come from the ISO 3758
/// symbols, which are identical in every country — so the only thing that can
/// go wrong here is the screen saying something silly about a label it read
/// perfectly well.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/features/wardrobe/care_text.dart';

void main() {
  test('a foreign language is named', () {
    expect(foreignLanguageName('fr'), 'French');
    expect(foreignLanguageName('ja'), 'Japanese');
  });

  test('English is not worth mentioning', () {
    // "This label is in English" reads as though the app were unsure of
    // something obvious.
    expect(foreignLanguageName('en'), isNull);
  });

  test('a symbols-only label has nothing to mention either', () {
    // Entirely ordinary: the symbols carry the instructions, and plenty of
    // labels print no words at all.
    expect(foreignLanguageName(null), isNull);
  });

  test('a code with no name here is silent rather than raw', () {
    // Better nothing than "This label is in mt". The reading is unaffected.
    expect(foreignLanguageName('mt'), isNull);
  });

  test('case does not matter', () {
    // Models answer "en", "EN" and "En" to the same question, and the server
    // lower-cases — but this must not depend on that having happened.
    expect(foreignLanguageName('FR'), 'French');
  });
}
