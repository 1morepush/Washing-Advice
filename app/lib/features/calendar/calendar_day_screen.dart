/// One day of the calendar: what was worn, large enough to recognise.
///
/// Each piece opens its garment's page. Two things can be done with the day,
/// and both reuse what the app already does rather than a second way of doing
/// it: "Wore this again today" records the pieces through the same path as
/// "Wearing this" on an outfit idea — the wear, and the move to the basket —
/// and "Save as an outfit" asks for a name the way saving an idea does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/theme.dart';
import '../../widgets/back_navigation.dart';
import '../../widgets/item_thumbnail.dart';
import '../../widgets/photo_viewer.dart';
import '../../widgets/rinse_kit.dart';
import '../../widgets/state_view.dart';
import '../../widgets/status_message.dart';
import '../outfits/outfit_controller.dart';
import '../sell/list/listing_clock.dart';
import '../outfits/saved_outfits.dart' show askForOutfitName;
import 'calendar_providers.dart';
import 'calendar_words.dart';

class CalendarDayScreen extends ConsumerWidget {
  const CalendarDayScreen({required this.slug, super.key});

  /// The address's day, `2026-03-04`. Kept as text so a malformed link can be
  /// told so instead of being parsed away before the screen sees it.
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = parseDateSlug(slug);
    final today = ref.watch(calendarTodayProvider);

    return Scaffold(
      appBar: AppBar(
        leading: backLeading(context, '/calendar'),
        title: AppBarTitle(
          date == null ? 'Calendar' : dayTitle(date, relativeTo: today),
        ),
      ),
      body: date == null
          ? const EmptyView(
              icon: Icons.event_busy_outlined,
              title: 'That is not a date',
              message: 'The calendar has no day by that name.',
            )
          : ref
                .watch(wearCalendarProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) => StatusMessage.failure(
                    title: 'Could not load this day',
                    error: error,
                  ),
                  data: (calendar) {
                    final day = calendar.on(date);
                    return day == null
                        ? _NothingThisDay(date: date)
                        : _Day(day: day, isToday: date == today);
                  },
                ),
    );
  }
}

class _NothingThisDay extends StatelessWidget {
  const _NothingThisDay({required this.date});

  final CalendarDate date;

  @override
  Widget build(BuildContext context) => EmptyView(
    icon: Icons.calendar_today_outlined,
    title: 'Nothing logged',
    message: 'No wears are on record for this day.',
    action: OutlinedButton(
      onPressed: () => context.backOr('/calendar'),
      child: const Text('Back to the calendar'),
    ),
  );
}

class _Day extends ConsumerWidget {
  const _Day({required this.day, required this.isToday});

  final WearDay day;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final present = day.present;
    // Only what is still owned can be put on again. A jumper sold in the spring
    // is part of the day it was worn and not part of tonight's.
    final wearable = [
      for (final piece in present)
        if (piece.item!.lifecycle.isOwned) piece.item!,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        Text(
          day.pieces.length == 1
              ? '1 piece worn'
              : '${day.pieces.length} pieces worn',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        _Pieces(pieces: day.pieces),
        const SizedBox(height: 20),
        // Not on today itself: those pieces are already logged, and the same
        // button there would log them a second time.
        if (!isToday && wearable.isNotEmpty)
          FilledButton.icon(
            onPressed: () => _wearAgain(context, ref, wearable),
            icon: const Icon(Icons.checkroom_outlined),
            label: const Text('Wore this again today'),
          ),
        if (present.length >= 2) ...[
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () =>
                _save(context, ref, [for (final piece in present) piece.item!]),
            icon: const Icon(Icons.bookmark_border),
            label: const Text('Save as an outfit'),
          ),
        ],
      ],
    );
  }

  /// The same two things "Wearing this" does on an outfit idea, and the
  /// confirmation the Worn today flow gives.
  Future<void> _wearAgain(
    BuildContext context,
    WidgetRef ref,
    List<WardrobeItem> items,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    // Stamped with the app's clock, the one that decided what "today" is on
    // this screen, so the wear lands on the day the calendar thinks it is.
    await ref.read(outfitControllerProvider).wearItems([
      for (final item in items) item.id,
    ], at: ref.read(listingClockProvider)());
    ref.invalidate(wearCalendarProvider);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            items.length == 1
                ? '1 garment in the basket. Logged as worn today, and ready '
                      'for the next wash.'
                : '${items.length} garments in the basket. Logged as worn '
                      'today, and ready for the next wash.',
          ),
        ),
      );
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    List<WardrobeItem> items,
  ) async {
    final name = await askForOutfitName(
      context,
      title: 'Save this outfit',
      initial: 'Worn ${day.date.day} ${monthNames[day.date.month - 1]}',
    );
    if (name == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final saved = await ref
        .read(outfitControllerProvider)
        .saveItems(items, name: name, occasion: Occasion.everyday);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Saved as ${saved.name}.')));
  }
}

/// The pieces two to a row, sized from the width so that a large text size
/// makes the cards taller and not wider than the screen.
class _Pieces extends StatelessWidget {
  const _Pieces({required this.pieces});

  final List<WornPiece> pieces;

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - _gap) / 2;
      return Wrap(
        spacing: _gap,
        runSpacing: 16,
        children: [
          for (final piece in pieces)
            SizedBox(
              width: width,
              child: piece.item == null
                  ? const _GonePiece()
                  : _Piece(item: piece.item!, times: piece.times),
            ),
        ],
      );
    },
  );
}

class _Piece extends StatelessWidget {
  const _Piece({required this.item, required this.times});

  final WardrobeItem item;
  final int times;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Semantics(
      button: true,
      label: item.displayName,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => context.push('/item/${item.id.value}'),
        borderRadius: context.rinse.tileBorderRadius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: EnlargeOnTap(
                item: item,
                onLongPress: true,
                // A measured size, not `double.infinity`: a garment with no
                // photograph is drawn as a silhouette, and given an unbounded
                // size that draws smaller than a photographed neighbour.
                child: LayoutBuilder(
                  builder: (_, box) =>
                      ItemThumbnail(item: item, size: box.maxWidth),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(item.type.value.label, style: quiet),
            // Said in words, so a piece that is no longer owned is not mistaken
            // for one that can be put on again.
            if (!item.lifecycle.isOwned)
              Text(item.lifecycle.label, style: quiet),
            if (times > 1) Text('Worn $times times', style: quiet),
          ],
        ),
      ),
    );
  }
}

/// A garment that was worn this day and has since been deleted.
class _GonePiece extends StatelessWidget {
  const _GonePiece();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: GarmentWell(
            child: Center(
              child: Icon(
                Icons.checkroom_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'No longer in your wardrobe',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          'Worn this day, then deleted.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
