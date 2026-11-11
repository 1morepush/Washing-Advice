/// The names of days and months, for the calendar.
///
/// Written out here, in English like the rest of the app, rather than pulling
/// in a localisation package for two lists.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

const monthNames = [
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

/// Monday first, as [DateTime.weekday] counts.
const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// `March 2026`.
String monthTitle(int year, int month) => '${monthNames[month - 1]} $year';

/// `Wednesday 4 March`, or `Wednesday 4 March 2026` outside [relativeTo]'s year.
String dayTitle(CalendarDate date, {CalendarDate? relativeTo}) {
  final base =
      '${weekdayNames[date.weekday - 1]} ${date.day} '
      '${monthNames[date.month - 1]}';
  return relativeTo != null && relativeTo.year == date.year
      ? base
      : '$base ${date.year}';
}

/// `2026-03-04`, the form a day has in the address.
String dateSlug(CalendarDate date) => date.toString();

/// The day an address names, or null for anything that is not a real date.
///
/// Strict: `2026-02-30` is nothing, not the 2nd of March, because a link that
/// opens a day nobody asked for is worse than one that says there is no such
/// day.
CalendarDate? parseDateSlug(String text) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > CalendarDate.daysIn(year, month)) return null;
  return CalendarDate(year, month, day);
}
