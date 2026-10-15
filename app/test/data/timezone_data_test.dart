/// The time zone data a reminder is scheduled against.
///
/// `LocalNudges` loads the ten-year database rather than the full history. A
/// reminder only ever looks forward, so what matters is that today's rules
/// are in it and daylight saving is applied.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('zones are present and observe daylight saving', () {
    final london = tz.getLocation('Europe/London');
    expect(tz.TZDateTime(london, 2026, 7, 1).timeZoneOffset.inHours, 1);
    expect(tz.TZDateTime(london, 2026, 12, 1).timeZoneOffset.inHours, 0);

    final auckland = tz.getLocation('Pacific/Auckland');
    expect(tz.TZDateTime(auckland, 2027, 1, 15).timeZoneOffset.inHours, 13);
  });
}
