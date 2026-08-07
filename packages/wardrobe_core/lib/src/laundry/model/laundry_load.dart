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
    this.rationale = const [],
  });

  final LoadId id;

  /// The items in this load.
  final List<WardrobeItem> items;

  /// Care requirements satisfying every member — the most restrictive of them.
  final CareInstructions effectiveCare;

  final WashSpec washSpec;
  final DrySpec drySpec;

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
