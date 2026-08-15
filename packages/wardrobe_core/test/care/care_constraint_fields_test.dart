/// That every field a [CareConstraint] can state survives the whole journey.
///
/// A constraint field has to be declared in five places — the field list,
/// `statedFields`, `toJson`, `fromJson`, and `CareResolver._valueOf` — and
/// nothing makes an omission fail. The `_valueOf` one is the dangerous one: an
/// unlisted path returns null for *both* the before and after instructions, so
/// the field compares equal, looks unchanged, and never appears in
/// `fieldsOverriddenByLabel`. The label is applied correctly and the app just
/// never mentions it.
///
/// That is not hypothetical. `solvent` was read by the server, carried by the
/// JSON contract, and absent from the Dart constraint entirely — decoded into
/// nothing on arrival for as long as the field had existed.
///
/// So this file states every field once, and asserts the journey rather than
/// the wiring. Add a field to `CareConstraint` and this fails until it is
/// wired everywhere.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  /// Every field stated at once.
  ///
  /// Deliberately not a realistic label — no manufacturer forbids dry cleaning
  /// and names a solvent in the same breath. It exists to exercise the
  /// plumbing, and every value differs from what the cotton t-shirt below
  /// resolves to without a label, so each one genuinely changes something and
  /// a field that fails to register is a wiring fault rather than a
  /// coincidence.
  const everything = CareConstraint(
    method: WashMethod.hand,
    maxTempC: 60,
    washTemperature: WashTemperature.hot,
    agitation: Agitation.normal,
    bleach: BleachAllowance.nonChlorineOnly,
    tumbleDryAllowed: true,
    tumbleDryHeat: TumbleDryHeat.medium,
    naturalDry: NaturalDryMethod.flatDry,
    dryInShade: true,
    doNotWring: true,
    ironTemperature: IronTemperature.high,
    steamAllowed: true,
    doNotDryClean: true,
    solvent: CleaningSolvent.hydrocarbon,
    warnings: {CareWarning.washInsideOut},
  );

  /// The paths above, spelled out rather than derived — a test that computed
  /// this from the same getter it checks would agree with any mistake.
  const expectedFields = {
    'wash.method',
    'wash.maxTempC',
    'wash.statedAs',
    'wash.agitation',
    'bleach',
    'dry.tumbleDryAllowed',
    'dry.tumbleDryHeat',
    'dry.naturalDry',
    'dry.dryInShade',
    'dry.doNotWring',
    'iron.temperature',
    'iron.steamAllowed',
    'professional.doNotDryClean',
    'professional.solvent',
  };

  test('every stated field is reported as stated', () {
    expect(everything.statedFields, expectedFields);
  });

  test('every stated field survives a JSON round trip', () {
    final returned = CareConstraint.fromJson(everything.toJson());

    expect(returned.statedFields, expectedFields);
    expect(returned.solvent, CleaningSolvent.hydrocarbon);
    expect(returned.warnings, everything.warnings);
  });

  test('every stated field is reported as overridden by the label', () {
    // The assertion that catches a missing `_valueOf` case. Each field is
    // stated with a value the conservative default does not hold, so all of
    // them genuinely changed — anything missing from the result was compared
    // as null-against-null.
    final resolution = const CareResolver().resolve(
      facts: ItemFacts(
        type: ItemType.tShirt,
        composition: FabricComposition(const {Fiber.cotton: 100}),
      ),
      fromLabel: everything,
    );

    expect(resolution.fieldsOverriddenByLabel, expectedFields);
  });

  test('a label states the solvent the fibre rules never could', () {
    // No rule infers which solvent a cleaner should use, so this value can
    // only ever arrive from a label. Before it was carried,
    // `ProfessionalCare.solvent` was permanently null.
    final resolution = const CareResolver().resolve(
      facts: ItemFacts(
        type: ItemType.sweater,
        composition: FabricComposition(const {Fiber.wool: 100}),
      ),
      fromLabel: const CareConstraint(solvent: CleaningSolvent.wetClean),
    );

    expect(
      resolution.instructions.professional.solvent,
      CleaningSolvent.wetClean,
    );
  });

  group('merging a later reading over an earlier one', () {
    test('every field survives a reading that states nothing', () {
      // `mergedWith` is a sixth place each field has to be declared, and an
      // omission there does not fail loudly: it silently drops evidence the
      // user had already scanned. Merging an empty reading over a full one
      // must give the full one back, field for field.
      const nothing = CareConstraint();

      expect(nothing.mergedWith(everything).statedFields, expectedFields);
      expect(nothing.mergedWith(everything).toJson(), everything.toJson());
    });

    test('and a reading that states everything keeps its own values', () {
      const nothing = CareConstraint();

      expect(everything.mergedWith(nothing).toJson(), everything.toJson());
    });

    test('a newly stated field wins over the earlier one', () {
      // A re-scan is as often a correction as an addition, and the newer
      // reading is the more recent direct evidence.
      const earlier = CareConstraint(maxTempC: 60, method: WashMethod.machine);
      const later = CareConstraint(maxTempC: 30);

      final merged = later.mergedWith(earlier);
      expect(merged.maxTempC, 30);
      // And the field the new reading was silent about is still there.
      expect(merged.method, WashMethod.machine);
    });

    test('warnings add up rather than replace', () {
      // The commonest two-sided label: symbols on one face, prose on the
      // other. A photograph of the symbol panel legitimately states no
      // warnings while the earlier shot of the text panel stated two.
      const earlier = CareConstraint(
        warnings: {CareWarning.washInsideOut, CareWarning.doNotUseSoftener},
      );
      const later = CareConstraint(
        maxTempC: 30,
        warnings: {CareWarning.washSeparately},
      );

      expect(later.mergedWith(earlier).warnings, {
        CareWarning.washInsideOut,
        CareWarning.doNotUseSoftener,
        CareWarning.washSeparately,
      });
    });

    test('what was kept rather than read is reportable', () {
      // The screen has to say so. A field carried over from a scan weeks ago,
      // presented as though this photograph had just read it, is the app
      // being quietly more certain than it is.
      const earlier = CareConstraint(
        maxTempC: 60,
        method: WashMethod.machine,
        bleach: BleachAllowance.none,
      );
      const later = CareConstraint(maxTempC: 30);

      expect(later.fieldsKeptFrom(earlier), {'wash.method', 'bleach'});
    });

    test('nothing is kept when the new reading restates it all', () {
      expect(everything.fieldsKeptFrom(everything), isEmpty);
    });
  });
}
