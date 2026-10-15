/// [Nudges] over the platform's own notifications, on a phone.
///
/// One scheduled notification, repeated daily by the operating system, which
/// keeps firing whether or not the app is ever opened again — the property
/// that matters, because a reminder that has to be re-armed by the app is one
/// that stops the first evening it is ignored.
///
/// Scheduled *inexactly*. Android 14 stopped granting exact alarms by default,
/// and the difference between 20:30 and 20:34 is nothing to a reminder that
/// says "sometime this evening"; exactness would cost a permission prompt
/// that reads as an alarm clock asking for control.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
// The ten-year database: today's rules for every zone, about a sixth of the
// size of the full history, and a reminder only ever looks forward.
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'nudges.dart';

final class LocalNudges implements Nudges {
  LocalNudges._(this._plugin);

  /// The one daily reminder. A fixed id is what makes scheduling again
  /// replace it rather than pile up a second.
  static const _id = 1;

  /// The status-bar icon, a drawable in `android/app/src/main/res`.
  ///
  /// Not the launcher icon. Android draws this as a silhouette from its
  /// alpha channel alone, so a full-colour icon becomes a white square; and
  /// it is looked up by name, so `res/raw/keep.xml` has to stop a release
  /// build stripping it. A test holds the name, the file and the keep rule
  /// together.
  static const androidIcon = 'ic_stat_nudge';

  static const _channel = AndroidNotificationDetails(
    'evening-nudge',
    'Evening reminder',
    channelDescription: 'Asks what you wore today, once a day.',
    icon: androidIcon,
  );

  final FlutterLocalNotificationsPlugin _plugin;

  /// Where "half past eight in the evening" is, found the first time a
  /// reminder is scheduled rather than at startup.
  ///
  /// The daily repeat matches the time of day in *this* zone, so it has to
  /// be the phone's real one: scheduled in UTC, a reminder set for 20:30
  /// would move by an hour every time the clocks changed.
  ///
  /// Lazy because opening the store used to parse the time zone database
  /// before the first frame, for a reminder that a launch with the setting
  /// off never schedules, and that one that does schedule it does not wait
  /// for. Cancelling needs no zone at all.
  Future<tz.Location> _locate() async {
    if (_location case final tz.Location known) return known;
    final (location, complete) = await findLocation();
    // A fallback is used but not kept, so a later schedule tries again.
    if (complete) _location = location;
    return location;
  }

  tz.Location? _location;

  /// Loads the database and finds the phone's zone, or falls back to UTC.
  ///
  /// `complete` is false when anything failed, including the database itself
  /// not loading. UTC keeps the reminder firing; only the clock-change drift
  /// is lost. [loadDatabase] and [zoneId] are seams for a test.
  @visibleForTesting
  static Future<(tz.Location, bool)> findLocation({
    void Function() loadDatabase = tzdata.initializeTimeZones,
    Future<String> Function() zoneId = _deviceZone,
  }) async {
    var location = tz.UTC;
    var complete = true;
    try {
      loadDatabase();
      location = tz.getLocation(await zoneId());
    } on Object {
      // A zone the database does not know, a platform that would not say, or
      // a database that would not load.
      complete = false;
    }
    tz.setLocalLocation(location);
    return (location, complete);
  }

  static Future<String> _deviceZone() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;

  final _taps = StreamController<String>.broadcast();

  /// Starts the plugin and finds the local time zone.
  ///
  /// Throws if the platform refuses, which `main()` turns into [NoNudges]:
  /// a phone whose notifications cannot be set up still has a wardrobe.
  static Future<LocalNudges> open() async {
    final plugin = FlutterLocalNotificationsPlugin();
    final nudges = LocalNudges._(plugin);
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(androidIcon),
        // Not asked for at startup. Permission is requested when the switch
        // is turned on, which is the moment the question makes sense.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: nudges._onTap,
    );
    return nudges;
  }

  void _onTap(NotificationResponse response) {
    if (response.payload case final String route when route.isNotEmpty) {
      _taps.add(route);
    }
  }

  @override
  bool get isSupported => true;

  @override
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      // Null on Android 12 and older, where there is no permission to ask
      // for and notifications are simply allowed.
      return await android.requestNotificationsPermission() ?? true;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    // A desktop. Nothing to ask.
    return true;
  }

  @override
  Future<void> scheduleDaily({
    required DateTime firstAt,
    required String title,
    required String body,
    required String route,
  }) async {
    final location = await _locate();
    await _plugin.zonedSchedule(
      id: _id,
      title: title,
      body: body,
      payload: route,
      // The same instant, expressed in the phone's zone, so the daily match on
      // time of day is a match on the wall clock the person set.
      scheduledDate: tz.TZDateTime.from(firstAt, location),
      notificationDetails: const NotificationDetails(
        android: _channel,
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> cancel() => _plugin.cancel(id: _id);

  @override
  Future<String?> launchRoute() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    final route = details.notificationResponse?.payload;
    return route == null || route.isEmpty ? null : route;
  }

  @override
  Stream<String> get taps => _taps.stream;
}
