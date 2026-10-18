/// Saying when, in the words the rest of the app uses.
///
/// "16 days ago" is the wording Settings already uses for the last sync, and a
/// listing is dated the same way: how long it has been up is what a seller
/// asks, and a date they would have to subtract from today's is not an answer.
/// A sale is the other way round. It is a record, and "180 days ago" is a worse
/// thing to read about it in a year than the day it happened.
library;

/// How long ago, as a person says it: `just now`, `5 minutes ago`, `3 hours
/// ago`, `16 days ago`.
///
/// Singular where it is one, which the sync line does not trouble with: a
/// listing put up yesterday is far likelier than a sync exactly a day old.
String timeAgo(Duration elapsed) {
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${_count(elapsed.inMinutes, 'minute')} ago';
  if (elapsed.inDays < 1) return '${_count(elapsed.inHours, 'hour')} ago';
  return '${_count(elapsed.inDays, 'day')} ago';
}

/// Whole weeks, for a listing that has sat long enough to be worth refreshing:
/// `2 weeks`. A listing is only nudged from fourteen days, so this is never one.
String weeksLabel(Duration elapsed) => _count(elapsed.inDays ~/ 7, 'week');

/// `25 Sep 2026`, in the phone's own time zone.
///
/// A moment is stored in UTC and a day is somebody's local one: a sale at ten to
/// midnight at home is on that day, not on the next.
String shortDate(DateTime moment) {
  final local = moment.toLocal();
  return '${local.day} ${_months[local.month - 1].substring(0, 3)} '
      '${local.year}';
}

/// `17 October 2026`, for a date that is a calendar day and not a moment.
///
/// Read as it was written, with no time zone applied: the fee schedule is dated
/// the 17th, and a phone west of Greenwich must not turn that into the 16th.
String calendarDate(DateTime day) =>
    '${day.day} ${_months[day.month - 1]} ${day.year}';

String _count(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
