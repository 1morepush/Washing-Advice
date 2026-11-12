/// What the calendar reads.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../sell/list/listing_clock.dart';

/// Every wear in the log, grouped by the day it fell on where the person is.
///
/// Rebuilt whenever the wardrobe changes. Recording a wear saves the garment
/// (the cached counters move with it), so watching the owned items is what
/// makes a wear logged from anywhere in the app appear here without this
/// screen being told. The log itself is the source; the items are only read to
/// put faces on its ids.
///
/// The garments are looked up by id rather than taken from the owned list,
/// because a calendar is history: a jumper sold in the spring was still worn
/// on the days it was worn, and an owned-only list would turn those days into
/// gaps.
final wearCalendarProvider = FutureProvider<WearCalendar>((ref) async {
  // Only for the dependency: see above.
  ref.watch(ownedItemsProvider);

  final events = await ref.watch(eventLogProvider).all(types: {wornEventType});
  final items = await ref.watch(wardrobeRepositoryProvider).byIds({
    for (final event in events) event.itemId,
  });
  return WearCalendar.fromEvents(events, items: items);
});

/// Today, as a calendar day where the person is.
///
/// Read through the app's one clock so a test can say what day it is.
final calendarTodayProvider = Provider<CalendarDate>(
  (ref) => CalendarDate.of(ref.watch(listingClockProvider)().toLocal()),
);
