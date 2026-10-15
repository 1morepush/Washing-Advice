/// Finding the zone a reminder is scheduled in.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:washing_advice/data/notifications/local_nudges.dart';

void main() {
  test(
    'a database that will not load falls back to UTC, and says so',
    () async {
      final (location, complete) = await LocalNudges.findLocation(
        loadDatabase: () => throw StateError('corrupt'),
        zoneId: () async => 'Europe/London',
      );

      expect(location, tz.UTC);
      expect(complete, isFalse, reason: 'so the next schedule tries again');
    },
  );

  test('a working lookup is complete', () async {
    final (location, complete) = await LocalNudges.findLocation(
      zoneId: () async => 'Europe/London',
    );

    expect(location.name, 'Europe/London');
    expect(complete, isTrue);
  });
}
