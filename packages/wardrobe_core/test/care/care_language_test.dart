import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../support/fixtures.dart';

void main() {
  const language = CareLanguage();

  String washingOf(CareInstructions care) => language
      .describe(care)
      .firstWhere((s) => s.topic == CareTopic.washing)
      .text;

  List<String> textsOf(CareInstructions care, CareTopic topic) => [
        for (final sentence in language.describe(care))
          if (sentence.topic == topic) sentence.text,
      ];

  group('washing', () {
    test('renders a cold gentle machine wash', () {
      expect(
        washingOf(delicateCare),
        'Machine wash cold (max 30°C) on a delicate cycle',
      );
    });

    test('renders an ordinary warm wash without naming a cycle', () {
      // A normal cycle is the default, so saying "on a normal cycle" is noise.
      expect(washingOf(cottonCare), 'Machine wash warm (max 40°C)');
    });

    test('renders a hand wash without naming a machine cycle', () {
      // "Hand wash on a delicate cycle" would be nonsense.
      expect(washingOf(handWashCare), 'Hand wash cold (max 30°C)');
    });

    test('renders a prohibition plainly', () {
      const care = CareInstructions(
        wash: WashCare(method: WashMethod.doNotWash),
        bleach: BleachAllowance.none,
        dry: DryCare(tumbleDryAllowed: false),
        iron: IronCare(temperature: IronTemperature.none),
        professional: ProfessionalCare(solvent: CleaningSolvent.hydrocarbon),
      );
      expect(washingOf(care), 'Do not wash');
      final sentence = language
          .describe(care)
          .firstWhere((s) => s.topic == CareTopic.washing);
      expect(sentence.isProhibition, isTrue);
    });

    test('describes hot temperatures in words a person uses', () {
      expect(washingOf(heavyCare), contains('hot'));
      expect(washingOf(heavyCare), contains('60°C'));
    });

    test('converts to Fahrenheit when asked', () {
      const american =
          CareLanguage(temperatureUnit: TemperatureUnit.fahrenheit);
      final text = american
          .describe(cottonCare)
          .firstWhere((s) => s.topic == CareTopic.washing)
          .text;
      expect(text, contains('104°F'));
      expect(text, isNot(contains('°C')));
    });
  });

  group('the symbols users cannot read', () {
    test('a crossed triangle becomes "Do not bleach"', () {
      expect(
        textsOf(delicateCare, CareTopic.bleaching),
        contains('Do not bleach'),
      );
    });

    test('a triangle with lines becomes a plain sentence', () {
      expect(
        textsOf(cottonCare, CareTopic.bleaching),
        contains('Only non-chlorine bleach, if needed'),
      );
    });

    test('a crossed square-in-circle becomes "Do not tumble dry"', () {
      expect(
        textsOf(delicateCare, CareTopic.drying),
        contains('Do not tumble dry'),
      );
    });

    test('a one-dot dryer symbol becomes "Tumble dry on low heat"', () {
      const care = CareInstructions(
        wash: WashCare(method: WashMethod.machine, maxTempC: 40),
        bleach: BleachAllowance.none,
        dry: DryCare(tumbleDryAllowed: true, tumbleDryHeat: TumbleDryHeat.low),
        iron: IronCare(temperature: IronTemperature.medium),
        professional: ProfessionalCare.unspecified(),
      );
      expect(
        textsOf(care, CareTopic.drying),
        contains('Tumble dry on low heat'),
      );
    });

    test('a flat-dry symbol explains why, not just what', () {
      expect(
        textsOf(delicateCare, CareTopic.drying),
        contains('Dry flat to keep its shape'),
      );
    });

    test('a crossed iron becomes "Do not iron"', () {
      const care = CareInstructions(
        wash: WashCare(method: WashMethod.machine),
        bleach: BleachAllowance.none,
        dry: DryCare(tumbleDryAllowed: false),
        iron: IronCare(temperature: IronTemperature.none),
        professional: ProfessionalCare.unspecified(),
      );
      expect(textsOf(care, CareTopic.ironing), contains('Do not iron'));
    });

    test('a one-dot iron gives both the setting and the temperature', () {
      final text = textsOf(delicateCare, CareTopic.ironing).single;
      expect(text, contains('low setting'));
      expect(text, contains('110°C'));
      expect(text, contains('without steam'));
    });

    test('a circled P becomes an instruction about dry cleaning', () {
      const care = CareInstructions(
        wash: WashCare(method: WashMethod.doNotWash),
        bleach: BleachAllowance.none,
        dry: DryCare(tumbleDryAllowed: false),
        iron: IronCare(temperature: IronTemperature.none),
        professional: ProfessionalCare(
          solvent: CleaningSolvent.perchloroethylene,
          gentleCycle: true,
        ),
      );
      expect(
        textsOf(care, CareTopic.professional).single,
        'Professional dry clean (standard solvents), gentle cycle',
      );
    });

    test('do-not-wring explains what to do instead', () {
      expect(
        textsOf(handWashCare, CareTopic.drying),
        contains('Do not wring — press the water out instead'),
      );
    });
  });

  group('summary line', () {
    test('is short enough for a list row', () {
      final summary = language.summarise(delicateCare);
      expect(
          summary,
          'Machine wash cold (max 30°C) on a delicate cycle · '
          'Do not tumble dry · Do not bleach');
      expect(summary.split('·'), hasLength(3));
    });
  });

  test('no sentence is ever left empty', () {
    for (final care in [cottonCare, heavyCare, delicateCare, handWashCare]) {
      for (final sentence in language.describe(care)) {
        expect(sentence.text.trim(), isNotEmpty);
      }
    }
  });

  test('handling warnings are rendered verbatim', () {
    final care = cottonCare.withWarnings([
      CareWarning.washInsideOut,
      CareWarning.doNotUseSoftener,
    ]);
    final handling = textsOf(care, CareTopic.handling);
    expect(handling,
        containsAll(['Wash inside out', 'Do not use fabric softener']));
  });
}
