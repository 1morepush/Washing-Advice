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

  /// Whether the item is still owned. Terminal states stay in the record for
  /// statistics but leave the active wardrobe.
  bool get isOwned => switch (this) {
        purchased || active || stored || inLaundry || beingRepaired => true,
        donated || sold || discarded || lost => false,
      };

  /// Whether the item can be worn or put in an outfit right now.
  bool get isWearable => this == active;

  /// Whether the item should be offered to the laundry sorter.
  bool get isLaunderable => this == active || this == inLaundry;

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
      active || stored || inLaundry || beingRepaired => true,
      donated || sold || discarded || lost => false,
    };
  }
}
