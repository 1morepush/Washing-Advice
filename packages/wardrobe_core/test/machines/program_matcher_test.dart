import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  const matcher = ProgramMatcher();
  final lg = seededWashers['LG']!;
  final speedQueen = seededWashers['Speed Queen']!;
  final lgDryer = seededDryers['LG']!;
  final speedQueenDryer = seededDryers['Speed Queen']!;

  const coldDelicate = WashSpec(
    method: WashMethod.machine,
    agitation: Agitation.veryMild,
    fabricClass: FabricClass.delicate,
    maxTempC: 30,
    maxSpinRpm: 800,
    needsExtraRinse: true,
  );

  const ordinaryWarm = WashSpec(
    method: WashMethod.machine,
    agitation: Agitation.normal,
    fabricClass: FabricClass.normal,
    maxTempC: 40,
  );

  const handWashOnly = WashSpec(
    method: WashMethod.hand,
    agitation: Agitation.veryMild,
    fabricClass: FabricClass.delicate,
    maxTempC: 30,
    maxSpinRpm: 600,
  );

  group('washing', () {
    test('picks a delicate programme for a delicate load', () {
      final setting = matcher.matchWash(coldDelicate, lg);
      expect(setting.programName, 'Delicates');
      expect(setting.temperatureC, lessThanOrEqualTo(30));
    });

    test('never selects a temperature above what the load allows', () {
      for (final washer in seededWashers.values) {
        final setting = matcher.matchWash(coldDelicate, washer);
        if (!setting.hasWarnings) {
          expect(
            setting.temperatureC,
            lessThanOrEqualTo(30),
            reason: washer.displayName,
          );
        }
      }
    });

    test('never selects a spin faster than the load allows', () {
      for (final washer in seededWashers.values) {
        final setting = matcher.matchWash(coldDelicate, washer);
        expect(
          setting.spinRpm,
          lessThanOrEqualTo(800),
          reason: washer.displayName,
        );
      }
    });

    test('never picks a harsher cycle than a delicate load can take', () {
      for (final washer in seededWashers.values) {
        final setting = matcher.matchWash(coldDelicate, washer);
        final program = washer.programs
            .firstWhere((p) => p.displayName == setting.programName);
        expect(
          program.agitation,
          Agitation.veryMild,
          reason: '${washer.displayName} chose ${program.displayName}',
        );
      }
    });

    test('picks an everyday programme for an ordinary load', () {
      final setting = matcher.matchWash(ordinaryWarm, lg);
      expect(setting.programName, anyOf('Cotton', 'Mixed Fabric'));
      expect(setting.isCompromise, isFalse);
    });

    test('turns extra rinse on for delicates when the machine has it', () {
      final setting = matcher.matchWash(coldDelicate, lg);
      expect(setting.options[WasherOption.extraRinse.label], isTrue);
    });

    test('WashSpec.from asks for an extra rinse on delicate loads', () {
      // Delicates hold detergent, and the residue is what leaves fine fabrics
      // feeling stiff — so the requirement is derived, not hand-set.
      const care = CareInstructions(
        wash: WashCare(
          method: WashMethod.machine,
          maxTempC: 30,
          agitation: Agitation.veryMild,
        ),
        bleach: BleachAllowance.none,
        dry: DryCare(tumbleDryAllowed: false),
        iron: IronCare(temperature: IronTemperature.low),
        professional: ProfessionalCare.unspecified(),
      );
      expect(
        WashSpec.from(care, FabricClass.delicate).needsExtraRinse,
        isTrue,
      );
      expect(
        WashSpec.from(care, FabricClass.normal).needsExtraRinse,
        isFalse,
      );
    });

    test('a fabric that weakens when wet gets a slower spin', () {
      const care = CareInstructions(
        wash: WashCare(method: WashMethod.machine, maxTempC: 30),
        bleach: BleachAllowance.none,
        dry: DryCare(tumbleDryAllowed: false, doNotWring: true),
        iron: IronCare(temperature: IronTemperature.low),
        professional: ProfessionalCare.unspecified(),
      );
      final spec = WashSpec.from(care, FabricClass.delicate);
      expect(spec.maxSpinRpm, 600);
      expect(matcher.matchWash(spec, lg).spinRpm, lessThanOrEqualTo(600));
    });

    test('refuses to wash an item the label forbids', () {
      const forbidden = WashSpec(
        method: WashMethod.doNotWash,
        agitation: Agitation.veryMild,
        fabricClass: FabricClass.delicate,
      );
      final setting = matcher.matchWash(forbidden, lg);
      expect(setting.hasWarnings, isTrue);
      expect(setting.programName, 'Do not wash');
    });

    test('warns about the reduced load size on a gentle cycle', () {
      final setting = matcher.matchWash(coldDelicate, lg);
      expect(
        setting.notes.map((n) => n.text).join(' '),
        contains('50%'),
      );
    });
  });

  group('hand wash on a machine without a hand-wash cycle', () {
    test('LG has a hand-wash cycle and uses it cleanly', () {
      final setting = matcher.matchWash(handWashOnly, lg);
      expect(setting.programName, 'Hand Wash/Wool');
    });

    test('Speed Queen has none, so it falls back and says so', () {
      // The most common real mismatch: a basic machine with three cycles.
      // The answer must be an honest "use Delicates, or wash it by hand",
      // never a silent substitution.
      final setting = matcher.matchWash(handWashOnly, speedQueen);
      expect(setting.programName, 'Delicate');
      expect(setting.isCompromise, isTrue);
      expect(
        setting.notes.map((n) => n.text).join(' '),
        contains('no dedicated hand-wash cycle'),
      );
    });

    test('the fallback still respects the spin limit', () {
      final setting = matcher.matchWash(handWashOnly, speedQueen);
      expect(setting.spinRpm, lessThanOrEqualTo(600));
    });
  });

  group('ranking is inspectable', () {
    test('reports why a programme was rejected', () {
      final ranked = matcher.rankPrograms(coldDelicate, lg);
      final heavy =
          ranked.firstWhere((c) => c.program.displayName == 'Heavy Duty');
      expect(heavy.disqualified, isTrue);
      expect(heavy.reasons, isNotEmpty);
    });

    test('the chosen programme is the highest-scoring viable one', () {
      final ranked = matcher.rankPrograms(ordinaryWarm, lg);
      final viable = ranked.where((c) => !c.disqualified).toList();
      final setting = matcher.matchWash(ordinaryWarm, lg);
      expect(setting.programName, viable.first.program.displayName);
    });
  });

  group('drying', () {
    test('recommends air drying when the load must not be tumbled', () {
      const spec = DrySpec(
        tumbleDryAllowed: false,
        maxHeat: TumbleDryHeat.noHeat,
        fabricClass: FabricClass.delicate,
        naturalDry: NaturalDryMethod.flatDry,
      );
      final setting = matcher.matchDry(spec, lgDryer);
      expect(setting.isAirDry, isTrue);
      expect(
        setting.notes.map((n) => n.text).join(' '),
        contains('Dry flat'),
      );
    });

    test('never selects a heat above what the load allows', () {
      const spec = DrySpec(
        tumbleDryAllowed: true,
        maxHeat: TumbleDryHeat.low,
        fabricClass: FabricClass.normal,
      );
      for (final dryer in seededDryers.values) {
        final setting = matcher.matchDry(spec, dryer);
        if (!setting.isAirDry) {
          expect(
            setting.heat.index,
            lessThanOrEqualTo(TumbleDryHeat.low.index),
            reason: dryer.displayName,
          );
        }
      }
    });

    test('falls back to air drying when no setting is cool enough', () {
      // Speed Queen's Regular programme is medium/high only, and its Delicate
      // is low — so a no-heat requirement has to fall through to Air Fluff.
      const noHeat = DrySpec(
        tumbleDryAllowed: true,
        maxHeat: TumbleDryHeat.noHeat,
        fabricClass: FabricClass.delicate,
      );
      final setting = matcher.matchDry(noHeat, speedQueenDryer);
      expect(setting.heat, TumbleDryHeat.noHeat);
      expect(setting.programName, 'Air Fluff');
    });

    test('prefers sensor drying over a timer when both would do', () {
      const spec = DrySpec(
        tumbleDryAllowed: true,
        maxHeat: TumbleDryHeat.medium,
        fabricClass: FabricClass.normal,
      );
      final setting = matcher.matchDry(spec, lgDryer);
      expect(setting.usesSensor, isTrue);
    });

    test('warns when a timed programme is the only option', () {
      const spec = DrySpec(
        tumbleDryAllowed: true,
        maxHeat: TumbleDryHeat.high,
        fabricClass: FabricClass.heavy,
      );
      final setting = matcher.matchDry(spec, speedQueenDryer);
      expect(setting.usesSensor, isFalse);
      expect(
        setting.notes.map((n) => n.text).join(' '),
        contains('timed'),
      );
    });
  });

  group('seeded catalogue', () {
    test('every brand has both a washer and a dryer', () {
      expect(seededWashers.keys.toSet(), seededDryers.keys.toSet());
    });

    test('no seeded profile claims to be a verified model', () {
      // These are brand archetypes. Claiming otherwise would mislead users
      // into trusting a cycle list their machine may not have.
      for (final washer in seededWashers.values) {
        expect(washer.isVerifiedModel, isFalse, reason: washer.displayName);
      }
      for (final dryer in seededDryers.values) {
        expect(dryer.isVerifiedModel, isFalse, reason: dryer.displayName);
      }
    });

    test('every washer can wash something cold and gently', () {
      for (final washer in seededWashers.values) {
        expect(washer.hasColdWash, isTrue, reason: washer.displayName);
        expect(
          washer.washCycles.any((p) => p.agitation == Agitation.veryMild),
          isTrue,
          reason: '${washer.displayName} has no gentle cycle at all',
        );
      }
    });

    test('programme ids are unique within each machine', () {
      for (final washer in seededWashers.values) {
        final ids = washer.programs.map((p) => p.id).toList();
        expect(ids.toSet().length, ids.length, reason: washer.displayName);
      }
    });

    test('every programme offers a temperature it can default to', () {
      for (final washer in seededWashers.values) {
        for (final program in washer.programs) {
          expect(
            program.availableTempsC,
            contains(program.defaultTempC),
            reason: '${washer.displayName} / ${program.displayName}',
          );
        }
      }
    });

    test('every dry programme offers the heat it defaults to', () {
      for (final dryer in seededDryers.values) {
        for (final program in dryer.programs) {
          expect(
            program.availableHeats,
            contains(program.defaultHeat),
            reason: '${dryer.displayName} / ${program.displayName}',
          );
        }
      }
    });
  });
}
