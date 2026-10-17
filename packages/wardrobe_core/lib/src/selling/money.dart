/// Money on the selling side: whole US cents, written and rounded the way a
/// Depop listing is.
///
/// Every amount in `selling/` is an [int] of US cents. A price held as a
/// double drifts the moment it is multiplied by a fee or a markup, and a net
/// payout that is a cent out is a number somebody will notice. Only US dollars
/// are carried at all — the contract excludes anything else rather than
/// converting it, because a comparable built on an invented exchange rate looks
/// like evidence and is not.
library;

/// Under this a price is rounded to a whole dollar; from here up, to $5.
const int _wholeDollarCeilingCents = 1000;

/// The smallest asking price a listing is given.
const int _minimumListPriceCents = 100;

/// The step listings of $10 and over are priced in.
const int _bigStepCents = 500;

/// Writes cents as dollars: `2856` is `$28.56`, `45` is `$0.45`.
///
/// Always two decimal places, because a price column that reads `$30` beside
/// `$28.56` is harder to compare than one that lines up. Thousands are grouped
/// (`$1,234.56`), and a negative amount keeps its sign in front of the dollar
/// sign (`-$0.45`), the way a statement prints it.
String formatUsd(int cents) {
  final sign = cents < 0 ? '-' : '';
  final absolute = cents.abs();

  final dollars = (absolute ~/ 100).toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
  final remainder = (absolute % 100).toString().padLeft(2, '0');

  return '$sign\$$dollars.$remainder';
}

/// Rounds to a price somebody would actually put on a listing.
///
/// Under $10 it is the nearest whole dollar, and never less than $1. From $10
/// up it is the nearest multiple of $5. Halves round up, so $9.50 is $10 and
/// $12.50 is $15 — a tie goes to the seller, since a price that was only ever
/// a median is not worth defending to the cent.
///
/// Whole dollars and round fives are not tidiness. A buyer scrolling a feed
/// reads $25 as a decision and $24.37 as a calculation, and offers arrive in
/// round numbers too, so a round asking price leaves room for them to land on
/// one.
int roundListPrice(int cents) {
  if (cents < _wholeDollarCeilingCents) {
    final dollars = (cents + 50) ~/ 100;
    final rounded = dollars * 100;
    return rounded < _minimumListPriceCents ? _minimumListPriceCents : rounded;
  }
  return ((cents + _bigStepCents ~/ 2) ~/ _bigStepCents) * _bigStepCents;
}

/// The largest listing price at or below [cents], by the same convention as
/// [roundListPrice].
///
/// For when a price has a ceiling it must not cross. Rounding to the *nearest*
/// can step over one — $63.50 rounds to $65 — and a used garment priced above
/// what it costs new is the one mistake the price suggestion exists to
/// prevent. Kept beside [roundListPrice] because the convention is one
/// decision and should live in one file.
///
/// Never less than $1, which is as low as a listing goes, so a ceiling under a
/// dollar is not honoured.
int roundListPriceDown(int cents) {
  if (cents < _wholeDollarCeilingCents) {
    final rounded = (cents ~/ 100) * 100;
    return rounded < _minimumListPriceCents ? _minimumListPriceCents : rounded;
  }
  return (cents ~/ _bigStepCents) * _bigStepCents;
}

/// The middle value of [values].
///
/// With an even count it is the mean of the two in the middle, rounded to the
/// nearest cent with halves up. A median rather than a mean because a single
/// absurd listing — somebody asking $400 for a $30 sweatshirt — moves a mean
/// a long way and a median not at all, and a price built on the comparables
/// has to survive the odd outlier among them.
///
/// Does not reorder [values]. Throws [ArgumentError] when it is empty: there
/// is no middle of nothing, and the caller knows what it wants to say then.
int median(List<int> values) {
  if (values.isEmpty) {
    throw ArgumentError.value(
      values,
      'values',
      'cannot take the median of nothing',
    );
  }

  final sorted = List<int>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];

  return (sorted[middle - 1] + sorted[middle] + 1) ~/ 2;
}
