/// The evening reminder: the half of "What did you wear today?" that gets
/// somebody to the screen.
///
/// The notification itself is the platform's and cannot run here. What is
/// worth protecting is everything around it: that the time you set is the
/// time it fires, that the switch cannot be on without permission, that the
/// stored setting is what every launch re-states, and that a tap lands on
/// the three-tap screen rather than the wardrobe.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/features/laundry/evening_nudge.dart';
import 'package:washing_advice/features/laundry/worn_today_screen.dart';
import 'package:washing_advice/features/settings/nudge_section.dart';
import 'package:washing_advice/features/wardrobe/wardrobe_screen.dart';
import 'package:washing_advice/main.dart';

import '../support/recording_nudges.dart';

void main() {
  group('the time of day', () {
    final tuesdayNoon = DateTime(2026, 9, 15, 12);

    test('comes round later today when it is still ahead', () {
      const evening = NudgeTime(hour: 20, minute: 30);
      expect(evening.next(tuesdayNoon), DateTime(2026, 9, 15, 20, 30));
    });

    test('and tomorrow once it has passed', () {
      const morning = NudgeTime(hour: 7, minute: 0);
      expect(morning.next(tuesdayNoon), DateTime(2026, 9, 16, 7));
    });

    test('the current minute counts as passed', () {
      // A reminder set for right now is for tomorrow, not for a notification
      // that fires the instant the switch is flipped.
      const noon = NudgeTime(hour: 12, minute: 0);
      expect(noon.next(tuesdayNoon), DateTime(2026, 9, 16, 12));
    });

    test('tomorrow can be next month', () {
      const morning = NudgeTime(hour: 7, minute: 0);
      expect(morning.next(DateTime(2026, 9, 30, 23)), DateTime(2026, 10, 1, 7));
    });

    test('round-trips through minutes after midnight', () {
      const time = NudgeTime(hour: 20, minute: 30);
      expect(NudgeTime.fromMinutes(time.minutes), time);
      expect(time.minutes, 20 * 60 + 30);
    });
  });

  group('the schedule follows the setting', () {
    late RecordingNudges nudges;
    late NudgeScheduler scheduler;

    setUp(() {
      nudges = RecordingNudges();
      scheduler = NudgeScheduler(nudges);
    });

    test('a time means a daily reminder from its next occurrence', () async {
      await scheduler.apply(
        const NudgeTime(hour: 20, minute: 30),
        now: DateTime(2026, 9, 15, 21),
      );

      final scheduled = nudges.scheduled!;
      expect(scheduled.firstAt, DateTime(2026, 9, 16, 20, 30));
      expect(scheduled.route, '/laundry/worn');
      expect(scheduled.title, 'What did you wear today?');
    });

    test('no time means no reminder', () async {
      await scheduler.apply(const NudgeTime(hour: 20, minute: 30));

      await scheduler.apply(null);

      expect(nudges.scheduled, isNull);
      expect(nudges.cancels, 1);
    });

    test('a platform that cannot is left alone', () async {
      // The web. Calling through would be harmless on the no-op, but a
      // scheduler that knows to stop is one that can be trusted with a
      // platform that throws instead.
      final unsupported = RecordingNudges(isSupported: false);

      await NudgeScheduler(unsupported).apply(NudgeTime.defaultEvening);
      await NudgeScheduler(unsupported).apply(null);

      expect(unsupported.scheduled, isNull);
      expect(unsupported.cancels, 0);
    });
  });

  group('the stored setting', () {
    late SettingsStore settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsStore(await SharedPreferences.getInstance());
    });

    test('is off until set', () {
      expect(settings.nudgeMinutes, isNull);
      expect(nudgeTimeOf(settings), isNull);
    });

    test('round-trips, and null turns it off', () async {
      await settings.setNudgeMinutes(20 * 60 + 30);
      expect(nudgeTimeOf(settings), const NudgeTime(hour: 20, minute: 30));

      await settings.setNudgeMinutes(null);
      expect(settings.nudgeMinutes, isNull);
    });

    test('a value no clock has is read as off', () async {
      // Written by a build that stored something else under the key, or by
      // hand. An unreadable time must not become a crash in `NudgeTime`.
      SharedPreferences.setMockInitialValues({'eveningNudgeMinutes': 9999});
      settings = SettingsStore(await SharedPreferences.getInstance());

      expect(settings.nudgeMinutes, isNull);
    });
  });

  group('the settings section', () {
    late RecordingNudges nudges;
    late SettingsStore settings;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = SettingsStore(await SharedPreferences.getInstance());
      nudges = RecordingNudges();
      container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWithValue(settings),
          nudgesProvider.overrideWithValue(nudges),
        ],
      );
      addTearDown(container.dispose);
    });

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: NudgeSection())),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('starts off, with no time shown', (tester) async {
      await pump(tester);

      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(find.textContaining('Every day at'), findsNothing);
    });

    testWidgets(
      'turning it on asks permission, then schedules half past eight',
      (tester) async {
        await pump(tester);

        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();

        expect(nudges.permissionRequests, 1);
        expect(settings.nudgeMinutes, 20 * 60 + 30);
        expect(nudges.scheduled?.route, '/laundry/worn');
        expect(find.textContaining('Every day at'), findsOneWidget);
      },
    );

    testWidgets('permission refused leaves it off, and says why', (
      tester,
    ) async {
      // Scheduled anyway, the reminder would simply never arrive and nothing
      // would say so.
      nudges.grant = false;
      await pump(tester);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(settings.nudgeMinutes, isNull);
      expect(nudges.scheduled, isNull);
      expect(find.textContaining("phone's settings"), findsOneWidget);
    });

    testWidgets('turning it off cancels and forgets the time', (tester) async {
      await settings.setNudgeMinutes(20 * 60 + 30);
      container.read(nudgeTimeProvider.notifier).state =
          NudgeTime.defaultEvening;
      await pump(tester);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(settings.nudgeMinutes, isNull);
      expect(nudges.cancels, 1);
      expect(find.textContaining('Every day at'), findsNothing);
    });

    testWidgets('a platform that cannot says so instead of offering a switch', (
      tester,
    ) async {
      container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWithValue(settings),
          nudgesProvider.overrideWithValue(RecordingNudges(isSupported: false)),
        ],
      );
      addTearDown(container.dispose);
      await pump(tester);

      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.textContaining('phone app'), findsOneWidget);
    });
  });

  group('a tap on the reminder', () {
    late RecordingNudges nudges;
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      nudges = RecordingNudges();
      container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWithValue(
            SettingsStore(await SharedPreferences.getInstance()),
          ),
          wardrobeRepositoryProvider.overrideWithValue(
            InMemoryWardrobeRepository(),
          ),
          outfitRepositoryProvider.overrideWithValue(
            InMemoryOutfitRepository(),
          ),
          eventLogProvider.overrideWithValue(InMemoryEventLog()),
          imageStoreProvider.overrideWithValue(MemoryImageStore()),
          nudgesProvider.overrideWithValue(nudges),
        ],
      );
      addTearDown(container.dispose);
    });

    Future<void> pump(
      WidgetTester tester, {
      String initialLocation = '/',
    }) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: WashingAdviceApp(initialLocation: initialLocation),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('while the app is open goes to the three-tap screen', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byType(WardrobeScreen), findsOneWidget);

      nudges.tapped.add(eveningNudge.route);
      await tester.pumpAndSettle();

      expect(find.byType(WornTodayScreen), findsOneWidget);
    });

    testWidgets('on a closed app opens there directly', (tester) async {
      // What `main()` does with `launchRoute()`: the screen the tap was for
      // is the first frame, not the wardrobe and then a jump.
      await pump(tester, initialLocation: eveningNudge.route);

      expect(find.byType(WornTodayScreen), findsOneWidget);
      expect(find.byType(WardrobeScreen), findsNothing);
    });
  });
}
