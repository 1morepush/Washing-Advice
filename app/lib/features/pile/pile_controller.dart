/// Scanning a pile of laundry into a plan.
///
/// The feature the whole project is named for, and the one that only works
/// because everything before it exists. A photograph of a heap of clothes is
/// turned into loads by four separate things, none of which is a model:
///
///  1. the server locates and identifies each garment in the frame;
///  2. `ItemMatcher` decides which of them are things already in the wardrobe;
///  3. recognised items bring their **real care profiles** — including any
///     scanned label — rather than what a photograph of a crumpled sleeve
///     suggests;
///  4. `LaundrySorter` groups them and `ProgramMatcher` names the programme.
///
/// Step 3 is why this is worth building on a wardrobe rather than as a
/// standalone "photograph your laundry" tool. A garment lying twisted in a heap
/// is a poor subject; the same garment photographed properly last month, with
/// its care label read, is a good one. The pile scan only has to work out
/// *which* item it is looking at.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/api/scan_dto.dart';

/// One garment found in the pile, and what the wardrobe made of it.
final class PileDetection {
  const PileDetection({
    required this.detected,
    required this.decision,
    required this.item,
  });

  /// What the vision layer saw, including where in the frame.
  final DetectedItem detected;

  /// Whether the wardrobe recognised it.
  final MatchDecision decision;

  /// The item this contributes to the plan.
  ///
  /// A real wardrobe item when recognised — with its stored care label — and
  /// otherwise a draft built from the reading alone.
  final WardrobeItem item;

  bool get isRecognised => decision is RecognisedItem;

  /// Whether the user should be asked before this is treated as known.
  ///
  /// True for the ambiguous middle: plausible enough to name, not certain
  /// enough to act on. Three identical black t-shirts land here, which is
  /// exactly where they belong.
  bool get needsConfirmation => decision is NeedsConfirmation;
}

sealed class PileState {
  const PileState();
}

final class PileIdle extends PileState {
  const PileIdle();
}

final class PileAnalysing extends PileState {
  const PileAnalysing();
}

/// A plan was produced.
final class PilePlanned extends PileState {
  const PilePlanned({
    required this.plan,
    required this.detections,
    required this.obscuredCount,
    this.diagnostics,
  });

  final LaundryPlan plan;
  final List<PileDetection> detections;

  /// Garments the server could see but not identify.
  ///
  /// Surfaced rather than hidden: "I found 6 items and 2 more are buried" lets
  /// someone reshuffle the pile and rescan, while silently planning for 6 sends
  /// them to the machine with the wrong load.
  final int obscuredCount;

  final ScanDiagnostics? diagnostics;

  int get recognisedCount => detections.where((d) => d.isRecognised).length;

  int get unrecognisedCount => detections.length - recognisedCount;
}

final class PileFailed extends PileState {
  const PileFailed(this.message, {this.isRetryable = true});

  final String message;
  final bool isRetryable;
}

class PileController extends StateNotifier<PileState> {
  PileController(this._ref) : super(const PileIdle());

  final Ref _ref;

  Future<void> captureAndPlan() async {
    final ScanImage? image;
    try {
      image = await _ref.read(imageCaptureProvider).capture();
    } on Exception catch (error) {
      state = PileFailed('The camera could not be opened. $error');
      return;
    }

    if (image == null) {
      state = const PileIdle();
      return;
    }
    await planFor(image);
  }

  Future<void> planFor(ScanImage image) async {
    state = const PileAnalysing();

    final gateway = _ref.read(aiGatewayProvider);
    final PileScanResult reading;
    try {
      reading = await gateway.scanPile(image);
    } on ScanFailure catch (failure) {
      state = PileFailed(failure.message, isRetryable: failure.isRetryable);
      return;
    } on ScanContractError catch (error) {
      state = PileFailed(
        'The server sent something this version cannot read. $error',
        isRetryable: false,
      );
      return;
    }

    if (reading.items.isEmpty) {
      state = PileFailed(
        reading.partiallyObscuredCount > 0
            ? 'Clothes were visible but none could be identified. Spread the '
                  'pile out so each item is separate.'
            : 'No clothes were found in that photo.',
      );
      return;
    }

    state = await _plan(reading);
  }

  Future<PilePlanned> _plan(PileScanResult reading) async {
    // The whole wardrobe, not a filtered slice: something being in the laundry
    // pile is not evidence about its lifecycle, and matching against only
    // "active" items would fail to recognise anything already marked as being
    // washed.
    final wardrobe = await _ref
        .read(wardrobeRepositoryProvider)
        .query(const WardrobeQuery());

    final matcher = _ref.read(itemMatcherProvider);
    final resolver = _ref.read(matchResolverProvider);
    final ids = _ref.read(idGeneratorProvider);
    final byId = {for (final item in wardrobe) item.id: item};

    final detections = <PileDetection>[];
    final claimed = <ItemId>{};

    for (final detected in reading.items) {
      final probe = _fingerprintOf(detected.scan);

      // Items already claimed by an earlier detection are excluded from the
      // next one's candidates. Two socks in a heap must not both resolve to
      // the same wardrobe row, which would plan one item and wash two.
      final available = [
        for (final item in wardrobe)
          if (!claimed.contains(item.id)) item,
      ];

      final decision = resolver.resolve(matcher.rank(probe, available));

      final item = switch (decision) {
        RecognisedItem(:final itemId) => byId[itemId]!,
        // A confirmation candidate is *not* adopted. Acting on a maybe is how
        // one garment's care label gets applied to a different garment.
        NeedsConfirmation() ||
        UnrecognisedItem() => _draftFrom(detected.scan, ids),
      };

      if (decision is RecognisedItem) claimed.add(decision.itemId);
      detections.add(
        PileDetection(detected: detected, decision: decision, item: item),
      );
    }

    final plan = _ref
        .read(laundrySorterProvider)
        .sort(
          [for (final detection in detections) detection.item],
          washer: _ref.read(washerProvider),
          dryer: _ref.read(dryerProvider),
        );

    return PilePlanned(
      plan: plan,
      detections: detections,
      obscuredCount: reading.partiallyObscuredCount,
      diagnostics: _ref.read(aiGatewayProvider).lastDiagnostics,
    );
  }

  /// Confirms a detection as an existing wardrobe item, and replans.
  Future<void> confirm(PileDetection detection, ItemId itemId) async {
    if (state case final PilePlanned planned) {
      final item = await _ref.read(wardrobeRepositoryProvider).byId(itemId);
      if (item == null) return;

      final updated = [
        for (final existing in planned.detections)
          if (identical(existing, detection))
            PileDetection(
              detected: existing.detected,
              decision: RecognisedItem(
                match: MatchCandidate(itemId: itemId, score: 1),
                candidates: existing.decision.candidates,
              ),
              item: item,
            )
          else
            existing,
      ];

      state = PilePlanned(
        plan: _ref
            .read(laundrySorterProvider)
            .sort(
              [for (final detection in updated) detection.item],
              washer: _ref.read(washerProvider),
              dryer: _ref.read(dryerProvider),
            ),
        detections: updated,
        obscuredCount: planned.obscuredCount,
        diagnostics: planned.diagnostics,
      );
    }
  }

  void reset() => state = const PileIdle();

  GarmentFingerprint _fingerprintOf(GarmentScanResult scan) =>
      GarmentFingerprint(
        type: scan.type.value,
        colors: scan.colors.value,
        composition: scan.composition?.value ?? FabricComposition.unknown(),
        brand: scan.brand?.value,
        pattern: scan.pattern?.value,
        distinguishingText: scan.distinguishingText,
      );

  /// An item for a garment the wardrobe does not know.
  ///
  /// Not saved. It exists to be sorted, so the plan covers everything in the
  /// pile rather than quietly omitting the unfamiliar — and a heap of laundry
  /// is the worst possible moment to make someone catalogue a new garment.
  WardrobeItem _draftFrom(GarmentScanResult scan, IdGenerator ids) {
    final now = DateTime.now();
    final draft = WardrobeItem(
      id: ItemId(ids.next()),
      name: scan.suggestedName ?? scan.type.value.label,
      type: scan.type,
      composition:
          scan.composition ??
          Confident(
            FabricComposition.unknown(),
            confidence: 0,
            source: Provenance.fallbackDefault,
          ),
      colors: scan.colors,
      brand: scan.brand,
      pattern: scan.pattern,
      care: const CareProfile.unknown(),
      addedAt: now,
      updatedAt: now,
    );

    return draft.copyWith(
      care: _ref.read(careResolverProvider).forItem(draft).profile,
    );
  }
}

final pileControllerProvider = StateNotifierProvider<PileController, PileState>(
  PileController.new,
);
