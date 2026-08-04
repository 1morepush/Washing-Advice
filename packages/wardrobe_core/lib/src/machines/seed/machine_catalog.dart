/// Seeded washer and dryer profiles for the major brands.
///
/// ## An honest caveat
///
/// These are **brand archetypes**, not model-exact specifications. Each is
/// built from the cycle line-up that brand commonly ships, and real machines
/// vary by model, year and region. The app must present them as a starting
/// point the user confirms and edits — `isVerifiedModel` is false on every one
/// of them, and the UI is expected to act on that.
///
/// Presenting a guessed cycle list as fact would be the single easiest way for
/// this product to lose a user's trust: they look at their machine, see no
/// "Delicates" dial, and stop believing anything the app says.
///
/// Held as const Dart data rather than JSON assets: it is compiler-checked,
/// needs no file I/O, and works identically on every platform.
library;

import '../../care/model/care_symbols.dart';
import '../../shared/ids.dart';
import '../../wardrobe/model/fabric.dart';
import '../model/dryer_profile.dart';
import '../model/washer_profile.dart';

/// All fabric classes — for programmes that genuinely handle anything.
const Set<FabricClass> _allFabrics = {
  FabricClass.delicate,
  FabricClass.normal,
  FabricClass.heavy,
};
const Set<FabricClass> _sturdy = {FabricClass.normal, FabricClass.heavy};
const Set<FabricClass> _gentle = {FabricClass.delicate};
const Set<FabricClass> _everyday = {FabricClass.normal};

/// Temperature ladders common to European and North American machines.
const List<int> _euTemps = [0, 20, 30, 40, 60, 90];
const List<int> _euTempsLimited = [0, 20, 30, 40];
const List<int> _usTemps = [0, 20, 30, 40, 60];

/// A cold-only cycle, for wool and hand-wash programmes.
const List<int> _coldTemps = [0, 20, 30];

const List<int> _fullSpin = [0, 400, 600, 800, 1000, 1200, 1400];
const List<int> _midSpin = [0, 400, 600, 800, 1000, 1200];
const List<int> _gentleSpin = [0, 400, 600, 800];
const List<int> _lowSpin = [0, 400, 600];

/// Every seeded washer, keyed by brand.
const Map<String, WasherProfile> seededWashers = {
  'LG': _lgWasher,
  'Samsung': _samsungWasher,
  'Whirlpool': _whirlpoolWasher,
  'GE': _geWasher,
  'Bosch': _boschWasher,
  'Speed Queen': _speedQueenWasher,
  'Maytag': _maytagWasher,
  'Electrolux': _electroluxWasher,
  'Generic': _genericWasher,
};

/// Every seeded dryer, keyed by brand.
const Map<String, DryerProfile> seededDryers = {
  'LG': _lgDryer,
  'Samsung': _samsungDryer,
  'Whirlpool': _whirlpoolDryer,
  'GE': _geDryer,
  'Bosch': _boschDryer,
  'Speed Queen': _speedQueenDryer,
  'Maytag': _maytagDryer,
  'Electrolux': _electroluxDryer,
  'Generic': _genericDryer,
};

/// Brands offered in the setup flow.
List<String> get seededBrands => seededWashers.keys.toList();

// --- Washers --------------------------------------------------------------

const _lgWasher = WasherProfile(
  id: WasherId('seed.lg.washer'),
  brand: 'LG',
  model: 'Front loader (typical)',
  capacityKg: 9.0,
  options: {
    WasherOption.extraRinse,
    WasherOption.prewash,
    WasherOption.steam,
    WasherOption.delayStart,
    WasherOption.stainRemoval,
    WasherOption.softenerDispenser,
  },
  programs: [
    WashProgram(
      id: 'lg.cotton',
      displayName: 'Cotton',
      kind: WashProgramKind.cotton,
      availableTempsC: _euTemps,
      defaultTempC: 40,
      agitation: Agitation.normal,
      spinSpeedsRpm: _fullSpin,
      suitableFor: _sturdy,
      typicalDuration: Duration(minutes: 135),
    ),
    WashProgram(
      id: 'lg.mixed',
      displayName: 'Mixed Fabric',
      kind: WashProgramKind.syntheticsMixed,
      availableTempsC: _euTempsLimited,
      defaultTempC: 40,
      agitation: Agitation.mild,
      spinSpeedsRpm: _midSpin,
      suitableFor: _everyday,
      typicalDuration: Duration(minutes: 100),
    ),
    WashProgram(
      id: 'lg.delicates',
      displayName: 'Delicates',
      kind: WashProgramKind.delicates,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.veryMild,
      spinSpeedsRpm: _gentleSpin,
      suitableFor: _gentle,
      maxLoadFraction: 0.5,
      typicalDuration: Duration(minutes: 60),
    ),
    WashProgram(
      id: 'lg.handwash',
      displayName: 'Hand Wash/Wool',
      kind: WashProgramKind.handWash,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.veryMild,
      spinSpeedsRpm: _lowSpin,
      suitableFor: _gentle,
      maxLoadFraction: 0.4,
      typicalDuration: Duration(minutes: 55),
    ),
    WashProgram(
      id: 'lg.speedwash',
      displayName: 'Speed Wash',
      kind: WashProgramKind.quick,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.normal,
      spinSpeedsRpm: _midSpin,
      suitableFor: _everyday,
      typicalDuration: Duration(minutes: 30),
    ),
    WashProgram(
      id: 'lg.heavyduty',
      displayName: 'Heavy Duty',
      kind: WashProgramKind.heavyDuty,
      availableTempsC: _euTemps,
      defaultTempC: 60,
      agitation: Agitation.normal,
      spinSpeedsRpm: _fullSpin,
      suitableFor: {FabricClass.heavy},
      typicalDuration: Duration(minutes: 150),
    ),
    WashProgram(
      id: 'lg.bedding',
      displayName: 'Bedding',
      kind: WashProgramKind.bedding,
      availableTempsC: _euTemps,
      defaultTempC: 40,
      agitation: Agitation.mild,
      spinSpeedsRpm: _midSpin,
      suitableFor: _sturdy,
      maxLoadFraction: 0.6,
      typicalDuration: Duration(minutes: 150),
    ),
  ],
);

const _samsungWasher = WasherProfile(
  id: WasherId('seed.samsung.washer'),
  brand: 'Samsung',
  model: 'Front loader (typical)',
  capacityKg: 9.0,
  options: {
    WasherOption.extraRinse,
    WasherOption.prewash,
    WasherOption.steam,
    WasherOption.delayStart,
    WasherOption.ecoMode,
    WasherOption.softenerDispenser,
  },
  programs: [
    WashProgram(
      id: 'samsung.cotton',
      displayName: 'Cotton',
      kind: WashProgramKind.cotton,
      availableTempsC: _euTemps,
      defaultTempC: 40,
      agitation: Agitation.normal,
      spinSpeedsRpm: _fullSpin,
      suitableFor: _sturdy,
      typicalDuration: Duration(minutes: 130),
    ),
    WashProgram(
      id: 'samsung.synthetics',
      displayName: 'Synthetics',
      kind: WashProgramKind.syntheticsMixed,
      availableTempsC: _euTempsLimited,
      defaultTempC: 40,
      agitation: Agitation.mild,
      spinSpeedsRpm: _midSpin,
      suitableFor: _everyday,
      typicalDuration: Duration(minutes: 95),
    ),
    WashProgram(
      id: 'samsung.delicates',
      displayName: 'Delicates',
      kind: WashProgramKind.delicates,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.veryMild,
      spinSpeedsRpm: _gentleSpin,
      suitableFor: _gentle,
      maxLoadFraction: 0.5,
      typicalDuration: Duration(minutes: 55),
    ),
    WashProgram(
      id: 'samsung.wool',
      displayName: 'Wool',
      kind: WashProgramKind.wool,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.veryMild,
      spinSpeedsRpm: _lowSpin,
      suitableFor: _gentle,
      maxLoadFraction: 0.4,
      typicalDuration: Duration(minutes: 50),
    ),
    WashProgram(
      id: 'samsung.quick',
      displayName: 'Quick Wash',
      kind: WashProgramKind.quick,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.normal,
      spinSpeedsRpm: _midSpin,
      suitableFor: _everyday,
      typicalDuration: Duration(minutes: 15),
    ),
    WashProgram(
      id: 'samsung.bedding',
      displayName: 'Bedding',
      kind: WashProgramKind.bedding,
      availableTempsC: _euTemps,
      defaultTempC: 40,
      agitation: Agitation.mild,
      spinSpeedsRpm: _midSpin,
      suitableFor: _sturdy,
      maxLoadFraction: 0.6,
      typicalDuration: Duration(minutes: 145),
    ),
    WashProgram(
      id: 'samsung.activewear',
      displayName: 'Activewear',
      kind: WashProgramKind.sportswear,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.mild,
      spinSpeedsRpm: _gentleSpin,
      suitableFor: _everyday,
      typicalDuration: Duration(minutes: 70),
    ),
  ],
);

const _whirlpoolWasher = WasherProfile(
  id: WasherId('seed.whirlpool.washer'),
  brand: 'Whirlpool',
  model: 'Top loader (typical)',
  capacityKg: 8.0,
  options: {
    WasherOption.extraRinse,
    WasherOption.prewash,
    WasherOption.delayStart,
    WasherOption.softenerDispenser,
  },
  programs: [
    WashProgram(
      id: 'whirlpool.normal',
      displayName: 'Normal',
      kind: WashProgramKind.cotton,
      availableTempsC: _usTemps,
      defaultTempC: 40,
      agitation: Agitation.normal,
      spinSpeedsRpm: _midSpin,
      suitableFor: _sturdy,
      typicalDuration: Duration(minutes: 60),
    ),
    WashProgram(
      id: 'whirlpool.heavy',
      displayName: 'Heavy Duty',
      kind: WashProgramKind.heavyDuty,
      availableTempsC: _usTemps,
      defaultTempC: 60,
      agitation: Agitation.normal,
      spinSpeedsRpm: _midSpin,
      suitableFor: {FabricClass.heavy},
      typicalDuration: Duration(minutes: 75),
    ),
    WashProgram(
      id: 'whirlpool.delicate',
      displayName: 'Delicate',
      kind: WashProgramKind.delicates,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.veryMild,
      spinSpeedsRpm: _lowSpin,
      suitableFor: _gentle,
      maxLoadFraction: 0.5,
      typicalDuration: Duration(minutes: 45),
    ),
    WashProgram(
      id: 'whirlpool.quick',
      displayName: 'Quick Wash',
      kind: WashProgramKind.quick,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.normal,
      spinSpeedsRpm: _midSpin,
      suitableFor: _everyday,
      typicalDuration: Duration(minutes: 28),
    ),
    WashProgram(
      id: 'whirlpool.bulky',
      displayName: 'Bulky Items',
      kind: WashProgramKind.bedding,
      availableTempsC: _usTemps,
      defaultTempC: 40,
      agitation: Agitation.mild,
      spinSpeedsRpm: _lowSpin,
      suitableFor: _sturdy,
      maxLoadFraction: 0.6,
      typicalDuration: Duration(minutes: 80),
    ),
  ],
);

const _geWasher = WasherProfile(
  id: WasherId('seed.ge.washer'),
  brand: 'GE',
  model: 'Top loader (typical)',
  capacityKg: 8.0,
  options: {
    WasherOption.extraRinse,
    WasherOption.prewash,
    WasherOption.delayStart,
    WasherOption.stainRemoval,
    WasherOption.softenerDispenser,
  },
  programs: [
    WashProgram(
      id: 'ge.normal',
      displayName: 'Normal',
      kind: WashProgramKind.cotton,
      availableTempsC: _usTemps,
      defaultTempC: 40,
      agitation: Agitation.normal,
      spinSpeedsRpm: _midSpin,
      suitableFor: _sturdy,
      typicalDuration: Duration(minutes: 55),
    ),
    WashProgram(
      id: 'ge.heavy',
      displayName: 'Heavy Duty',
      kind: WashProgramKind.heavyDuty,
      availableTempsC: _usTemps,
      defaultTempC: 60,
      agitation: Agitation.normal,
      spinSpeedsRpm: _midSpin,
      suitableFor: {FabricClass.heavy},
      typicalDuration: Duration(minutes: 70),
    ),
    WashProgram(
      id: 'ge.delicate',
      displayName: 'Delicate',
      kind: WashProgramKind.delicates,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.veryMild,
      spinSpeedsRpm: _lowSpin,
      suitableFor: _gentle,
      maxLoadFraction: 0.5,
      typicalDuration: Duration(minutes: 40),
    ),
    WashProgram(
      id: 'ge.perm',
      displayName: 'Casuals',
      kind: WashProgramKind.syntheticsMixed,
      availableTempsC: _usTemps,
      defaultTempC: 40,
      agitation: Agitation.mild,
      spinSpeedsRpm: _midSpin,
      suitableFor: _everyday,
      typicalDuration: Duration(minutes: 50),
    ),
  ],
);

const _boschWasher = WasherProfile(
  id: WasherId('seed.bosch.washer'),
  brand: 'Bosch',
  model: 'Front loader (typical)',
  capacityKg: 8.0,
  options: {
    WasherOption.extraRinse,
    WasherOption.prewash,
    WasherOption.delayStart,
    WasherOption.ecoMode,
    WasherOption.timeSaver,
    WasherOption.softenerDispenser,
  },
  programs: [
    WashProgram(
      id: 'bosch.cottons',
      displayName: 'Cottons',
      kind: WashProgramKind.cotton,
      availableTempsC: _euTemps,
      defaultTempC: 40,
      agitation: Agitation.normal,
      spinSpeedsRpm: _fullSpin,
      suitableFor: _sturdy,
      typicalDuration: Duration(minutes: 140),
    ),
    WashProgram(
      id: 'bosch.eco',
      displayName: 'Eco 40-60',
      kind: WashProgramKind.eco,
      availableTempsC: [40, 60],
      defaultTempC: 40,
      agitation: Agitation.normal,
      spinSpeedsRpm: _fullSpin,
      suitableFor: _sturdy,
      typicalDuration: Duration(minutes: 200),
    ),
    WashProgram(
      id: 'bosch.easycare',
      displayName: 'Easy-Care',
      kind: WashProgramKind.syntheticsMixed,
      availableTempsC: _euTempsLimited,
      defaultTempC: 40,
      agitation: Agitation.mild,
      spinSpeedsRpm: _midSpin,
      suitableFor: _everyday,
      typicalDuration: Duration(minutes: 105),
    ),
    WashProgram(
      id: 'bosch.delicates',
      displayName: 'Delicates/Silk',
      kind: WashProgramKind.delicates,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.veryMild,
      spinSpeedsRpm: _gentleSpin,
      suitableFor: _gentle,
      maxLoadFraction: 0.4,
      typicalDuration: Duration(minutes: 50),
    ),
    WashProgram(
      id: 'bosch.wool',
      displayName: 'Wool/Hand Wash',
      kind: WashProgramKind.handWash,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.veryMild,
      spinSpeedsRpm: _lowSpin,
      suitableFor: _gentle,
      maxLoadFraction: 0.3,
      typicalDuration: Duration(minutes: 40),
    ),
    WashProgram(
      id: 'bosch.super15',
      displayName: 'Super Quick 15',
      kind: WashProgramKind.quick,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.normal,
      spinSpeedsRpm: _midSpin,
      suitableFor: _everyday,
      maxLoadFraction: 0.4,
      typicalDuration: Duration(minutes: 15),
    ),
  ],
);

/// Speed Queen machines are deliberately mechanical and short on cycles — a
/// good stress case for the matcher's no-fit handling.
const _speedQueenWasher = WasherProfile(
  id: WasherId('seed.speedqueen.washer'),
  brand: 'Speed Queen',
  model: 'Top loader (typical)',
  capacityKg: 9.0,
  options: {WasherOption.prewash, WasherOption.extraRinse},
  programs: [
    WashProgram(
      id: 'sq.normal',
      displayName: 'Normal Eco',
      kind: WashProgramKind.cotton,
      availableTempsC: [0, 30, 40, 60],
      defaultTempC: 40,
      agitation: Agitation.normal,
      spinSpeedsRpm: [0, 700],
      suitableFor: _sturdy,
      typicalDuration: Duration(minutes: 45),
    ),
    WashProgram(
      id: 'sq.heavy',
      displayName: 'Heavy Duty',
      kind: WashProgramKind.heavyDuty,
      availableTempsC: [0, 30, 40, 60],
      defaultTempC: 60,
      agitation: Agitation.normal,
      spinSpeedsRpm: [0, 700],
      suitableFor: {FabricClass.heavy},
      typicalDuration: Duration(minutes: 50),
    ),
    WashProgram(
      id: 'sq.delicate',
      displayName: 'Delicate',
      kind: WashProgramKind.delicates,
      availableTempsC: [0, 30, 40],
      defaultTempC: 30,
      agitation: Agitation.veryMild,
      spinSpeedsRpm: [0, 700],
      suitableFor: _gentle,
      maxLoadFraction: 0.5,
      typicalDuration: Duration(minutes: 35),
    ),
  ],
);

const _maytagWasher = WasherProfile(
  id: WasherId('seed.maytag.washer'),
  brand: 'Maytag',
  model: 'Top loader (typical)',
  capacityKg: 8.5,
  options: {
    WasherOption.extraRinse,
    WasherOption.prewash,
    WasherOption.steam,
    WasherOption.delayStart,
    WasherOption.softenerDispenser,
  },
  programs: [
    WashProgram(
      id: 'maytag.normal',
      displayName: 'Normal',
      kind: WashProgramKind.cotton,
      availableTempsC: _usTemps,
      defaultTempC: 40,
      agitation: Agitation.normal,
      spinSpeedsRpm: _midSpin,
      suitableFor: _sturdy,
      typicalDuration: Duration(minutes: 60),
    ),
    WashProgram(
      id: 'maytag.heavy',
      displayName: 'Heavy Duty',
      kind: WashProgramKind.heavyDuty,
      availableTempsC: _usTemps,
      defaultTempC: 60,
      agitation: Agitation.normal,
      spinSpeedsRpm: _midSpin,
      suitableFor: {FabricClass.heavy},
      typicalDuration: Duration(minutes: 80),
    ),
    WashProgram(
      id: 'maytag.delicate',
      displayName: 'Delicates',
      kind: WashProgramKind.delicates,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.veryMild,
      spinSpeedsRpm: _lowSpin,
      suitableFor: _gentle,
      maxLoadFraction: 0.5,
      typicalDuration: Duration(minutes: 45),
    ),
    WashProgram(
      id: 'maytag.permpress',
      displayName: 'Permanent Press',
      kind: WashProgramKind.syntheticsMixed,
      availableTempsC: _usTemps,
      defaultTempC: 40,
      agitation: Agitation.mild,
      spinSpeedsRpm: _midSpin,
      suitableFor: _everyday,
      typicalDuration: Duration(minutes: 55),
    ),
    WashProgram(
      id: 'maytag.bulky',
      displayName: 'Bulky/Sheets',
      kind: WashProgramKind.bedding,
      availableTempsC: _usTemps,
      defaultTempC: 40,
      agitation: Agitation.mild,
      spinSpeedsRpm: _lowSpin,
      suitableFor: _sturdy,
      maxLoadFraction: 0.6,
      typicalDuration: Duration(minutes: 85),
    ),
  ],
);

const _electroluxWasher = WasherProfile(
  id: WasherId('seed.electrolux.washer'),
  brand: 'Electrolux',
  model: 'Front loader (typical)',
  capacityKg: 8.0,
  options: {
    WasherOption.extraRinse,
    WasherOption.prewash,
    WasherOption.steam,
    WasherOption.delayStart,
    WasherOption.ecoMode,
    WasherOption.softenerDispenser,
  },
  programs: [
    WashProgram(
      id: 'electrolux.cottons',
      displayName: 'Cottons',
      kind: WashProgramKind.cotton,
      availableTempsC: _euTemps,
      defaultTempC: 40,
      agitation: Agitation.normal,
      spinSpeedsRpm: _fullSpin,
      suitableFor: _sturdy,
      typicalDuration: Duration(minutes: 145),
    ),
    WashProgram(
      id: 'electrolux.synthetics',
      displayName: 'Synthetics',
      kind: WashProgramKind.syntheticsMixed,
      availableTempsC: _euTempsLimited,
      defaultTempC: 40,
      agitation: Agitation.mild,
      spinSpeedsRpm: _midSpin,
      suitableFor: _everyday,
      typicalDuration: Duration(minutes: 110),
    ),
    WashProgram(
      id: 'electrolux.delicates',
      displayName: 'Delicates',
      kind: WashProgramKind.delicates,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.veryMild,
      spinSpeedsRpm: _gentleSpin,
      suitableFor: _gentle,
      maxLoadFraction: 0.5,
      typicalDuration: Duration(minutes: 55),
    ),
    WashProgram(
      id: 'electrolux.wool',
      displayName: 'Wool/Silk',
      kind: WashProgramKind.wool,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.veryMild,
      spinSpeedsRpm: _lowSpin,
      suitableFor: _gentle,
      maxLoadFraction: 0.4,
      typicalDuration: Duration(minutes: 55),
    ),
    WashProgram(
      id: 'electrolux.quick',
      displayName: 'Quick 20',
      kind: WashProgramKind.quick,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.normal,
      spinSpeedsRpm: _midSpin,
      suitableFor: _everyday,
      maxLoadFraction: 0.5,
      typicalDuration: Duration(minutes: 20),
    ),
    WashProgram(
      id: 'electrolux.sport',
      displayName: 'Sport',
      kind: WashProgramKind.sportswear,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.mild,
      spinSpeedsRpm: _gentleSpin,
      suitableFor: _everyday,
      typicalDuration: Duration(minutes: 65),
    ),
  ],
);

/// The fallback when a user's brand is not listed, and the base for a custom
/// profile they build themselves.
const _genericWasher = WasherProfile(
  id: WasherId('seed.generic.washer'),
  brand: 'Generic',
  model: 'Washing machine',
  capacityKg: 7.0,
  options: {WasherOption.extraRinse, WasherOption.prewash},
  programs: [
    WashProgram(
      id: 'generic.normal',
      displayName: 'Normal',
      kind: WashProgramKind.cotton,
      availableTempsC: _euTemps,
      defaultTempC: 40,
      agitation: Agitation.normal,
      spinSpeedsRpm: _midSpin,
      suitableFor: _sturdy,
      typicalDuration: Duration(minutes: 90),
    ),
    WashProgram(
      id: 'generic.synthetics',
      displayName: 'Synthetics',
      kind: WashProgramKind.syntheticsMixed,
      availableTempsC: _euTempsLimited,
      defaultTempC: 40,
      agitation: Agitation.mild,
      spinSpeedsRpm: _midSpin,
      suitableFor: _everyday,
      typicalDuration: Duration(minutes: 80),
    ),
    WashProgram(
      id: 'generic.delicates',
      displayName: 'Delicates',
      kind: WashProgramKind.delicates,
      availableTempsC: _coldTemps,
      defaultTempC: 30,
      agitation: Agitation.veryMild,
      spinSpeedsRpm: _gentleSpin,
      suitableFor: _gentle,
      maxLoadFraction: 0.5,
      typicalDuration: Duration(minutes: 50),
    ),
  ],
);

// --- Dryers ---------------------------------------------------------------

const _standardDryPrograms = [
  DryProgram(
    id: 'std.normal',
    displayName: 'Normal',
    kind: DryProgramKind.normal,
    availableHeats: [
      TumbleDryHeat.low,
      TumbleDryHeat.medium,
      TumbleDryHeat.high
    ],
    defaultHeat: TumbleDryHeat.medium,
    suitableFor: _sturdy,
    typicalDuration: Duration(minutes: 55),
  ),
  DryProgram(
    id: 'std.permpress',
    displayName: 'Permanent Press',
    kind: DryProgramKind.permanentPress,
    availableHeats: [TumbleDryHeat.low, TumbleDryHeat.medium],
    defaultHeat: TumbleDryHeat.medium,
    suitableFor: _everyday,
    typicalDuration: Duration(minutes: 45),
  ),
  DryProgram(
    id: 'std.delicates',
    displayName: 'Delicates',
    kind: DryProgramKind.delicates,
    availableHeats: [TumbleDryHeat.noHeat, TumbleDryHeat.low],
    defaultHeat: TumbleDryHeat.low,
    suitableFor: _gentle,
    maxLoadFraction: 0.5,
    typicalDuration: Duration(minutes: 40),
  ),
  DryProgram(
    id: 'std.airfluff',
    displayName: 'Air Fluff',
    kind: DryProgramKind.airFluff,
    availableHeats: [TumbleDryHeat.noHeat],
    defaultHeat: TumbleDryHeat.noHeat,
    suitableFor: _allFabrics,
    control: DrynessControl.timed,
    typicalDuration: Duration(minutes: 30),
  ),
  DryProgram(
    id: 'std.timed',
    displayName: 'Timed Dry',
    kind: DryProgramKind.timedDry,
    availableHeats: [
      TumbleDryHeat.noHeat,
      TumbleDryHeat.low,
      TumbleDryHeat.medium
    ],
    defaultHeat: TumbleDryHeat.low,
    suitableFor: _allFabrics,
    control: DrynessControl.timed,
    typicalDuration: Duration(minutes: 40),
  ),
];

const _lgDryer = DryerProfile(
  id: DryerId('seed.lg.dryer'),
  brand: 'LG',
  model: 'Condenser dryer (typical)',
  capacityKg: 9.0,
  options: {DryerOption.wrinkleGuard, DryerOption.steam, DryerOption.ecoDry},
  programs: _standardDryPrograms,
);

const _samsungDryer = DryerProfile(
  id: DryerId('seed.samsung.dryer'),
  brand: 'Samsung',
  model: 'Heat pump dryer (typical)',
  capacityKg: 9.0,
  options: {DryerOption.wrinkleGuard, DryerOption.steam, DryerOption.ecoDry},
  programs: _standardDryPrograms,
);

const _whirlpoolDryer = DryerProfile(
  id: DryerId('seed.whirlpool.dryer'),
  brand: 'Whirlpool',
  model: 'Vented dryer (typical)',
  capacityKg: 8.0,
  options: {DryerOption.wrinkleGuard, DryerOption.sanitize},
  programs: _standardDryPrograms,
);

const _geDryer = DryerProfile(
  id: DryerId('seed.ge.dryer'),
  brand: 'GE',
  model: 'Vented dryer (typical)',
  capacityKg: 8.0,
  options: {DryerOption.wrinkleGuard, DryerOption.sanitize},
  programs: _standardDryPrograms,
);

const _boschDryer = DryerProfile(
  id: DryerId('seed.bosch.dryer'),
  brand: 'Bosch',
  model: 'Heat pump dryer (typical)',
  capacityKg: 8.0,
  options: {DryerOption.ecoDry, DryerOption.reverseTumble},
  programs: [
    ..._standardDryPrograms,
    DryProgram(
      id: 'bosch.wool',
      displayName: 'Wool Finish',
      kind: DryProgramKind.wool,
      availableHeats: [TumbleDryHeat.noHeat],
      defaultHeat: TumbleDryHeat.noHeat,
      suitableFor: _gentle,
      control: DrynessControl.timed,
      maxLoadFraction: 0.3,
      typicalDuration: Duration(minutes: 20),
    ),
  ],
);

/// Speed Queen dryers are timer-driven with few programmes — another useful
/// stress case, since nothing here uses moisture sensing.
const _speedQueenDryer = DryerProfile(
  id: DryerId('seed.speedqueen.dryer'),
  brand: 'Speed Queen',
  model: 'Vented dryer (typical)',
  capacityKg: 9.0,
  programs: [
    DryProgram(
      id: 'sq.regular',
      displayName: 'Regular',
      kind: DryProgramKind.normal,
      availableHeats: [TumbleDryHeat.medium, TumbleDryHeat.high],
      defaultHeat: TumbleDryHeat.high,
      suitableFor: _sturdy,
      control: DrynessControl.timed,
      typicalDuration: Duration(minutes: 50),
    ),
    DryProgram(
      id: 'sq.delicate',
      displayName: 'Delicate',
      kind: DryProgramKind.delicates,
      availableHeats: [TumbleDryHeat.low],
      defaultHeat: TumbleDryHeat.low,
      suitableFor: _gentle,
      control: DrynessControl.timed,
      typicalDuration: Duration(minutes: 40),
    ),
    DryProgram(
      id: 'sq.airfluff',
      displayName: 'Air Fluff',
      kind: DryProgramKind.airFluff,
      availableHeats: [TumbleDryHeat.noHeat],
      defaultHeat: TumbleDryHeat.noHeat,
      suitableFor: _allFabrics,
      control: DrynessControl.timed,
      typicalDuration: Duration(minutes: 30),
    ),
  ],
);

const _maytagDryer = DryerProfile(
  id: DryerId('seed.maytag.dryer'),
  brand: 'Maytag',
  model: 'Vented dryer (typical)',
  capacityKg: 8.5,
  options: {DryerOption.wrinkleGuard, DryerOption.steam},
  programs: _standardDryPrograms,
);

const _electroluxDryer = DryerProfile(
  id: DryerId('seed.electrolux.dryer'),
  brand: 'Electrolux',
  model: 'Heat pump dryer (typical)',
  capacityKg: 8.0,
  options: {DryerOption.ecoDry, DryerOption.reverseTumble},
  programs: _standardDryPrograms,
);

const _genericDryer = DryerProfile(
  id: DryerId('seed.generic.dryer'),
  brand: 'Generic',
  model: 'Tumble dryer',
  capacityKg: 7.0,
  programs: [
    DryProgram(
      id: 'generic.normal',
      displayName: 'Normal',
      kind: DryProgramKind.normal,
      availableHeats: [
        TumbleDryHeat.low,
        TumbleDryHeat.medium,
        TumbleDryHeat.high
      ],
      defaultHeat: TumbleDryHeat.medium,
      suitableFor: _sturdy,
      typicalDuration: Duration(minutes: 60),
    ),
    DryProgram(
      id: 'generic.low',
      displayName: 'Low Heat',
      kind: DryProgramKind.delicates,
      availableHeats: [TumbleDryHeat.noHeat, TumbleDryHeat.low],
      defaultHeat: TumbleDryHeat.low,
      suitableFor: _gentle,
      typicalDuration: Duration(minutes: 45),
    ),
  ],
);
