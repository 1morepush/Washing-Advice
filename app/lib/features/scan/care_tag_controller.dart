/// Reading a garment's care label.
///
/// Distinct from the garment scan, and not just because it calls a different
/// endpoint. A garment scan *guesses* at fabric from pixels; a label scan reads
/// the manufacturer's own instruction, which outranks anything the rule table
/// would have concluded. The result of this flow is the strongest care evidence
/// the app can hold short of the user typing it in themselves.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/api/scan_dto.dart';

sealed class CareTagState {
  const CareTagState();
}

final class CareTagIdle extends CareTagState {
  const CareTagIdle();
}

final class CareTagReading extends CareTagState {
  const CareTagReading();
}

/// The label was read and the user is confirming what it says.
final class CareTagReviewing extends CareTagState {
  const CareTagReviewing({
    required this.reading,
    required this.updated,
    required this.resolution,
    required this.previous,
  });

  /// What the label scan returned, including how much of it was legible.
  final CareTagScanResult reading;

  /// The item as it would be saved, with the label attached and care
  /// re-resolved from it.
  final WardrobeItem updated;

  /// The resolution, kept for [CareResolution.fieldsOverriddenByLabel] — the
  /// interesting part to show, since it is where the manufacturer contradicted
  /// what we would otherwise have recommended.
  final CareResolution resolution;

  /// The care in force before the scan, for showing what changed.
  final CareInstructions previous;
}

final class CareTagSaved extends CareTagState {
  const CareTagSaved(this.item);

  final WardrobeItem item;
}

final class CareTagFailed extends CareTagState {
  const CareTagFailed(this.message, {this.isRetryable = true});

  final String message;
  final bool isRetryable;
}

class CareTagController extends StateNotifier<CareTagState> {
  CareTagController(this._ref, this.itemId) : super(const CareTagIdle());

  final Ref _ref;
  final ItemId itemId;

  Future<void> captureAndRead() async {
    final ScanImage? image;
    try {
      image = await _ref.read(imageCaptureProvider).capture();
    } on Exception catch (error) {
      state = CareTagFailed('The camera could not be opened. $error');
      return;
    }

    if (image == null) {
      state = const CareTagIdle();
      return;
    }
    await readImage(image);
  }

  Future<void> readImage(ScanImage image) async {
    final item = await _ref.read(wardrobeRepositoryProvider).byId(itemId);
    if (item == null) {
      state = const CareTagFailed(
        'That item is no longer in your wardrobe.',
        isRetryable: false,
      );
      return;
    }

    state = const CareTagReading();

    final CareTagScanResult reading;
    try {
      reading = await _ref.read(aiGatewayProvider).scanCareTag(image);
    } on ScanFailure catch (failure) {
      state = CareTagFailed(failure.message, isRetryable: failure.isRetryable);
      return;
    } on ScanContractError catch (error) {
      state = CareTagFailed(
        'The server sent something this version cannot read. $error',
        isRetryable: false,
      );
      return;
    }

    if (reading.instructions.statesNothing) {
      // Not an error and not a success. Saving a constraint that states nothing
      // would replace a rule-derived profile with an empty label and record it
      // at `tagScan` provenance, making the app *more* confident about care it
      // knows nothing new about.
      state = const CareTagFailed(
        'Nothing on that label could be read. Try a closer, flatter shot with '
        'the symbols in focus.',
      );
      return;
    }

    state = _review(item, reading);
  }

  /// Attaches the label to the item and re-resolves its care.
  CareTagReviewing _review(WardrobeItem item, CareTagScanResult reading) {
    // The composition printed on the label outranks whatever was guessed from
    // a photograph of the garment, so it is taken too when the label carries
    // one. `Confident.resolve` picks by provenance first, which is precisely
    // the ordering this needs.
    final composition = reading.composition == null
        ? item.composition
        : Confident.resolve(item.composition, reading.composition!);

    final withLabel = item.copyWith(
      composition: composition,
      careLabel: Confident(
        reading.instructions,
        // An unreadable symbol lowers confidence in the whole reading, not
        // just in the field it belonged to: if part of the label defeated the
        // OCR, the rest of it deserves less trust as well.
        confidence: reading.confidence,
        source: Provenance.tagScan,
      ),
      updatedAt: DateTime.now(),
    );

    final resolution = _ref.read(careResolverProvider).forItem(withLabel);

    return CareTagReviewing(
      reading: reading,
      updated: withLabel.copyWith(care: resolution.profile),
      resolution: resolution,
      previous: item.care.instructions,
    );
  }

  Future<void> save() async {
    if (state case final CareTagReviewing reviewing) {
      await _ref.read(wardrobeRepositoryProvider).save(reviewing.updated);
      state = CareTagSaved(reviewing.updated);
    }
  }

  void reset() => state = const CareTagIdle();
}

final careTagControllerProvider =
    StateNotifierProvider.family<CareTagController, CareTagState, ItemId>(
      CareTagController.new,
    );
