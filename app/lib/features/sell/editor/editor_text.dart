/// The few sentences of the editor that are built from numbers.
///
/// Kept apart from the widgets so the wording can be tested without a screen:
/// "1 hour ago" against "1 hours ago" is a bug that is invisible until the
/// right minute, and a pound and a half that reads "1 lb 8 oz" is a decision
/// worth making once.
///
/// None of it is a selling rule. The weights come from the core, the money from
/// `formatUsd`; this only writes them down.
library;

/// [count] with thousands separated: `1000` is `1,000`.
///
/// For the counters under the description, which are read against Depop's own
/// "312 / 1,000".
String groupedCount(int count) {
  final digits = count.abs().toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return count < 0 ? '-$digits' : digits;
}

/// [ounces] as a postal scale reads: `12 oz`, `1 lb`, `1 lb 2 oz`.
///
/// Whole ounces, as the core gives them, rounded up there on purpose.
String weightPhrase(int ounces) {
  final pounds = ounces ~/ 16;
  final remainder = ounces % 16;
  if (pounds == 0) return '$ounces oz';
  return remainder == 0 ? '$pounds lb' : '$pounds lb $remainder oz';
}

/// How long ago [then] was, as of [now]: `just now`, `5 minutes ago`,
/// `1 hour ago`, `3 days ago`.
///
/// Days is the largest unit. A price checked 40 days ago should say 40, not
/// "about a month", because the number is the point: it is how stale the price
/// is. A time in the future, which a phone with the wrong clock produces, is
/// "just now" and not "-3 minutes ago".
String agoPhrase(DateTime then, DateTime now) {
  final elapsed = now.difference(then);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return _count(elapsed.inMinutes, 'minute');
  if (elapsed.inDays < 1) return _count(elapsed.inHours, 'hour');
  return _count(elapsed.inDays, 'day');
}

String _count(int number, String unit) =>
    '$number $unit${number == 1 ? '' : 's'} ago';

/// How long a listing has been up: `Listed today`, `Listed 1 day ago`,
/// `Listed 16 days ago`.
///
/// [onSale] is how long since it was posted. Whole days, so a listing posted
/// yesterday evening reads as today until a full day has gone — the same count
/// the 14-day nudge is made against.
String listedPhrase(Duration onSale) {
  final days = onSale.inDays;
  if (days < 1) return 'Listed today';
  return 'Listed ${_count(days, 'day')}';
}

/// What a search left out, for the line under the results: `2 not in US
/// dollars, 1 price not on the page, 4 not alike`.
///
/// Only the reasons that apply, in the order the server counts them. Empty
/// when nothing was left out, which is for the caller to leave unsaid.
String excludedPhrase({
  required int notUsd,
  required int unverifiedPrice,
  required int notComparable,
}) => [
  if (notUsd > 0) '$notUsd not in US dollars',
  if (unverifiedPrice > 0)
    '$unverifiedPrice ${unverifiedPrice == 1 ? 'price' : 'prices'} '
        'not on the page',
  if (notComparable > 0) '$notComparable not alike',
].join(', ');
