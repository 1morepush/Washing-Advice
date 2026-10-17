/// What a parcel is likely to weigh, to choose a postage label by.
///
/// An estimate and nothing more. A seller buys the label before the parcel is
/// on a scale, and the cost of guessing wrong is not a refund but postage due:
/// the carrier weighs it, charges the difference, and the buyer is left holding
/// a parcel with a bill attached. So the answer is shaped to be corrected —
/// weigh the packed item before paying for the label.
library;

import '../wardrobe/model/item_attributes.dart';

/// A poly mailer and the label on it. Added to every garment, since the thing
/// in the post is never only the garment.
const int _polyMailerGrams = 60;

const double _gramsPerOunce = 28.349523125;

/// A guess at what a packed parcel weighs.
final class ShippingEstimate {
  const ShippingEstimate({
    required this.packedGrams,
    required this.ounces,
    required this.band,
  });

  /// The garment's typical weight plus its packaging.
  final int packedGrams;

  /// [packedGrams] in whole ounces, rounded **up**.
  ///
  /// Up, because postage rounds a fractional weight to the next step rather
  /// than the last, and a label bought for too little comes back as postage
  /// due. This is the number to start from when buying the label.
  final int ounces;

  /// The price band that weight falls in: `under 8 oz`, `under 1 lb`, `1–2 lb`,
  /// `2–3 lb` or `over 3 lb`.
  ///
  /// Decided on the weight itself, not on the rounded [ounces], so it is the
  /// lowest band the parcel can honestly be in: a parcel of 7.4 oz is `under
  /// 8 oz` although its label weight is 8. Postage is quoted in bands, so this
  /// is the line to compare with a price before deciding what a sale is worth.
  final String band;
}

/// Estimates the packed weight of an item of [type].
///
/// From the type's typical dry weight — the same figure the laundry sorter
/// fills a drum with — plus a poly mailer. Typical, not actual: a heavy knit
/// and a thin one are the same "sweater" here. Treat it as a place to start and
/// weigh the packed item before buying the label.
ShippingEstimate estimateShipping(ItemType type) {
  final grams = type.typicalWeightGrams + _polyMailerGrams;
  final exactOunces = grams / _gramsPerOunce;

  return ShippingEstimate(
    packedGrams: grams,
    ounces: exactOunces.ceil(),
    band: _bandFor(exactOunces),
  );
}

String _bandFor(double ounces) {
  if (ounces < 8) return 'under 8 oz';
  if (ounces < 16) return 'under 1 lb';
  if (ounces <= 32) return '1–2 lb';
  if (ounces <= 48) return '2–3 lb';
  return 'over 3 lb';
}
