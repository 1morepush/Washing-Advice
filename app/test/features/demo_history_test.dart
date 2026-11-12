/// The demo build has something to show on the calendar and in the suggestion.
///
/// The screenshots are taken from the demo, so a calendar that opens on an
/// empty month or a suggestion with nothing to suggest would quietly photograph
/// the wrong screen.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/main_demo.dart';

void main() {
  final today = DateTime(2026, 11, 11, 12);
  final wardrobe = demoWardrobe();

  test('two months of wears, with gaps and a day of four pieces', () {
    final calendar = WearCalendar.fromEvents(
      demoWearHistory(now: today),
      items: wardrobe,
    );

    final thisMonth = calendar.inMonth(2026, 11);
    final lastMonth = calendar.inMonth(2026, 10);
    expect(thisMonth, isNotEmpty);
    expect(lastMonth.length, greaterThan(15));
    expect(lastMonth.length, lessThan(31));
    expect(
      [...thisMonth, ...lastMonth].any((day) => day.pieces.length == 4),
      isTrue,
    );
    // Every worn garment is one the demo wardrobe has.
    expect(
      [
        for (final day in [...thisMonth, ...lastMonth]) day.missingCount,
      ].every((missing) => missing == 0),
      isTrue,
    );
    expect(calendar.summaryFor(2026, 10).mostWorn, isNotNull);
  });

  test('nothing is dated in the future', () {
    final latest = demoWearHistory(
      now: today,
    ).map((event) => event.occurredAt).reduce((a, b) => a.isAfter(b) ? a : b);
    expect(latest.isBefore(today), isTrue);
  });

  test('two garments have gone a year unworn', () {
    final candidates = letGoCandidates(wardrobe, now: today);
    // The boots were never worn and came first, so they lead.
    expect(candidates.map((c) => c.item.id.value), [
      'demo-boots',
      'demo-cardigan',
    ]);
    expect(candidates.first.neverWorn, isTrue);
  });
}
