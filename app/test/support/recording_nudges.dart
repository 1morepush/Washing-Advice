/// A [Nudges] that remembers what it was asked, for tests.
library;

import 'dart:async';

import 'package:washing_advice/data/notifications/nudges.dart';

final class RecordingNudges implements Nudges {
  RecordingNudges({this.isSupported = true, this.grant = true});

  @override
  final bool isSupported;

  /// What the person answers when asked for permission.
  bool grant;

  int permissionRequests = 0;

  /// The daily reminder currently scheduled, if any.
  ({DateTime firstAt, String title, String body, String route})? scheduled;

  int cancels = 0;

  /// What [launchRoute] answers.
  String? launched;

  /// Taps to feed the app while it is running.
  final tapped = StreamController<String>.broadcast();

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<void> scheduleDaily({
    required DateTime firstAt,
    required String title,
    required String body,
    required String route,
  }) async {
    scheduled = (firstAt: firstAt, title: title, body: body, route: route);
  }

  @override
  Future<void> cancel() async {
    cancels++;
    scheduled = null;
  }

  @override
  Future<String?> launchRoute() async => launched;

  @override
  Stream<String> get taps => tapped.stream;
}
