/// Where an item is in its life, and what that permits.
///
/// The laundry states are the interesting ones. Three of them describe a
/// garment that is *not in the wardrobe* — in the basket, in the drum, on the
/// airer — and each answers "can I wear this tonight?" differently from the
/// others while answering "do I still own it?" the same way. Getting either
/// wrong is visible: a shirt mid-cycle offered up in an outfit, or a wardrobe
/// that appears to have lost everything currently being washed.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  group('an item in the laundry cycle', () {
    const cycle = [
      LifecycleState.inLaundry,
      LifecycleState.beingWashed,
      LifecycleState.beingDried,
    ];

    test('is still owned, so the wardrobe does not appear to lose it', () {
      for (final state in cycle) {
        expect(state.isOwned, isTrue, reason: state.label);
        expect(
          const WardrobeQuery.owned().lifecycleStates,
          contains(state),
          reason: state.label,
        );
      }
    });

    test('cannot be worn while it is in there', () {
      for (final state in cycle) {
        expect(state.isWearable, isFalse, reason: state.label);
      }
    });

    test('is recognised as being in the cycle', () {
      for (final state in cycle) {
        expect(state.isInLaundryCycle, isTrue, reason: state.label);
      }
      expect(LifecycleState.active.isInLaundryCycle, isFalse);
      expect(LifecycleState.stored.isInLaundryCycle, isFalse);
    });

    test('is only offered to the sorter while it is still in the basket', () {
      // Something already turning in the drum must not be planned into a
      // second load — it is being washed, not waiting to be.
      expect(LifecycleState.inLaundry.isLaunderable, isTrue);
      expect(LifecycleState.beingWashed.isLaunderable, isFalse);
      expect(LifecycleState.beingDried.isLaunderable, isFalse);
    });

    test('moves through the cycle and back to the wardrobe', () {
      expect(
        LifecycleState.active.canTransitionTo(LifecycleState.inLaundry),
        isTrue,
      );
      expect(
        LifecycleState.inLaundry.canTransitionTo(LifecycleState.beingWashed),
        isTrue,
      );
      expect(
        LifecycleState.beingWashed.canTransitionTo(LifecycleState.beingDried),
        isTrue,
      );
      expect(
        LifecycleState.beingDried.canTransitionTo(LifecycleState.active),
        isTrue,
      );
      // And back a step, because people do take a wet thing out and re-run it.
      expect(
        LifecycleState.beingDried.canTransitionTo(LifecycleState.beingWashed),
        isTrue,
      );
    });

    test('cannot be reached from a state that is already final', () {
      expect(
        LifecycleState.discarded.canTransitionTo(LifecycleState.inLaundry),
        isFalse,
      );
    });
  });

  group('reading a state that was stored', () {
    test('round-trips through the name it is stored under', () {
      for (final state in LifecycleState.values) {
        expect(LifecycleState.parse(state.name), state, reason: state.name);
      }
    });

    test('a name this build has never heard of does not throw', () {
      // States get added. A device on an older build can be synced an item in
      // one it does not know, and `values.byName` would take down the read of
      // the entire wardrobe over a single field.
      expect(LifecycleState.parse('beingIroned'), LifecycleState.active);
    });
  });
}
