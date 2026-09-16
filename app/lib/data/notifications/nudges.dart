/// Reminders that arrive when the app is closed.
///
/// A port rather than a direct plugin call, because the thing behind it is a
/// platform plugin three times over: it cannot run in a test, it does not
/// exist on the web — no browser can schedule a notification for later — and
/// what the app needs from it is small enough to state in an interface. The
/// one thing the app schedules is an evening question, and the one thing it
/// needs back is which screen a tap was for.
library;

/// Somewhere to put a reminder for later.
abstract interface class Nudges {
  /// Whether this platform can schedule one at all.
  ///
  /// False on the web, and on a phone where the plugin failed to start. The
  /// settings screen reads this to say so rather than offer a switch that
  /// does nothing.
  bool get isSupported;

  /// Asks the person, on the platforms that ask.
  ///
  /// False means they said no, and the caller should leave the reminder off
  /// and say why — scheduling anyway would silently never fire.
  Future<bool> requestPermission();

  /// Shows [title] and [body] at [firstAt], and every day after at the same
  /// time of day. Tapping it opens [route].
  ///
  /// There is one daily reminder, so scheduling again replaces it.
  Future<void> scheduleDaily({
    required DateTime firstAt,
    required String title,
    required String body,
    required String route,
  });

  Future<void> cancel();

  /// The route the app was opened for, when a reminder opened it.
  ///
  /// Read once, before the first frame, so a tap on a closed app lands on
  /// the screen it was for rather than on the wardrobe with a redirect after.
  Future<String?> launchRoute();

  /// Routes to open, one per reminder tapped while the app is running.
  Stream<String> get taps;
}

/// Nowhere to put one.
///
/// The web, where the platform cannot do it, and a phone where the plugin
/// could not be started. Everything is a no-op, and [isSupported] says so, so
/// the app behaves as though the feature is absent rather than broken.
final class NoNudges implements Nudges {
  const NoNudges();

  @override
  bool get isSupported => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> scheduleDaily({
    required DateTime firstAt,
    required String title,
    required String body,
    required String route,
  }) async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<String?> launchRoute() async => null;

  @override
  Stream<String> get taps => const Stream.empty();
}
