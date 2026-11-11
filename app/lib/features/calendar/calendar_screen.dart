/// The outfit calendar: what you wore, a month at a time.
///
/// Every day with a wear on record shows small pictures of the garments, so a
/// month reads like a row of mirrors and a gap is a day nobody logged. Tapping
/// a day opens it. Nothing here is computed: the grouping into days, and the
/// "days logged" and favourite lines, are the core's `WearCalendar`.
///
/// The grid is drawn by hand. A calendar package would bring its own idea of a
/// day cell, and what goes in this one — a handful of garment thumbnails that
/// must stay legible at 320 wide and at a text size 60% over normal — is the
/// whole design.
///
/// Paging stops at the current month, because the future has no wears, and at
/// the month of the first one, because before that there is nothing to see and
/// an endless back button invites someone to page into years of blank grids.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/theme.dart';
import '../../widgets/back_navigation.dart';
import '../../widgets/item_thumbnail.dart';
import '../../widgets/rinse_kit.dart';
import '../../widgets/state_view.dart';
import '../../widgets/status_message.dart';
import 'calendar_providers.dart';
import 'calendar_words.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  /// The month being looked at, as the first of it. Null until the first build
  /// has said what today is.
  ({int year, int month})? _shown;

  @override
  Widget build(BuildContext context) {
    final calendar = ref.watch(wearCalendarProvider);
    final today = ref.watch(calendarTodayProvider);
    final shown = _shown ?? (year: today.year, month: today.month);

    return Scaffold(
      appBar: AppBar(
        leading: backLeading(context, '/more'),
        title: const Text('Calendar'),
      ),
      body: calendar.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StatusMessage.failure(
          title: 'Could not load your calendar',
          error: error,
        ),
        data: (data) => data.isEmpty
            ? const _NothingLoggedYet()
            : _Month(
                calendar: data,
                today: today,
                year: shown.year,
                month: shown.month,
                onMove: (year, month) =>
                    setState(() => _shown = (year: year, month: month)),
              ),
      ),
    );
  }
}

/// A whole-number month index, so months compare and step like numbers.
int _index(int year, int month) => year * 12 + month - 1;

class _Month extends StatelessWidget {
  const _Month({
    required this.calendar,
    required this.today,
    required this.year,
    required this.month,
    required this.onMove,
  });

  final WearCalendar calendar;
  final CalendarDate today;
  final int year;
  final int month;
  final void Function(int year, int month) onMove;

  @override
  Widget build(BuildContext context) {
    final here = _index(year, month);
    final last = _index(today.year, today.month);
    final firstDay = calendar.firstDay;
    final first = firstDay == null
        ? last
        : _index(firstDay.year, firstDay.month);

    void step(int by) {
      final target = here + by;
      onMove(target ~/ 12, target % 12 + 1);
    }

    final summary = calendar.summaryFor(year, month);
    final days = {for (final d in calendar.inMonth(year, month)) d.date: d};

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _MonthBar(
          title: monthTitle(year, month),
          onPrevious: here > first ? () => step(-1) : null,
          onNext: here < last ? () => step(1) : null,
        ),
        const SizedBox(height: 8),
        _Summary(summary: summary, month: month),
        const SizedBox(height: 16),
        const _WeekdayRow(),
        const SizedBox(height: 4),
        _Grid(year: year, month: month, today: today, days: days),
      ],
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.title,
    required this.onPrevious,
    required this.onNext,
  });

  final String title;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next month',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

/// Days logged, and the garment worn on the most of them.
class _Summary extends StatelessWidget {
  const _Summary({required this.summary, required this.month});

  final MonthSummary summary;
  final int month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = monthNames[month - 1];
    final logged = summary.daysLogged;
    final favourite = summary.mostWorn;

    return InsetPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            logged == 0
                ? 'Nothing logged in $name'
                : logged == 1
                ? '1 day logged in $name'
                : '$logged days logged in $name',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (favourite != null) ...[
            const SizedBox(height: 4),
            Text(
              'Most worn: ${favourite.displayName}, on '
              '${summary.mostWornDays} days',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w800,
    );
    return Row(
      children: [
        for (final name in weekdayNames)
          Expanded(
            child: Semantics(
              label: name,
              excludeSemantics: true,
              child: Text(
                name.substring(0, 1),
                textAlign: TextAlign.center,
                style: style,
              ),
            ),
          ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.year,
    required this.month,
    required this.today,
    required this.days,
  });

  final int year;
  final int month;
  final CalendarDate today;
  final Map<CalendarDate, WearDay> days;

  @override
  Widget build(BuildContext context) {
    final lead = CalendarDate(year, month, 1).weekday - 1;
    final length = CalendarDate.daysIn(year, month);
    final cells = lead + length;
    final rows = (cells / 7).ceil();

    return Column(
      children: [
        for (var row = 0; row < rows; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(child: _cell(row * 7 + col - lead + 1, length)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(int day, int length) {
    // Outside the month: the same height as a day, so a short last week does
    // not change where the rows fall.
    if (day < 1 || day > length) return const _DayCell.blank();
    final date = CalendarDate(year, month, day);
    return _DayCell(date: date, today: date == today, wear: days[date]);
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.date, required this.today, required this.wear});

  const _DayCell.blank() : date = null, today = false, wear = null;

  final CalendarDate? date;
  final bool today;
  final WearDay? wear;

  @override
  Widget build(BuildContext context) {
    final date = this.date;
    final number = date == null
        ? const SizedBox.shrink()
        : _Number(day: date.day, today: today, quiet: wear == null);

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The number's own box is as tall as the largest text the phone
        // allows, so a ringed today does not push its row apart.
        SizedBox(
          height: _numberHeight(context),
          child: Center(child: number),
        ),
        AspectRatio(
          aspectRatio: 1,
          child: wear == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.all(1),
                  child: _Thumbs(day: wear!),
                ),
        ),
      ],
    );

    final day = wear;
    if (date == null || day == null) {
      return Semantics(
        label: date == null
            ? null
            : '${dayTitle(date)}${today ? ', today' : ''}, nothing logged',
        excludeSemantics: true,
        child: Padding(padding: const EdgeInsets.all(2), child: body),
      );
    }

    return Semantics(
      button: true,
      excludeSemantics: true,
      label:
          '${dayTitle(date)}${today ? ', today' : ''}: '
          '${day.pieces.length} '
          '${day.pieces.length == 1 ? 'piece' : 'pieces'} worn, '
          '${[for (final p in day.present) p.item!.displayName].join(', ')}',
      child: InkWell(
        borderRadius: context.rinse.tileBorderRadius,
        onTap: () => context.push('/calendar/${dateSlug(date)}'),
        child: Padding(padding: const EdgeInsets.all(2), child: body),
      ),
    );
  }

  static double _numberHeight(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(12) + 10;
}

class _Number extends StatelessWidget {
  const _Number({required this.day, required this.today, required this.quiet});

  final int day;
  final bool today;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = Text(
      '$day',
      maxLines: 1,
      style: theme.textTheme.labelMedium?.copyWith(
        fontWeight: today ? FontWeight.w800 : FontWeight.w600,
        color: today
            ? scheme.onPrimary
            : quiet
            ? scheme.onSurfaceVariant
            : scheme.onSurface,
      ),
    );
    if (!today) return text;
    // Today is the one filled number: a mark that survives all three themes
    // without a colour of its own, and that is not colour alone — the day is
    // also called "today" to a screen reader.
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        child: text,
      ),
    );
  }
}

/// Up to three garments, and "+N" for the rest.
class _Thumbs extends StatelessWidget {
  const _Thumbs({required this.day});

  final WearDay day;

  @override
  Widget build(BuildContext context) {
    final pieces = day.pieces;
    if (pieces.length == 1) return _Mini(piece: pieces.single);

    final extra = pieces.length - 3;
    final slots = <Widget>[
      for (final piece in pieces.take(3)) _Mini(piece: piece),
      if (extra > 0) _More(count: extra),
    ];
    // A two-by-two, whatever it holds: empty slots keep the pictures the same
    // size on a day with two garments as on one with five.
    while (slots.length < 4) {
      slots.add(const SizedBox.shrink());
    }

    return Column(
      children: [
        for (var row = 0; row < 2; row++)
          Expanded(
            child: Row(
              children: [
                for (var col = 0; col < 2; col++)
                  Expanded(child: slots[row * 2 + col]),
              ],
            ),
          ),
      ],
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.piece});

  final WornPiece piece;

  @override
  Widget build(BuildContext context) {
    final item = piece.item;
    return Padding(
      padding: const EdgeInsets.all(1),
      child: item == null
          ? GarmentWell(child: const SizedBox.expand())
          : LayoutBuilder(
              // Measured, for the reason the day screen gives: the garment is
              // drawn to fit the tile and not to a fraction of an unbounded one.
              builder: (_, box) =>
                  ItemThumbnail(item: item, size: box.biggest.shortestSide),
            ),
    );
  }
}

class _More extends StatelessWidget {
  const _More({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        '+$count',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
  );
}

/// A wardrobe with no wears on record: what the calendar is, and how it fills.
class _NothingLoggedYet extends StatelessWidget {
  const _NothingLoggedYet();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: EmptyView(
      icon: Icons.calendar_month_outlined,
      title: 'No outfits logged yet',
      message:
          'Each day you record what you wore shows up here. Tap “Wore it” on '
          'a garment’s page, use “Worn today” in Laundry when you put clothes '
          'in the basket, or choose “Wearing this” on an outfit idea.',
      action: FilledButton.icon(
        onPressed: () => context.push('/laundry/worn'),
        icon: const Icon(Icons.checkroom_outlined),
        label: const Text('Log what you wore today'),
      ),
    ),
  );
}
