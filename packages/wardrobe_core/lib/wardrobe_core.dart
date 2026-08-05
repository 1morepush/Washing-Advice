/// Domain core for the Washing Advice wardrobe and laundry assistant.
///
/// Pure Dart, no Flutter, no runtime dependencies. Everything that decides how
/// a garment is treated lives here so it can be tested exhaustively and run
/// offline — the UI and the AI layer sit on top of this, never the other way
/// round.
///
/// The package is organised by bounded context:
///
/// * `shared` — confidence and provenance, typed ids, clock, feature flags.
/// * `wardrobe` — what the user owns: items, fabric, colour, photos, condition,
///   lifecycle and relationships.
/// * `care` — how things must be treated: the ISO 3758 model, the care rule
///   table, resolution between conflicting sources, and plain-English rendering.
/// * `laundry` — doing the wash: sorting a pile into loads and recording them.
/// * `machines` — translating abstract requirements into settings on a real
///   washer or dryer.
/// * `matching` — recognising a garment already in the wardrobe.
/// * `vision` — the contract the AI layer must satisfy (no implementation).
/// * `events` — the append-only history and the projections derived from it.
library;

// Exports are ordered by path, which keeps each bounded context together.

// Care: the ISO 3758 model, rule table, resolution and plain-English output.
export 'src/care/care_language.dart';
export 'src/care/care_resolver.dart';
export 'src/care/model/care_instructions.dart';
export 'src/care/model/care_symbols.dart';
export 'src/care/model/wash_spec.dart';
export 'src/care/rules/care_rule.dart';
export 'src/care/rules/default_rules.dart';
export 'src/care/rules/rule_evaluator.dart';
// Events: the append-only history and its projections.
export 'src/events/event_log.dart';
export 'src/events/projections.dart';
export 'src/events/wardrobe_event.dart';
// Laundry: sorting a pile into loads, and recording what was run.
export 'src/laundry/model/laundry_load.dart';
export 'src/laundry/model/laundry_record.dart';
export 'src/laundry/sorting/laundry_sorter.dart';
export 'src/laundry/sorting/separation_rules.dart';
// Machines: profiles and translation into concrete settings.
export 'src/machines/model/dryer_profile.dart';
export 'src/machines/model/machine_setting.dart';
export 'src/machines/model/washer_profile.dart';
export 'src/machines/program_matcher.dart';
export 'src/machines/seed/machine_catalog.dart';
// Matching: recognising an item already in the wardrobe.
export 'src/matching/attribute_matcher.dart';
export 'src/matching/fingerprint.dart';
export 'src/matching/matcher.dart';
// Shared kernel.
export 'src/shared/clock.dart';
export 'src/shared/confidence.dart';
export 'src/shared/feature_flags.dart';
export 'src/shared/ids.dart';
// Vision: the contract the AI layer must satisfy.
export 'src/vision/vision_port.dart';
// Wardrobe: what the user owns.
export 'src/wardrobe/in_memory_repository.dart';
export 'src/wardrobe/model/condition.dart';
export 'src/wardrobe/model/fabric.dart';
export 'src/wardrobe/model/item_attributes.dart';
export 'src/wardrobe/model/item_color.dart';
export 'src/wardrobe/model/lifecycle.dart';
export 'src/wardrobe/model/ownership.dart';
export 'src/wardrobe/model/photo.dart';
export 'src/wardrobe/model/relationship.dart';
export 'src/wardrobe/model/wardrobe_item.dart';
export 'src/wardrobe/query.dart';
export 'src/wardrobe/repository.dart';
