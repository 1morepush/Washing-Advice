/// Reading a garment's care label.
///
/// Distinct from the garment scan, and not just because it calls a different
/// endpoint. A garment scan *guesses* at fabric from pixels; a label scan reads
/// the manufacturer's own instruction, which outranks anything the rule table
/// would have concluded. The result of this flow is the strongest care evidence
/// the app can hold short of the user typing it in themselves.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/api/scan_dto.dart';
import '../../data/images/image_store.dart';
import 'care_label_merge.dart';

sealed class CareTagState {
  const CareTagState();
}

final class CareTagIdle extends CareTagState {
  const CareTagIdle();
}

final class CareTagReading extends CareTagState {
  const CareTagReading();
}

/// Photographs taken so far, before any of them has been read.
///
/// A label is very often printed on both sides, or continues onto a second tag
/// sewn behind the first, and reading one side of a two-sided label gives an
/// answer that looks complete and is not. Collecting first means the reading
/// sees the whole label at once rather than producing two partial answers for
/// something to reconcile afterwards.
final class CareTagCollecting extends CareTagState {
  const CareTagCollecting(this.images);

  final List<ScanImage> images;
}

/// The label was read and the user is confirming what it says.
final class CareTagReviewing extends CareTagState {
  const CareTagReviewing({
    required this.reading,
    required this.updated,
    required this.resolution,
    required this.previous,
    this.images = const [],
    this.keptFromEarlier = const {},
    this.hadEarlierLabel = false,
  });

  /// What the label scan returned, including how much of it was legible.
  final CareTagScanResult reading;

  /// The photographs the reading came from, kept so they can be filed against
  /// the item on save.
  ///
  /// Empty only when a reading arrived without any, which is how the tests
  /// drive this controller directly.
  final List<ScanImage> images;

  /// The item as it would be saved, with the label attached and care
  /// re-resolved from it.
  final WardrobeItem updated;

  /// The resolution, kept for [CareResolution.fieldsOverriddenByLabel] — the
  /// interesting part to show, since it is where the manufacturer contradicted
  /// what we would otherwise have recommended.
  final CareResolution resolution;

  /// The care in force before the scan, for showing what changed.
  final CareInstructions previous;

  /// Fields this reading did not state, kept from a label scanned earlier.
  ///
  /// Empty when there was no earlier label, or when the new reading restated
  /// everything. Non-empty is worth showing: a value carried over from a scan
  /// weeks ago, presented as though this photograph had just read it, is the
  /// app being quietly more certain than it is.
  final Set<String> keptFromEarlier;

  /// Whether an earlier label existed to merge with at all.
  ///
  /// Distinct from [keptFromEarlier] being empty, which also happens when the
  /// new reading covered everything the old one did. Only this decides whether
  /// there is anything to offer replacing.
  final bool hadEarlierLabel;
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

  /// Takes one photograph and holds it, without reading anything yet.
  ///
  /// Deliberately does not read. Somebody photographing a two-sided label has
  /// to be able to turn it over before the answer is worked out, and a flow
  /// that read the first shot immediately would give them a complete-looking
  /// answer from half a label.
  Future<void> capture() async {
    final existing = switch (state) {
      CareTagCollecting(:final images) => images,
      _ => const <ScanImage>[],
    };

    final ScanImage? image;
    try {
      image = await _ref.read(imageCaptureProvider).capture();
    } on Exception catch (error) {
      state = CareTagFailed('The camera could not be opened. $error');
      return;
    }

    if (image == null) {
      // Backing out of the camera keeps whatever was already taken. Losing an
      // earlier side because the second shot was cancelled would be its own
      // small disaster.
      state = existing.isEmpty
          ? const CareTagIdle()
          : CareTagCollecting(existing);
      return;
    }

    state = CareTagCollecting([...existing, image]);
  }

  /// Drops the last photograph taken, for a shot that came out unusable.
  void discardLast() {
    if (state case CareTagCollecting(:final images) when images.isNotEmpty) {
      final kept = images.sublist(0, images.length - 1);
      state = kept.isEmpty ? const CareTagIdle() : CareTagCollecting(kept);
    }
  }

  /// Reads everything collected so far.
  Future<void> readCollected() async {
    if (state case CareTagCollecting(:final images)) {
      await readImages(images);
    }
  }

  Future<void> readImages(List<ScanImage> images) async {
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
      reading = await _ref.read(aiGatewayProvider).scanCareTag(images);
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
      state = CareTagFailed(
        images.length > 1
            ? 'Nothing on that label could be read, from any of the '
                  '${images.length} photos. Try closer, flatter shots with the '
                  'symbols in focus.'
            : 'Nothing on that label could be read. Try a closer, flatter shot '
                  'with the symbols in focus.',
      );
      return;
    }

    state = _review(item, reading, images);
  }

  /// Attaches the label to the item and re-resolves its care.
  ///
  /// The rules for doing that live in [withCareLabel], shared with the scan
  /// flow, which now reads a label from the same handful of photographs that
  /// identified the garment. What stays here is the part specific to this
  /// screen: what to tell the user about the merge.
  CareTagReviewing _review(
    WardrobeItem item,
    CareTagScanResult reading, [
    List<ScanImage> images = const [],
    bool replaceEarlier = false,
  ]) {
    final labelled = withCareLabel(
      item,
      reading,
      resolver: _ref.read(careResolverProvider),
      replaceEarlier: replaceEarlier,
    );

    return CareTagReviewing(
      reading: reading,
      updated: labelled.item,
      resolution: labelled.resolution,
      previous: item.care.instructions,
      images: images,
      keptFromEarlier: labelled.keptFromEarlier,
      hadEarlierLabel: item.careLabel != null,
    );
  }

  /// Re-runs the review with the earlier label discarded.
  ///
  /// The escape hatch the merge needs. Merging keeps a field the earlier scan
  /// read *wrong* whenever the new photograph is silent about it, and no
  /// amount of re-scanning shifts it while that symbol stays illegible. This
  /// is how somebody says "start from this reading alone".
  Future<void> replaceEarlierLabel() async {
    if (state case final CareTagReviewing reviewing) {
      final item = await _ref.read(wardrobeRepositoryProvider).byId(itemId);
      if (item == null) return;
      state = _review(item, reviewing.reading, reviewing.images, true);
    }
  }

  /// Files the label photograph against the item.
  ///
  /// `PhotoSet.careTagPhoto` exists so instructions can be re-read without
  /// digging the garment back out of the wardrobe, and nothing had ever put a
  /// photo there — the accessor and the role were both dead.
  ///
  /// Failures are swallowed, on the same reasoning the garment scan already
  /// documents: a label picture that will not store is a convenience lost,
  /// and refusing to save over it would throw away a care reading the user has
  /// just reviewed and approved. No cutout is requested — a label is text, not
  /// a garment to lift off its background.
  Future<WardrobeItem> _withLabelPhotos(
    WardrobeItem item,
    List<ScanImage> images,
  ) async {
    var updated = item;

    for (final (index, image) in images.indexed) {
      try {
        // One instant per photograph, because the name is derived from it: two
        // sides saved on the same instant would write over each other and
        // leave two records pointing at one file. The index is added for the
        // same reason — `DateTime.now()` twice in a tight loop can genuinely
        // return the same microsecond.
        final capturedAt = DateTime.now().add(Duration(microseconds: index));
        final uri = await _ref
            .read(imageStoreProvider)
            .save(
              Uint8List.fromList(image.bytes),
              name: imageName(item.id, PhotoRole.careTag, takenAt: capturedAt),
            );

        updated = updated.copyWith(
          photos: updated.photos.add(
            ItemPhoto(
              uri: uri,
              role: PhotoRole.careTag,
              capturedAt: capturedAt,
              width: image.width,
              height: image.height,
            ),
          ),
        );
      } on Exception {
        // One side that will not store should not cost the others, nor the
        // reading the user has just approved.
        continue;
      }
    }

    return updated;
  }

  Future<void> save() async {
    if (state case final CareTagReviewing reviewing) {
      final item = reviewing.images.isEmpty
          ? reviewing.updated
          : await _withLabelPhotos(reviewing.updated, reviewing.images);

      await _ref.read(wardrobeRepositoryProvider).save(item);

      // The detail screen reads the item through a cached future that nothing
      // re-queries on its own. Without this the user scans a label, taps
      // Done, and lands back on the garment exactly as it was before —
      // yesterday's care instructions, "Unknown composition" where the label
      // just supplied one, and a banner asking them to scan the label they
      // are holding. The write was fine; only the screen was old.
      _ref.invalidate(itemProvider(itemId));

      state = CareTagSaved(item);
    }
  }

  void reset() => state = const CareTagIdle();
}

final careTagControllerProvider =
    StateNotifierProvider.family<CareTagController, CareTagState, ItemId>(
      CareTagController.new,
    );
