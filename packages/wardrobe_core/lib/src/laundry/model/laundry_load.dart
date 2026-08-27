/// The output of sorting a pile of laundry.
///
/// Every load explains itself. "Load 2 runs at 30°C because your new red tee
/// bleeds" is far more useful — and far more trustworthy — than a bare
/// temperature, and it is what lets a user disagree with the app intelligently
/// rather than just ignoring it.
library;

import '../../care/model/care_instructions.dart';
import '../../care/model/wash_spec.dart';
import '../../machines/model/machine_setting.dart';
import '../../shared/ids.dart';
import '../../wardrobe/model/wardrobe_item.dart';

/// Why a load ended up the way it did.
enum RationaleKind {
  temperature('Temperature'),
  agitation('Cycle'),
  spin('Spin speed'),
  separation('Kept separate'),
  capacity('Load size'),
  drying('Drying'),
  handling('Handling');

  const RationaleKind(this.label);

  final String label;
}

/// One explanation attached to a load.
final class LoadRationale {
  const LoadRationale({
    required this.kind,
    required this.reason,
    this.causedBy,
    this.causedByName,
  });

  final RationaleKind kind;

  /// A complete sentence, ready to show.
  final String reason;

  /// The item that forced this, when one item is responsible.
  final ItemId? causedBy;

  /// That item's display name, so the UI need not look it up.
  final String? causedByName;

  @override
  String toString() => reason;
}

/// An item the sorter could not place, and why.
final class UnassignedItem {
  const UnassignedItem({
    required this.item,
    required this.reason,
    this.needsUserAction = false,
  });

  final WardrobeItem item;

  /// Why it was left out, in words the user can act on.
  final String reason;

  /// Whether the user can resolve this — by scanning a care label, say — as
  /// opposed to it simply not being laundry.
  final bool needsUserAction;

  @override
  String toString() => '${item.displayName}: $reason';
}

/// One wash load.
/// Part of a load that dries together.
///
/// A load is grouped for *washing*: the members share a drum because their
/// wash requirements are compatible. Drying is a separate question, and the
/// answers differ more often than they agree — a cotton tee and a technical
/// short can be washed in one drum, and one of them must not go near a dryer.
///
/// Left as one group the whole load takes the most restrictive answer, which
/// means one air-dry-only garment sends everything to the airer. Splitting is
/// the finer answer and costs the user a sorting step, so which one they get
/// is a preference rather than a decision made for them.
final class DryingGroup {
  const DryingGroup({
    required this.items,
    required this.spec,
    this.dryerSetting,
  });

  final List<WardrobeItem> items;
  final DrySpec spec;

  /// Concrete settings for the user's dryer, when one is configured.
  final DryerSetting? dryerSetting;

  /// Whether this group goes in the machine or on the airer.
  bool get isTumbleDried => spec.tumbleDryAllowed;

  double get totalWeightKg =>
      items.fold(0.0, (total, item) => total + item.drumLoadGrams) / 1000.0;
}

final class LaundryLoad {
  const LaundryLoad({
    required this.id,
    required this.items,
    required this.effectiveCare,
    required this.washSpec,
    required this.drySpec,
    required this.label,
    required this.totalWeightKg,
    this.washerSetting,
    this.dryerSetting,
    this.dryingGroups = const [],
    this.rationale = const [],
  });

  final LoadId id;

  /// The items in this load.
  final List<WardrobeItem> items;

  /// Care requirements satisfying every member — the most restrictive of them.
  final CareInstructions effectiveCare;

  final WashSpec washSpec;

  /// What drying this load as one demands: the most restrictive of its
  /// members. Unchanged in meaning, and still what a load dried together
  /// follows.
  final DrySpec drySpec;

  /// How the load divides for drying.
  ///
  /// One group when the load dries together, which is the default and is the
  /// behaviour every earlier version had. More than one when the user asked
  /// for drying to be split, in which case each group carries its own spec and
  /// the tumble-dryable part is no longer held back by the rest.
  ///
  /// Never empty for a load the sorter built. Empty only on a load constructed
  /// without them, where [items] is the whole answer.
  final List<DryingGroup> dryingGroups;

  /// Whether drying this load means more than one thing.
  bool get driesInParts => dryingGroups.length > 1;

  /// A short description, e.g. `'Darks — cold, gentle'`.
  final String label;

  /// Estimated dry weight, for judging how full the drum will be.
  final double totalWeightKg;

  /// Concrete settings for the user's washer, once one is configured.
  final WasherSetting? washerSetting;

  /// Concrete settings for the user's dryer.
  final DryerSetting? dryerSetting;

  /// Why this load has the settings it does.
  final List<LoadRationale> rationale;

  int get itemCount => items.length;

  bool get isEmpty => items.isEmpty;

  /// Whether anything about this load needs the user's attention.
  bool get hasWarnings =>
      (washerSetting?.hasWarnings ?? false) ||
      (dryerSetting?.hasWarnings ?? false);

  /// Whether the recommended settings are an imperfect fit for the machine.
  bool get isCompromise =>
      (washerSetting?.isCompromise ?? false) ||
      (dryerSetting?.isCompromise ?? false);

  List<LoadRationale> rationaleOf(RationaleKind kind) => [
        for (final r in rationale)
          if (r.kind == kind) r
      ];

  @override
  String toString() => 'LaundryLoad($label, $itemCount items)';
}

/// A complete sorting result.
final class LaundryPlan {
  const LaundryPlan({
    required this.loads,
    required this.unassigned,
    required this.generatedAt,
  });

  final List<LaundryLoad> loads;

  /// Items deliberately left out, each with a reason.
  final List<UnassignedItem> unassigned;

  final DateTime generatedAt;

  int get loadCount => loads.length;

  int get itemsSorted => loads.fold(0, (total, load) => total + load.itemCount);

  bool get isEmpty => loads.isEmpty;

  /// Items the user could bring into the plan by acting — usually by scanning
  /// a care label.
  List<UnassignedItem> get actionable => [
        for (final item in unassigned)
          if (item.needsUserAction) item
      ];

  @override
  String toString() => 'LaundryPlan($loadCount loads, $itemsSorted items, '
      '${unassigned.length} unassigned)';
}
