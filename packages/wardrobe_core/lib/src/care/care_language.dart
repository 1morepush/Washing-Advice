/// Renders care instructions as plain English.
///
/// The point of the product: a user should never have to decode a triangle. A
/// crossed-out triangle becomes "Do not bleach"; a square with a circle and one
/// dot becomes "Tumble dry on low heat".
///
/// Returning structured [CareSentence] values rather than one blob of text lets
/// the UI lay each instruction out with its own icon, and keeps this class free
/// of presentation concerns.
library;

import 'model/care_instructions.dart';
import 'model/care_symbols.dart';

/// Which of the five symbol groups an instruction belongs to.
enum CareTopic {
  washing('Washing'),
  bleaching('Bleaching'),
  drying('Drying'),
  ironing('Ironing'),
  professional('Professional cleaning'),
  handling('Handling');

  const CareTopic(this.label);

  final String label;
}

/// One rendered instruction.
final class CareSentence {
  const CareSentence({
    required this.topic,
    required this.text,
    this.isProhibition = false,
  });

  final CareTopic topic;

  /// The instruction, e.g. `'Machine wash cold on a delicate cycle'`.
  final String text;

  /// Whether this forbids something, so the UI can mark it clearly.
  final bool isProhibition;

  @override
  String toString() => text;
}

/// Turns [CareInstructions] into readable sentences.
final class CareLanguage {
  const CareLanguage({this.temperatureUnit = TemperatureUnit.celsius});

  final TemperatureUnit temperatureUnit;

  /// Every instruction for an item, in the order a person would do them.
  List<CareSentence> describe(CareInstructions care) => [
        _washing(care.wash),
        _bleaching(care.bleach),
        ..._drying(care.dry),
        _ironing(care.iron),
        ..._professional(care.professional),
        ..._handling(care.warnings),
      ];

  /// A single-line summary for a list row, e.g.
  /// `'Machine wash cold · Tumble dry low · Do not bleach'`.
  String summarise(CareInstructions care) => [
        _washing(care.wash).text,
        ..._drying(care.dry).take(1).map((s) => s.text),
        if (care.bleach == BleachAllowance.none) 'Do not bleach',
      ].join(' · ');

  CareSentence _washing(WashCare wash) {
    if (wash.method == WashMethod.doNotWash) {
      return const CareSentence(
        topic: CareTopic.washing,
        text: 'Do not wash',
        isProhibition: true,
      );
    }

    final verb = wash.method == WashMethod.hand ? 'Hand wash' : 'Machine wash';
    final parts = <String>[verb];

    if (wash.maxTempC case final int temp) {
      parts.add(_temperatureWords(temp));
    }

    // A hand wash is gentle by definition; naming a cycle would be nonsense.
    if (wash.method == WashMethod.machine &&
        wash.agitation != Agitation.normal) {
      parts.add('on a ${wash.agitation.label.toLowerCase()} cycle');
    }

    return CareSentence(topic: CareTopic.washing, text: parts.join(' '));
  }

  /// Renders a temperature the way a person reads a dial, not a thermometer.
  String _temperatureWords(int celsius) {
    final descriptor = switch (celsius) {
      <= 30 => 'cold',
      <= 40 => 'warm',
      <= 60 => 'hot',
      _ => 'very hot',
    };
    final measured = switch (temperatureUnit) {
      TemperatureUnit.celsius => '$celsius°C',
      TemperatureUnit.fahrenheit => '${(celsius * 9 / 5 + 32).round()}°F',
    };
    return '$descriptor (max $measured)';
  }

  CareSentence _bleaching(BleachAllowance bleach) => switch (bleach) {
        BleachAllowance.none => const CareSentence(
            topic: CareTopic.bleaching,
            text: 'Do not bleach',
            isProhibition: true,
          ),
        BleachAllowance.nonChlorineOnly => const CareSentence(
            topic: CareTopic.bleaching,
            text: 'Only non-chlorine bleach, if needed',
          ),
        BleachAllowance.any => const CareSentence(
            topic: CareTopic.bleaching,
            text: 'Any bleach may be used',
          ),
      };

  List<CareSentence> _drying(DryCare dry) {
    final sentences = <CareSentence>[];

    if (dry.tumbleDryAllowed) {
      final heat = switch (dry.tumbleDryHeat) {
        TumbleDryHeat.noHeat => 'with no heat',
        TumbleDryHeat.low => 'on low heat',
        TumbleDryHeat.medium => 'on medium heat',
        TumbleDryHeat.high => 'on high heat',
      };
      sentences.add(
        CareSentence(topic: CareTopic.drying, text: 'Tumble dry $heat'),
      );
    } else {
      sentences.add(
        const CareSentence(
          topic: CareTopic.drying,
          text: 'Do not tumble dry',
          isProhibition: true,
        ),
      );
    }

    if (dry.naturalDry case final NaturalDryMethod method) {
      final text = switch (method) {
        NaturalDryMethod.lineDry => 'Hang to dry',
        NaturalDryMethod.dripDry => 'Hang to dry without spinning',
        NaturalDryMethod.flatDry => 'Dry flat to keep its shape',
      };
      sentences.add(
        CareSentence(
          topic: CareTopic.drying,
          text: dry.dryInShade ? '$text, out of direct sunlight' : text,
        ),
      );
    } else if (dry.dryInShade) {
      sentences.add(
        const CareSentence(
          topic: CareTopic.drying,
          text: 'Dry out of direct sunlight',
        ),
      );
    }

    if (dry.doNotWring) {
      sentences.add(
        const CareSentence(
          topic: CareTopic.drying,
          text: 'Do not wring — press the water out instead',
          isProhibition: true,
        ),
      );
    }

    return sentences;
  }

  CareSentence _ironing(IronCare iron) {
    if (iron.temperature == IronTemperature.none) {
      return const CareSentence(
        topic: CareTopic.ironing,
        text: 'Do not iron',
        isProhibition: true,
      );
    }

    final setting = switch (iron.temperature) {
      IronTemperature.low => 'on a low setting',
      IronTemperature.medium => 'on a medium setting',
      IronTemperature.high => 'on a high setting',
      IronTemperature.none => '',
    };
    final maxTemp = iron.temperature.maxPlateC;
    final measured = maxTemp == null
        ? ''
        : switch (temperatureUnit) {
            TemperatureUnit.celsius => ' (max $maxTemp°C)',
            TemperatureUnit.fahrenheit =>
              ' (max ${(maxTemp * 9 / 5 + 32).round()}°F)',
          };
    final steam = iron.steamAllowed ? '' : ', without steam';

    return CareSentence(
      topic: CareTopic.ironing,
      text: 'Iron $setting$measured$steam',
    );
  }

  List<CareSentence> _professional(ProfessionalCare care) {
    if (care.doNotDryClean) {
      return const [
        CareSentence(
          topic: CareTopic.professional,
          text: 'Do not dry clean',
          isProhibition: true,
        ),
      ];
    }
    if (care.solvent case final CleaningSolvent solvent) {
      final description = switch (solvent) {
        CleaningSolvent.perchloroethylene =>
          'Professional dry clean (standard solvents)',
        CleaningSolvent.hydrocarbon =>
          'Professional dry clean (hydrocarbon solvent only)',
        CleaningSolvent.wetClean => 'Professional wet clean',
      };
      return [
        CareSentence(
          topic: CareTopic.professional,
          text: care.gentleCycle ? '$description, gentle cycle' : description,
        ),
      ];
    }
    return const [];
  }

  List<CareSentence> _handling(Set<CareWarning> warnings) => [
        for (final warning in warnings)
          CareSentence(
            topic: CareTopic.handling,
            text: warning.label,
            isProhibition: warning == CareWarning.doNotSoak ||
                warning == CareWarning.doNotUseSoftener,
          ),
      ];
}

/// Which unit to show temperatures in.
enum TemperatureUnit { celsius, fahrenheit }
