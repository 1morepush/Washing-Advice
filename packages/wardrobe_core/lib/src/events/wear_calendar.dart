/// What was worn on each day: the outfit calendar's projection.
///
/// A fold over the wear events, like the co-wear graph and the usage counters,
/// and for the same reason: nothing is stored, so there is no second record of
/// what was worn to keep in step with the log, and it applies to history the
/// app already holds the moment it ships.
///
/// **A day is the person's day, not UTC's.** A wear logged at 23:30 in
/// California is the next morning in UTC, and a calendar that put Tuesday's
/// evening outfit on Wednesday would be wrong for every evening of the week
/// west of Greenwich. The core has no time zone database and should not grow
/// one, so the caller passes in the conversion — `DateTime.toLocal` in the
/// app, a fixed offset in a test. A function and not a bare offset, because a
/// fixed offset is wrong across a daylight-saving change: the same wall clock
/// is a different offset in March and in July.
library;

import '../shared/ids.dart';
import '../wardrobe/model/lifecycle.dart';
import '../wardrobe/model/wardrobe_item.dart';
import 'wardrobe_event.dart';

/// Turns an instant into the wall-clock time the person saw.
///
/// Only the year, month, day, hour and so on of the result are read; whether
/// it is flagged UTC or local is not.
typedef LocalClock = DateTime Function(DateTime instant);

DateTime _deviceLocal(DateTime instant) => instant.toLocal();

/// A calendar day with no time and no zone: "the 14th of March".
///
/// Not a `DateTime` at midnight, because that is a moment, and moments are what
/// move when a zone does. Two people in different zones who wore something on
/// "March 14th" agree about the day and disagree about the instant, and this is
/// the thing they agree about.
final class CalendarDate implements Comparable<CalendarDate> {
  const CalendarDate(this.year, this.month, this.day);

  /// The day [wallClock] falls on. Read as written: no conversion is applied.
  CalendarDate.of(DateTime wallClock)
      : this(wallClock.year, wallClock.month, wallClock.day);

  final int year;
  final int month;
  final int day;

  /// The day after this one, across month and year ends.
  CalendarDate get next {
    final following = DateTime.utc(year, month, day + 1);
    return CalendarDate(following.year, following.month, following.day);
  }

  /// How many days the month this falls in has.
  static int daysIn(int year, int month) =>
      DateTime.utc(year, month + 1, 0).day;

  /// Monday is 1 and Sunday is 7, as in [DateTime.weekday].
  int get weekday => DateTime.utc(year, month, day).weekday;

  @override
  int compareTo(CalendarDate other) => year != other.year
      ? year.compareTo(other.year)
      : month != other.month
          ? month.compareTo(other.month)
          : day.compareTo(other.day);

  bool isBefore(CalendarDate other) => compareTo(other) < 0;

  bool isAfter(CalendarDate other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is CalendarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  /// `2026-03-04`, which sorts as text and reads the same in every locale.
  @override
  String toString() => '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

/// One garment on one day.
final class WornPiece {
  const WornPiece({
    required this.itemId,
    required this.item,
    required this.firstWornAt,
    this.times = 1,
  });

  final ItemId itemId;

  /// The garment, or null when it no longer exists.
  ///
  /// A deleted garment is a tombstone in the store and its wears stay in the
  /// log. The day is kept, because the day happened: what is lost is the
  /// ability to show or open the piece, and the screen says so rather than
  /// letting the outfit quietly look one piece smaller.
  final WardrobeItem? item;

  /// When it was first worn that day, for ordering the pieces of an outfit.
  final DateTime firstWornAt;

  /// How many times it was logged that day. A garment put on twice is one
  /// piece of the day's outfit, and a second tap is not a second garment.
  final int times;

  bool get isMissing => item == null;
}

/// Everything worn on one day.
final class WearDay {
  const WearDay({required this.date, required this.pieces});

  final CalendarDate date;

  /// Each garment once, in the order it was first logged that day.
  final List<WornPiece> pieces;

  /// The pieces that can still be shown and opened.
  List<WornPiece> get present => [
        for (final piece in pieces)
          if (!piece.isMissing) piece,
      ];

  /// How many logged garments are gone from the wardrobe.
  int get missingCount => pieces.length - present.length;
}

/// The month at a glance, for the line above the grid.
final class MonthSummary {
  const MonthSummary({
    required this.daysLogged,
    this.mostWorn,
    this.mostWornDays = 0,
  });

  /// Days in the month with at least one wear.
  final int daysLogged;

  /// The garment worn on the most different days, or null when nothing was
  /// worn on more than one.
  ///
  /// Null rather than an arbitrary winner of a tie at one. "Most worn: the
  /// first thing you happened to log" is not a finding, and a month with a
  /// single wear of everything has no favourite to name. A garment that has
  /// since been deleted is never named: the line points at something the person
  /// can open.
  final WardrobeItem? mostWorn;

  /// On how many days [mostWorn] was worn.
  final int mostWornDays;
}

/// What was worn when, indexed by day.
final class WearCalendar {
  WearCalendar._(this._days);

  /// Groups the wears in [events] by the day they fell on locally.
  ///
  /// Only [ItemWorn] is read, so a whole log can be passed in. [items] resolves
  /// ids to garments; an id it does not hold, or holds as
  /// [LifecycleState.removed], is a missing piece. Sold, donated and lost
  /// garments are still garments: the day they were worn in is history, and
  /// leaving them out would rewrite it.
  ///
  /// [toLocal] defaults to the device's own zone.
  factory WearCalendar.fromEvents(
    Iterable<WardrobeEvent> events, {
    Iterable<WardrobeItem> items = const [],
    LocalClock toLocal = _deviceLocal,
  }) {
    final byId = {for (final item in items) item.id: item};
    final wears = <ItemWorn>[
      for (final event in events)
        if (event is ItemWorn) event,
    ]..sort((x, y) => x.occurredAt.compareTo(y.occurredAt));

    final grouped = <CalendarDate, Map<ItemId, _Tally>>{};
    for (final wear in wears) {
      final date = CalendarDate.of(toLocal(wear.occurredAt));
      final tallies = grouped.putIfAbsent(date, () => {});
      final tally = tallies[wear.itemId];
      if (tally == null) {
        tallies[wear.itemId] = _Tally(wear.occurredAt);
      } else {
        tally.times++;
      }
    }

    return WearCalendar._({
      for (final MapEntry(key: date, value: tallies) in grouped.entries)
        date: WearDay(
          date: date,
          // Map iteration is insertion order, and insertion followed the sort
          // above, so this is already the order they were first logged in.
          pieces: [
            for (final MapEntry(key: id, value: tally) in tallies.entries)
              WornPiece(
                itemId: id,
                item: _live(byId[id]),
                firstWornAt: tally.firstAt,
                times: tally.times,
              ),
          ],
        ),
    });
  }

  static WardrobeItem? _live(WardrobeItem? item) =>
      item == null || item.lifecycle == LifecycleState.removed ? null : item;

  final Map<CalendarDate, WearDay> _days;

  bool get isEmpty => _days.isEmpty;

  /// The day's wears, or null when nothing was logged.
  WearDay? on(CalendarDate date) => _days[date];

  /// The days of one month that have wears, in date order.
  List<WearDay> inMonth(int year, int month) => [
        for (final day in _days.values)
          if (day.date.year == year && day.date.month == month) day,
      ]..sort((x, y) => x.date.compareTo(y.date));

  /// The earliest day with a wear, or null for an empty history. Where the
  /// calendar stops letting someone page back.
  CalendarDate? get firstDay => _days.keys.isEmpty
      ? null
      : _days.keys.reduce((a, b) => a.isBefore(b) ? a : b);

  /// Days logged and the favourite, for [month] of [year].
  MonthSummary summaryFor(int year, int month) {
    final days = inMonth(year, month);
    final counts = <ItemId, int>{};
    final garments = <ItemId, WardrobeItem>{};
    for (final day in days) {
      for (final piece in day.present) {
        // Pieces are unique within a day, so this counts days, not wears.
        counts[piece.itemId] = (counts[piece.itemId] ?? 0) + 1;
        garments[piece.itemId] = piece.item!;
      }
    }

    ItemId? best;
    for (final entry in counts.entries) {
      final leads = best == null ||
          entry.value > counts[best]! ||
          // Ties go to the lower id, so the answer does not depend on which
          // day happened to be folded first.
          (entry.value == counts[best] &&
              entry.key.value.compareTo(best.value) < 0);
      if (leads) best = entry.key;
    }

    final leadDays = best == null ? 0 : counts[best]!;
    return MonthSummary(
      daysLogged: days.length,
      mostWorn: leadDays >= 2 ? garments[best] : null,
      mostWornDays: leadDays >= 2 ? leadDays : 0,
    );
  }
}

class _Tally {
  _Tally(this.firstAt);

  final DateTime firstAt;
  int times = 1;
}
