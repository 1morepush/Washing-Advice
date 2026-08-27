/// What the app calls a fibre.
///
/// Reported from a real scan: a label clearly printed SPANDEX and the app
/// showed "Elastane". The reading was correct — the server maps spandex onto
/// the elastane enum, and its care rules depend on that mapping — but the word
/// on screen was not the word on the tag, which reads as a misread.
///
/// The app writes American English throughout (0.5.0), and an American label
/// prints RAYON and SPANDEX. So the display names were inconsistent with the
/// app's own convention as well as with the tag in the user's hand.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  group('what a fibre is called', () {
    test('the American name is the one shown, per the app convention', () {
      expect(Fiber.elastane.label, 'Spandex');
      expect(Fiber.viscose.label, 'Rayon');
      // Already American: the European name is polyamide.
      expect(Fiber.nylon.label, 'Nylon');
    });

    test('the stored identifier is unchanged, so nothing has to migrate', () {
      // The enum *name* is what goes into storage and onto the wire. Renaming
      // that to match the display would be a data migration and a wire break
      // for a change that is entirely about wording.
      expect(Fiber.elastane.name, 'elastane');
      expect(Fiber.viscose.name, 'viscose');
    });

    test('the other names are kept, because labels use them', () {
      // A European tag says ELASTANE and a brand one says LYCRA. Neither is
      // wrong, and somebody comparing the app against a tag needs to know
      // they are looking at the same fibre.
      expect(Fiber.elastane.alsoKnownAs, containsAll(['Elastane', 'Lycra']));
      expect(Fiber.viscose.alsoKnownAs, contains('Viscose'));
      expect(Fiber.nylon.alsoKnownAs, contains('Polyamide'));
      expect(Fiber.lyocell.alsoKnownAs, contains('Tencel'));
    });

    test('a fibre that goes by one name claims no others', () {
      // The note only earns its place where there is a mismatch to explain.
      expect(Fiber.cotton.alsoKnownAs, isEmpty);
      expect(Fiber.wool.alsoKnownAs, isEmpty);
    });

    test('no other name collides with a real fibre name', () {
      // "Lycra is also cotton" would be worse than saying nothing at all.
      final labels = {
        for (final fiber in Fiber.values) fiber.label.toLowerCase()
      };
      for (final fiber in Fiber.values) {
        for (final alias in fiber.alsoKnownAs) {
          expect(
            labels,
            isNot(contains(alias.toLowerCase())),
            reason: '${alias} is both an alias and a fibre name',
          );
        }
      }
    });

    test('a composition reads back in the words the app uses', () {
      final blend = FabricComposition(const {
        Fiber.cotton: 95,
        Fiber.elastane: 5,
      });

      expect(blend.label, '95% Cotton, 5% Spandex');
    });
  });
}
