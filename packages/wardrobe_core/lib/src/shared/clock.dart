/// An injectable source of "now".
///
/// The domain records timestamps on every event, so time is a dependency. Tests
/// inject a fixed clock and get deterministic assertions instead of tolerance
/// windows.
library;

/// Supplies the current instant.
abstract interface class Clock {
  DateTime now();
}

/// Reads the real system clock, in UTC.
///
/// UTC throughout: wardrobe data syncs across devices and timezones, and
/// storing local times makes "washed yesterday" ambiguous after travel.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

/// A clock that returns whatever the test tells it to.
final class FixedClock implements Clock {
  FixedClock(this._instant);

  DateTime _instant;

  /// Moves the clock forward, for testing sequences of dated events.
  void advance(Duration by) => _instant = _instant.add(by);

  /// Jumps the clock to an exact instant.
  void set(DateTime instant) => _instant = instant;

  @override
  DateTime now() => _instant;
}
