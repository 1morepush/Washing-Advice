/// The four combinations of washing and drying, and the wiring behind them.
///
/// The grouping itself is the core's, and is tested there. What this covers is
/// the part the core cannot see: that a switch on a settings screen actually
/// reaches `SortingPreferences`, and that the sentence naming the combination
/// says what the switches do.
///
/// The summary is worth pinning precisely because it is only a sentence.
/// Nothing breaks when it drifts — it just quietly starts describing the
/// opposite of the behaviour, which is worse than showing nothing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/features/settings/sorting_section.dart';

void main() {
  group('the preference reaches the sorter', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('combining colours by default', () {
      expect(
        container
            .read(laundrySorterProvider)
            .preferences
            .mergeAcrossColorClasses,
        isTrue,
      );
    });

    test('and separating them once asked', () {
      container.read(separateWashingProvider.notifier).state = true;

      expect(
        container
            .read(laundrySorterProvider)
            .preferences
            .mergeAcrossColorClasses,
        isFalse,
        reason:
            'the switch reads "separate", the preference reads "merge"; '
            'an inversion dropped here would silently do the opposite',
      );
    });

    test('the two settings are independent', () {
      container.read(separateWashingProvider.notifier).state = true;

      final preferences = container.read(laundrySorterProvider).preferences;
      expect(preferences.mergeAcrossColorClasses, isFalse);
      expect(
        preferences.splitDrying,
        isFalse,
        reason: 'washing apart must not drag drying along with it',
      );
    });
  });

  group('the sentence naming the combination', () {
    test('wash together, dry together', () {
      expect(
        sortingSummary(separateWashing: false, splitDrying: false),
        'Colours that do not conflict wash together, and each load dries as '
        'one.',
      );
    });

    test('wash together, dry apart', () {
      expect(
        sortingSummary(separateWashing: false, splitDrying: true),
        'Colours that do not conflict wash together, and a load splits so '
        'whatever can be tumble dried is.',
      );
    });

    test('wash apart, dry together', () {
      expect(
        sortingSummary(separateWashing: true, splitDrying: false),
        'Each colour washes on its own, and each load dries as one.',
      );
    });

    test('wash apart, dry apart', () {
      expect(
        sortingSummary(separateWashing: true, splitDrying: true),
        'Each colour washes on its own, and a load splits so whatever can be '
        'tumble dried is.',
      );
    });

    test('all four are different sentences', () {
      final said = {
        for (final washing in [true, false])
          for (final drying in [true, false])
            sortingSummary(separateWashing: washing, splitDrying: drying),
      };

      expect(said, hasLength(4));
    });
  });

  group('the switches', () {
    testWidgets('write through to the store and to the sorter', (tester) async {
      final store = _RecordingSettingsStore();
      final container = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: SortingSection()),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Wash each colour separately'));
      await tester.pumpAndSettle();

      // Both, because they are two separate writes and either one alone is a
      // bug: the store without the provider does nothing until a restart, and
      // the provider without the store forgets at the next launch.
      expect(store.separateWashingWrites, [true]);
      expect(
        container
            .read(laundrySorterProvider)
            .preferences
            .mergeAcrossColorClasses,
        isFalse,
      );
    });

    testWidgets('and the summary follows them', (tester) async {
      final container = ProviderContainer(
        overrides: [
          settingsStoreProvider.overrideWithValue(_RecordingSettingsStore()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: SortingSection()),
            ),
          ),
        ),
      );

      expect(
        find.text(sortingSummary(separateWashing: false, splitDrying: false)),
        findsOneWidget,
      );

      await tester.tap(find.text('Split a load for drying'));
      await tester.pumpAndSettle();

      expect(
        find.text(sortingSummary(separateWashing: false, splitDrying: true)),
        findsOneWidget,
      );
    });
  });
}

/// A settings store that records the writes instead of reaching for the disk.
///
/// SharedPreferences is not available in a widget test without wiring up a
/// mock channel, and what matters here is only that the write happened.
class _RecordingSettingsStore implements SettingsStore {
  final separateWashingWrites = <bool>[];
  final splitDryingWrites = <bool>[];

  @override
  Future<void> setSeparateWashing(bool value) async =>
      separateWashingWrites.add(value);

  @override
  Future<void> setSplitDrying(bool value) async => splitDryingWrites.add(value);

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not needed here');
}
