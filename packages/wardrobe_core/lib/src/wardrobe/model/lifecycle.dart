/// The life of an item, from purchase to disposal.
///
/// Modelling this explicitly means "how long do I keep things", "what did that
/// jacket really cost me per wear" and "what have I not worn in a year" are
/// queries over recorded history rather than guesses. It also stops donated and
/// discarded items polluting laundry sorting and outfit suggestions.
library;

/// Where an item currently is in its life.
enum LifecycleState {
  /// Bought but not yet added to the wardrobe — an online order in transit,
  /// or a receipt scanned ahead of the item arriving.
  purchased('Purchased'),

  /// In the wardrobe and available to wear.
  active('Active'),

  /// Packed away — off-season storage, or in a suitcase.
  stored('Stored'),

  /// Sitting in the laundry basket, unavailable until washed.
  inLaundry('In laundry'),

  /// In the washing machine right now.
  ///
  /// Distinct from [inLaundry] because the answer to "can I wear this
  /// tonight?" is different — a shirt in the basket can be washed in time, one
  /// mid-cycle cannot — and because the sorter must not put an item that is
  /// already in the drum into a second load.
  beingWashed('Being washed'),

  /// In the dryer, or hanging up to dry.
  beingDried('Being dried'),

  /// Away for repair or alteration.
  beingRepaired('Being repaired'),

  /// Given away. Kept for history and statistics, hidden from the wardrobe.
  donated('Donated'),

  /// Sold on.
  sold('Sold'),

  /// Worn out and thrown away.
  discarded('Discarded'),

  /// Gone missing.
  lost('Lost');

  const LifecycleState(this.label);

  final String label;

  /// Reads a stored name, falling back to [active] for one it does not know.
  ///
  /// States get added, and a device still running an older build can be synced
  /// an item in one it has never heard of. `values.byName` throws, so a single
  /// unrecognised string would take down the read of the whole wardrobe rather
  /// than of one field. A stale value the user can see and correct is by far
  /// the better failure.
  static LifecycleState parse(String name) =>
      values.asNameMap()[name] ?? active;

  /// Whether the item is still owned. Terminal states stay in the record for
  /// statistics but leave the active wardrobe.
  bool get isOwned => switch (this) {
        purchased ||
        active ||
        stored ||
        inLaundry ||
        beingWashed ||
        beingDried ||
        beingRepaired =>
          true,
        donated || sold || discarded || lost => false,
      };

  /// Whether the item can be worn or put in an outfit right now.
  bool get isWearable => this == active;

  /// Whether the item should be offered to the laundry sorter.
  ///
  /// Emphatically not everything in the laundry cycle: something already in the
  /// drum must not be planned into a *second* load. Only the basket, and the
  /// clean clothes a pile photograph might turn up.
  bool get isLaunderable => this == active || this == inLaundry;

  /// Whether the item is somewhere between the basket and the wardrobe.
  ///
  /// The union the laundry screen counts, and the reason [isWearable] is false
  /// for all three: it is not in the wardrobe to be worn.
  bool get isInLaundryCycle =>
      this == inLaundry || this == beingWashed || this == beingDried;

  /// Whether moving to [next] makes sense.
  ///
  /// Prevents nonsense transitions such as reviving a discarded item, while
  /// staying permissive enough for real life — people do retrieve things from
  /// storage, and repair things twice.
  bool canTransitionTo(LifecycleState next) {
    if (this == next) return true;
    if (!isOwned) return false; // Terminal states are final.
    return switch (this) {
      purchased => next == active || next == stored || !next.isOwned,
      active ||
      stored ||
      inLaundry ||
      beingWashed ||
      beingDried ||
      beingRepaired =>
        true,
      donated || sold || discarded || lost => false,
    };
  }
}
