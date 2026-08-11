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
}
