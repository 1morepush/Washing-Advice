/// Reconciling two devices' versions of one garment.
///
/// The tests that matter are the ones where a clock gives the wrong answer.
/// Everything else here is bookkeeping.
library;

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

void main() {
  final monday = DateTime.utc(2026, 8, 3);
  final tuesday = DateTime.utc(2026, 8, 4);

  WardrobeItem jumper({
    required DateTime updatedAt,
    String name = 'Wool jumper',
    Confident<FabricComposition>? composition,
    Confident<CareConstraint>? careLabel,
    CareProfile? care,
    Set<String> tags = const {},
    bool isFavorite = false,
    UsageStats usage = const UsageStats.none(),
    PhotoSet photos = PhotoSet.empty,
    DateTime? addedAt,
  }) =>
      WardrobeItem(
        id: const ItemId('jumper'),
        name: name,
        type: Confident(
          ItemType.sweater,
          confidence: 0.9,
          source: Provenance.aiInference,
        ),
        composition: composition ??
            Confident(
              FabricComposition(const {Fiber.wool: 100}),
              confidence: 0.6,
              source: Provenance.aiInference,
            ),
        colors: Confident(
          ColorPalette([ItemColor.fromHex('#3C3F44', name: 'Charcoal')]),
          confidence: 0.9,
          source: Provenance.aiInference,
        ),
        careLabel: careLabel,
        care: care ?? const CareProfile.unknown(),
        tags: tags,
        isFavorite: isFavorite,
        usage: usage,
        photos: photos,
        addedAt: addedAt ?? monday,
        updatedAt: updatedAt,
      );

  group('provenance beats the clock', () {
    test('a scanned label survives a later photo guess', () {
      // The case that makes last-writer-wins unacceptable. Monday's phone read
      // the actual care label; Tuesday's tablet only saw a photograph. Taking
      // the later write would discard a manufacturer's instruction and start
      // recommending a hand wash for a machine-washable garment.
      final phone = jumper(
        updatedAt: monday,
        composition: Confident(
          FabricComposition(const {Fiber.wool: 80, Fiber.nylon: 20}),
          confidence: 0.95,
          source: Provenance.tagScan,
        ),
      );
      final tablet = jumper(
        updatedAt: tuesday,
        composition: Confident(
          FabricComposition(const {Fiber.wool: 100}),
          confidence: 0.55,
          source: Provenance.aiInference,
        ),
      );

      final merged = phone.mergedWith(tablet);

      expect(merged.item.composition.source, Provenance.tagScan);
      expect(merged.item.composition.value.percentOf(Fiber.nylon), 20);
      expect(merged.decisions['composition'], MergeOutcome.byProvenance);
    });

    test('and it survives in either direction', () {
      // Symmetry is not decoration. Two devices reconciling with each other
      // must not reach different states and then keep correcting one another.
      final phone = jumper(
        updatedAt: monday,
        composition: Confident(
          FabricComposition(const {Fiber.wool: 80, Fiber.nylon: 20}),
          confidence: 0.95,
          source: Provenance.tagScan,
        ),
      );
      final tablet = jumper(updatedAt: tuesday);

      expect(
        phone.mergedWith(tablet).item.composition.value.toJson(),
        tablet.mergedWith(phone).item.composition.value.toJson(),
      );
    });

    test('a user correction beats a later care-label scan', () {
      // The top of the ladder. Someone who looked at the garment knows things
      // the label does not — that it already shrank, that the label is wrong.
      final corrected = jumper(
        updatedAt: monday,
        composition: Confident.fromUser(
          FabricComposition(const {Fiber.acrylic: 100}),
        ),
      );
      final scanned = jumper(
        updatedAt: tuesday,
        composition: Confident(
          FabricComposition(const {Fiber.wool: 100}),
          confidence: 0.98,
          source: Provenance.tagScan,
        ),
      );

      final merged = corrected.mergedWith(scanned);
      expect(merged.item.composition.source, Provenance.userEdited);
      expect(merged.item.composition.value.percentOf(Fiber.acrylic), 100);
    });

    test('a care profile read from a label beats one derived from a rule', () {
      final fromLabel = jumper(
        updatedAt: monday,
        care: const CareProfile(
          instructions: CareInstructions.conservative(),
          source: Provenance.tagScan,
          confidence: 0.95,
        ),
      );
      final fromRule = jumper(
        updatedAt: tuesday,
        care: const CareProfile(
          instructions: CareInstructions.conservative(),
          source: Provenance.careRule,
          confidence: 0.7,
        ),
      );

      final merged = fromLabel.mergedWith(fromRule);
      expect(merged.item.care.source, Provenance.tagScan);
      expect(merged.decisions['care'], MergeOutcome.byProvenance);
    });
  });

  group('where the clock still decides', () {
    test('two edits of the same rank are settled by recency', () {
      // Provenance cannot separate two user edits, and confidence is not a
      // fact about either of them. Time is all that is left.
      final earlier = jumper(
        updatedAt: monday,
        composition: Confident.fromUser(
          FabricComposition(const {Fiber.cotton: 100}),
        ),
      );
      final later = jumper(
        updatedAt: tuesday,
        composition: Confident.fromUser(
          FabricComposition(const {Fiber.linen: 100}),
        ),
      );

      final merged = earlier.mergedWith(later);
      expect(merged.item.composition.value.percentOf(Fiber.linen), 100);
      expect(merged.decisions['composition'], MergeOutcome.byRecency);
    });

    test('a plain field takes the more recent value', () {
      final merged = jumper(updatedAt: monday, name: 'Old name')
          .mergedWith(jumper(updatedAt: tuesday, name: 'New name'));

      expect(merged.item.name, 'New name');
      expect(merged.decisions['name'], MergeOutcome.byRecency);
    });

    test('a favourite flag follows the more recent edit', () {
      final merged = jumper(updatedAt: tuesday, isFavorite: true)
          .mergedWith(jumper(updatedAt: monday));

      expect(merged.item.isFavorite, isTrue);
    });
  });

  group('what combines rather than competes', () {
    test('tags added on both devices are both kept', () {
      // Neither supersedes the other; both are things the user did.
      final merged = jumper(updatedAt: monday, tags: {'gym'})
          .mergedWith(jumper(updatedAt: tuesday, tags: {'winter'}));

      expect(merged.item.tags, {'gym', 'winter'});
      expect(merged.decisions['tags'], MergeOutcome.combined);
    });

    test('a label known to only one device is adopted, not discarded', () {
      // The ordinary case for a device that has scanned something the other
      // has never seen. Treating it as a conflict would lose information.
      final scanned = jumper(
        updatedAt: monday,
        careLabel: Confident(
          const CareConstraint(maxTempC: 40),
          confidence: 0.9,
          source: Provenance.tagScan,
        ),
      );

      final merged = scanned.mergedWith(jumper(updatedAt: tuesday));
      expect(merged.item.careLabel?.value.maxTempC, 40);
      expect(merged.decisions['careLabel'], MergeOutcome.combined);
    });

    test('photos union, and a cutout made on one device is kept', () {
      final withCutout = jumper(
        updatedAt: monday,
        photos: PhotoSet([
          ItemPhoto(
            uri: 'file:///front.jpg',
            cutoutUri: 'file:///front-cut.png',
            role: PhotoRole.front,
            capturedAt: monday,
          ),
        ]),
      );
      final withBack = jumper(
        updatedAt: tuesday,
        photos: PhotoSet([
          ItemPhoto(
            uri: 'file:///front.jpg',
            role: PhotoRole.front,
            capturedAt: monday,
          ),
          ItemPhoto(
            uri: 'file:///back.jpg',
            role: PhotoRole.back,
            capturedAt: tuesday,
          ),
        ]),
      );

      final merged = withCutout.mergedWith(withBack);
      expect(merged.item.photos.length, 2);
      // The cutout was made on one device only, and survives.
      expect(
        merged.item.photos.photos
            .firstWhere((p) => p.uri == 'file:///front.jpg')
            .cutoutUri,
        'file:///front-cut.png',
      );
    });

    test('counters never go backwards', () {
      // A count that shrank would make a garment look newer than it is and
      // re-enable the dye-bleed isolation it had earned its way out of. This
      // is an approximation until the event logs themselves merge, and it is
      // wrong in the safe direction.
      final merged = jumper(
        updatedAt: monday,
        usage: const UsageStats(timesWorn: 9, timesWashed: 4),
      ).mergedWith(
        jumper(
          updatedAt: tuesday,
          usage: const UsageStats(timesWorn: 3, timesWashed: 1),
        ),
      );

      expect(merged.item.usage.timesWorn, 9);
      expect(merged.item.usage.timesWashed, 4);
      expect(merged.decisions['usage'], MergeOutcome.combined);
    });
  });

  group('bookkeeping', () {
    test('an item keeps its earliest known acquisition date', () {
      // Otherwise a garment would appear to have been acquired when it was
      // merely synced to a second device.
      final merged = jumper(updatedAt: monday, addedAt: monday).mergedWith(
        jumper(updatedAt: tuesday, addedAt: tuesday),
      );

      expect(merged.item.addedAt, monday);
    });

    test('identical versions report no conflict at all', () {
      final merged =
          jumper(updatedAt: monday).mergedWith(jumper(updatedAt: monday));

      expect(merged.hadConflict, isFalse);
      expect(merged.decisions, isEmpty);
    });

    test('every differing field is reported, so a sync can explain itself', () {
      final merged = jumper(updatedAt: monday, name: 'A', tags: {'x'})
          .mergedWith(jumper(updatedAt: tuesday, name: 'B', tags: {'y'}));

      expect(merged.hadConflict, isTrue);
      expect(merged.decisions.keys, containsAll(['name', 'tags']));
    });
  });

  group('convergence', () {
    test('merging is symmetric across every field that can differ', () {
      // The property the whole design rests on, checked exhaustively rather
      // than on one lucky example. Two devices reconciling with each other
      // must reach the *same* state — otherwise each keeps its own value and
      // they correct one another forever.
      final variants = <WardrobeItem>[
        jumper(updatedAt: monday),
        jumper(updatedAt: tuesday, name: 'Renamed'),
        jumper(updatedAt: monday, tags: {'gym'}),
        jumper(updatedAt: tuesday, tags: {'winter'}),
        jumper(updatedAt: monday, isFavorite: true),
        jumper(
          updatedAt: tuesday,
          composition: Confident.fromUser(
            FabricComposition(const {Fiber.linen: 100}),
          ),
        ),
        jumper(
          updatedAt: monday,
          composition: Confident(
            FabricComposition(const {Fiber.wool: 80, Fiber.nylon: 20}),
            confidence: 0.95,
            source: Provenance.tagScan,
          ),
        ),
        jumper(
          updatedAt: monday,
          usage: const UsageStats(timesWorn: 7, timesWashed: 2),
        ),
        jumper(
          updatedAt: monday,
          careLabel: Confident(
            const CareConstraint(maxTempC: 40),
            confidence: 0.9,
            source: Provenance.tagScan,
          ),
        ),
      ];

      for (final a in variants) {
        for (final b in variants) {
          expect(
            a.mergedWith(b).item.toJson(),
            b.mergedWith(a).item.toJson(),
            reason: 'merging "${a.name}" and "${b.name}" is not symmetric',
          );
        }
      }
    });

    test('identical clocks still converge on one value', () {
      // The case the first implementation got wrong. With equal timestamps it
      // preferred the receiver, so each device kept its own name and neither
      // ever adopted the other's.
      final a = jumper(updatedAt: monday, name: 'Alpha');
      final b = jumper(updatedAt: monday, name: 'Beta');

      expect(a.mergedWith(b).item.name, b.mergedWith(a).item.name);
    });

    test('merging is idempotent', () {
      // Syncing twice must not keep changing the answer, or a quiet device
      // would drift every time it reconnected.
      final a = jumper(updatedAt: monday, tags: {'gym'});
      final b = jumper(updatedAt: tuesday, tags: {'winter'}, name: 'Renamed');

      final once = a.mergedWith(b).item;
      final twice = once.mergedWith(b).item;

      expect(twice.toJson(), once.toJson());
    });
  });
}
