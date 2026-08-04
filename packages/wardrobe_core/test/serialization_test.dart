/// Round-trip tests for every serialisable type.
///
/// These matter more than usual here: the same shapes have to be produced by a
/// Python backend and consumed by a Flutter app, so a silent drift in one field
/// name becomes a runtime failure on a user's phone. Encoding and decoding are
/// hand-written precisely so this can be asserted rather than assumed.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'support/fixtures.dart';

void main() {
  /// Encodes, decodes, and re-encodes — catching fields that are written but
  /// never read back, which a single round trip would miss.
  void expectStableRoundTrip<T>(
    T original,
    Map<String, Object?> Function(T) encode,
    T Function(Map<String, Object?>) decode,
  ) {
    final encoded = encode(original);
    // Force it through real JSON so non-encodable values are caught.
    final wire = jsonDecode(jsonEncode(encoded)) as Map<String, Object?>;
    final decoded = decode(wire);
    expect(encode(decoded), encoded);
    expect(decoded, original);
  }

  group('care model', () {
    test('WashCare', () {
      expectStableRoundTrip(
        const WashCare(
          method: WashMethod.hand,
          maxTempC: 30,
          agitation: Agitation.veryMild,
        ),
        (v) => v.toJson(),
        WashCare.fromJson,
      );
    });

    test('WashCare with no stated temperature', () {
      // Null must survive as null: "not stated" is different from "no limit
      // of zero", and collapsing them would silently change the advice.
      final decoded = WashCare.fromJson(
        const WashCare(method: WashMethod.machine).toJson(),
      );
      expect(decoded.maxTempC, isNull);
    });

    test('DryCare', () {
      expectStableRoundTrip(
        const DryCare(
          tumbleDryAllowed: true,
          tumbleDryHeat: TumbleDryHeat.low,
          naturalDry: NaturalDryMethod.flatDry,
          dryInShade: true,
          doNotWring: true,
        ),
        (v) => v.toJson(),
        DryCare.fromJson,
      );
    });

    test('IronCare', () {
      expectStableRoundTrip(
        const IronCare(
          temperature: IronTemperature.medium,
          steamAllowed: false,
        ),
        (v) => v.toJson(),
        IronCare.fromJson,
      );
    });

    test('ProfessionalCare', () {
      expectStableRoundTrip(
        const ProfessionalCare(
          solvent: CleaningSolvent.wetClean,
          gentleCycle: true,
        ),
        (v) => v.toJson(),
        ProfessionalCare.fromJson,
      );
    });

    test('CareInstructions including warnings', () {
      expectStableRoundTrip(
        delicateCare.withWarnings([
          CareWarning.washInsideOut,
          CareWarning.useMeshBag,
        ]),
        (v) => v.toJson(),
        CareInstructions.fromJson,
      );
    });

    test('CareProfile', () {
      expectStableRoundTrip(
        CareProfile(
          instructions: cottonCare,
          source: Provenance.tagScan,
          confidence: 0.91,
          lastReviewedAt: testNow,
        ),
        (v) => v.toJson(),
        CareProfile.fromJson,
      );
    });
  });

  group('wardrobe model', () {
    test('FabricComposition', () {
      expectStableRoundTrip(
        FabricComposition({Fiber.cotton: 80, Fiber.polyester: 20}),
        (v) => v.toJson(),
        FabricComposition.fromJson,
      );
    });

    test('PurchaseInfo', () {
      expectStableRoundTrip(
        PurchaseInfo(
          priceMinorUnits: 4999,
          currencyCode: 'GBP',
          purchasedAt: testNow,
          retailer: 'Somewhere',
        ),
        (v) => v.toJson(),
        PurchaseInfo.fromJson,
      );
    });

    test('UsageStats', () {
      expectStableRoundTrip(
        UsageStats(
          timesWorn: 12,
          timesWashed: 5,
          wearsSinceWash: 2,
          lastWornAt: testNow,
          lastWashedAt: testNow,
          firstWornAt: testNow,
        ),
        (v) => v.toJson(),
        UsageStats.fromJson,
      );
    });

    test('ItemPhoto', () {
      expectStableRoundTrip(
        ItemPhoto(
          uri: 'file://photo.jpg',
          role: PhotoRole.careTag,
          capturedAt: testNow,
          width: 1024,
          height: 768,
          isPrimary: true,
        ),
        (v) => v.toJson(),
        ItemPhoto.fromJson,
      );
    });

    test('WearObservation', () {
      expectStableRoundTrip(
        WearObservation(
          type: WearType.pilling,
          severity: WearSeverity.moderate,
          observedAt: testNow,
          note: 'under the arms',
        ),
        (v) => v.toJson(),
        WearObservation.fromJson,
      );
    });

    test('ItemRelationship', () {
      expectStableRoundTrip(
        const ItemRelationship(
          from: ItemId('a'),
          to: ItemId('b'),
          kind: RelationKind.suitSet,
          strength: 0.8,
        ),
        (v) => v.toJson(),
        ItemRelationship.fromJson,
      );
    });
  });

  group('WardrobeItem', () {
    test('a fully populated item survives a round trip', () {
      final item = buildItem(
        id: 'full',
        name: 'Grey Nike hoodie',
        type: ItemType.hoodie,
        composition: {Fiber.cotton: 80, Fiber.polyester: 20},
        colors: [Colors.grey, Colors.navy],
        brand: 'Nike',
        pattern: Pattern.graphic,
        sizeLabel: 'M',
        distinguishingText: 'Just Do It',
        purchase: PurchaseInfo(
          priceMinorUnits: 6500,
          currencyCode: 'USD',
          purchasedAt: testNow,
        ),
        isFavorite: true,
      );

      final wire =
          jsonDecode(jsonEncode(item.toJson())) as Map<String, Object?>;
      final restored = WardrobeItem.fromJson(wire);

      // Identity is the id alone, so compare the encodings for a real check.
      expect(restored.toJson(), item.toJson());
      expect(restored.name, item.name);
      expect(restored.brand?.value, 'Nike');
      expect(restored.brand?.source, item.brand?.source);
      expect(restored.composition.value, item.composition.value);
      expect(restored.colors.value.colors, hasLength(2));
      expect(restored.distinguishingText, 'Just Do It');
      expect(restored.purchase?.priceMinorUnits, 6500);
      expect(restored.isFavorite, isTrue);
    });

    test('a minimal item survives a round trip', () {
      final item = buildItem(id: 'minimal');
      final restored = WardrobeItem.fromJson(item.toJson());
      expect(restored.toJson(), item.toJson());
      expect(restored.brand, isNull);
      expect(restored.purchase, isNull);
    });

    test('confidence and provenance are preserved exactly', () {
      final item = buildItem(id: 'c');
      final restored = WardrobeItem.fromJson(item.toJson());
      expect(restored.type.confidence, item.type.confidence);
      expect(restored.type.source, item.type.source);
      expect(restored.care.source, item.care.source);
      expect(restored.care.confidence, item.care.confidence);
    });
  });

  group('machine profiles', () {
    test('every seeded washer survives a round trip', () {
      for (final washer in seededWashers.values) {
        final wire =
            jsonDecode(jsonEncode(washer.toJson())) as Map<String, Object?>;
        final restored = WasherProfile.fromJson(wire);
        expect(restored.toJson(), washer.toJson(), reason: washer.displayName);
        expect(restored.programs, hasLength(washer.programs.length));
      }
    });

    test('every seeded dryer survives a round trip', () {
      for (final dryer in seededDryers.values) {
        final wire =
            jsonDecode(jsonEncode(dryer.toJson())) as Map<String, Object?>;
        final restored = DryerProfile.fromJson(wire);
        expect(restored.toJson(), dryer.toJson(), reason: dryer.displayName);
      }
    });
  });

  group('Confident', () {
    test('preserves the wrapped value, confidence and source', () {
      final original = Confident(
        ItemType.hoodie,
        confidence: 0.73,
        source: Provenance.aiInference,
      );
      final restored = Confident.fromJson(
        original.toJson((t) => t.name),
        (raw) => ItemType.values.byName(raw! as String),
      );
      expect(restored, original);
    });

    test('rejects a confidence outside 0..1', () {
      expect(
        () => Confident(
          ItemType.hoodie,
          confidence: 1.5,
          source: Provenance.aiInference,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('LaundryRecord', () {
    test('survives a round trip with full settings', () {
      final record = LaundryRecord(
        washedAt: testNow,
        washerId: const WasherId('w1'),
        washerName: 'LG Front loader',
        programName: 'Delicates',
        temperatureC: 30,
        spinRpm: 800,
        detergent: 'Something',
        usedSoftener: false,
        dryHeat: TumbleDryHeat.low,
        duration: const Duration(minutes: 55),
        followedRecommendation: true,
        loadId: const LoadId('load.1'),
      );
      final wire =
          jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>;
      expect(LaundryRecord.fromJson(wire).toJson(), record.toJson());
    });
  });
}
