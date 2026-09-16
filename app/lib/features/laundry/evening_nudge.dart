/// A question at the end of the day: "What did you wear today?"
///
/// 0.27.0 built the screen that answers it in three taps. What it could not
/// do was get anyone *to* the screen: the information exists for about a
/// minute, between taking clothes off and them landing in a heap, and an app
/// that has to be remembered and opened in that minute is not opened. This is
/// the other half — a notification at a time you choose, whose tap is the
/// screen.
///
/// The time is stored as minutes after midnight, in the same preferences as
/// every other setting, and the platform's schedule is re-stated from that on
/// every launch rather than trusted: an update, a cleared app or a plugin
/// that forgot are all things that happen, and the stored time is the only
/// copy that is the person's own decision.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../data/notifications/nudges.dart';

/// A time of day, in the person's own clock.
final class NudgeTime {
  const NudgeTime({required this.hour, required this.minute})
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  /// From minutes after midnight, which is how it is stored.
  factory NudgeTime.fromMinutes(int minutes) =>
      NudgeTime(hour: minutes ~/ 60, minute: minutes % 60);

  /// Half past eight in the evening. Home from work, changed, and before the
  /// point in the evening when nothing more gets done.
  static const defaultEvening = NudgeTime(hour: 20, minute: 30);

  final int hour;
  final int minute;

  int get minutes => hour * 60 + minute;

  /// The next time this comes round, strictly after [now].
  ///
  /// Strictly: a reminder set for the current minute is for tomorrow, not
  /// for a notification that fires the instant the switch is flipped.
  DateTime next(DateTime now) {
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    return today.isAfter(now)
        ? today
        : DateTime(now.year, now.month, now.day + 1, hour, minute);
  }

  @override
  bool operator ==(Object other) =>
      other is NudgeTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() =>
      'NudgeTime(${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')})';
}

/// What the evening reminder says, and where a tap on it goes.
///
/// Named once, here, because two places would drift — and the route is the
/// contract with the router, which a test pins.
const eveningNudge = (
  title: 'What did you wear today?',
  body: 'Tap what you had on and it goes in the basket. Three taps, no photo.',
  route: '/laundry/worn',
);

/// Makes the platform's schedule match the setting.
final class NudgeScheduler {
  const NudgeScheduler(this._nudges);

  final Nudges _nudges;

  /// Scheduled at [time], or not at all when it is null.
  ///
  /// Idempotent, which is what lets `main()` call it on every launch: there
  /// is one reminder, and stating it again replaces rather than duplicates.
  Future<void> apply(NudgeTime? time, {DateTime? now}) async {
    if (!_nudges.isSupported) return;
    if (time == null) {
      await _nudges.cancel();
      return;
    }
    await _nudges.scheduleDaily(
      firstAt: time.next(now ?? DateTime.now()),
      title: eveningNudge.title,
      body: eveningNudge.body,
      route: eveningNudge.route,
    );
  }
}

/// The stored reminder time, or null when it is off.
NudgeTime? nudgeTimeOf(SettingsStore settings) =>
    switch (settings.nudgeMinutes) {
      final int minutes => NudgeTime.fromMinutes(minutes),
      null => null,
    };

/// Where reminders go. Overridden in `main()` with the platform's own on a
/// phone; the default is the web's answer, and every test's.
final nudgesProvider = Provider<Nudges>((ref) => const NoNudges());

/// The reminder time, as state so the settings screen rebuilds on change.
final nudgeTimeProvider = StateProvider<NudgeTime?>(
  (ref) => nudgeTimeOf(ref.watch(settingsStoreProvider)),
);

final nudgeSchedulerProvider = Provider<NudgeScheduler>(
  (ref) => NudgeScheduler(ref.watch(nudgesProvider)),
);
