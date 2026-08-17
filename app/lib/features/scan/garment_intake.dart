/// Turning a handful of photographs into a garment in the wardrobe.
///
/// Extracted from the scan controller when a second caller appeared. Adding one
/// garment and adding forty are the same work repeated, and the part that is
/// genuinely fiddly — which shots go to which reader, how a label is laid over
/// a draft, which photograph earns a cutout, keeping the item row and the event
/// log in step — must not exist twice. The controllers differ in what they show
/// while it happens, which is all they should differ in.
///
/// Nothing here touches state. It reads photographs and writes items, and the
/// callers decide what that looks like on a screen.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../data/api/ai_gateway.dart';
import '../../data/api/scan_dto.dart';
import '../../data/images/image_store.dart';
import 'care_label_merge.dart';
import 'scan_controller.dart' show ScanShot;

/// A garment identified but not yet written down.
final class GarmentDraft {
  const GarmentDraft({
    required this.draft,
    required this.result,
    required this.shots,
    this.label,
    this.labelUnread = false,
    this.diagnostics,
  });

  final WardrobeItem draft;
  final GarmentScanResult result;
  final List<ScanShot> shots;

  /// The care label read from the same batch, if one was photographed.
  final CareTagScanResult? label;

  /// Whether a label was photographed and came back with nothing usable.
  ///
  /// Distinct from [label] being null, which is also the ordinary case of no
  /// tag at all. The user took that photograph on purpose, and a screen that
  /// stayed silent would leave them believing the manufacturer's instructions
  /// were in hand when a guess is showing.
  final bool labelUnread;

  final ScanDiagnostics? diagnostics;

  GarmentDraft withDraft(WardrobeItem revised) => GarmentDraft(
    draft: revised,
    result: result,
    shots: shots,
    label: label,
    labelUnread: labelUnread,
    diagnostics: diagnostics,
  );
}

/// A garment could not be identified.
///
/// Carries the same retryable distinction the gateway does, because "the
/// server is asleep" and "this version cannot read that reply" need different
/// words and different buttons.
class IntakeFailure implements Exception {
  const IntakeFailure(this.message, {this.isRetryable = true});

  final String message;
  final bool isRetryable;

  @override
  String toString() => message;
}

class GarmentIntake {
  const GarmentIntake(this._ref);

  final Ref _ref;

  /// Reads a garment from photographs, including its label if one is among
  /// them.
  ///
  /// Shots marked as the care label are split off and read by the label
  /// scanner rather than being handed to the garment one. They are different
  /// questions — what is this, and what does the manufacturer say about
  /// washing it — and a photograph of a tag tells the garment reader almost
  /// nothing.
  Future<GarmentDraft> read(List<ScanShot> shots) async {
    final garment = [
      for (final shot in shots)
        if (shot.role != PhotoRole.careTag) shot.image,
    ];
    final label = [
      for (final shot in shots)
        if (shot.role == PhotoRole.careTag) shot.image,
    ];

    if (garment.isEmpty) {
      // A label on its own identifies nothing. Worth saying plainly rather
      // than sending it to the garment reader and relaying whatever it makes
      // of a photograph of a tag.
      throw const IntakeFailure(
        'There is no photo of the garment itself here — only its label. Add a '
        'photo of the garment so it can be identified.',
        isRetryable: false,
      );
    }

    final gateway = _ref.read(aiGatewayProvider);
    final GarmentScanResult result;
    try {
      result = await gateway.scanGarment(garment);
    } on ScanFailure catch (failure) {
      throw IntakeFailure(failure.message, isRetryable: failure.isRetryable);
    } on ScanContractError catch (error) {
      // Deliberately distinct wording. This is the app and the server
      // disagreeing about the contract, and no amount of retrying fixes it.
      throw IntakeFailure(
        'The server sent something this version cannot read. $error',
        isRetryable: false,
      );
    }

    var draft = _draftFrom(result);

    CareTagScanResult? reading;
    if (label.isNotEmpty) {
      reading = await _readLabel(label);
      if (reading != null) {
        draft = withCareLabel(
          draft,
          reading,
          resolver: _ref.read(careResolverProvider),
        ).item;
      }
    }

    return GarmentDraft(
      draft: draft,
      result: result,
      shots: shots,
      label: reading,
      labelUnread: label.isNotEmpty && reading == null,
      diagnostics: gateway.lastDiagnostics,
    );
  }

  /// Reads the label shots, or returns null if they said nothing usable.
  ///
  /// Failure here never fails the scan. The garment has already been
  /// identified and is worth saving; an unreadable tag costs the user the care
  /// instructions, which they can scan again from the item screen at their
  /// leisure. Throwing away a good garment reading because the label photo was
  /// blurred would be the tail wagging the dog.
  Future<CareTagScanResult?> _readLabel(List<ScanImage> images) async {
    try {
      final reading = await _ref.read(aiGatewayProvider).scanCareTag(images);
      // A label stating nothing must not be attached. It would replace a
      // rule-derived profile with an empty one recorded at `tagScan`
      // provenance, making the app more confident about care it learned
      // nothing new about.
      return reading.instructions.statesNothing ? null : reading;
    } on ScanFailure {
      return null;
    } on ScanContractError {
      return null;
    }
  }

  /// Writes a reviewed garment to the wardrobe, photographs and all.
  Future<WardrobeItem> commit(WardrobeItem draft, List<ScanShot> shots) async {
    final ids = _ref.read(idGeneratorProvider);
    final item = await _withPhotos(draft, shots);

    await _ref.read(wardrobeRepositoryProvider).save(item);
    // The item row and the event are two records of the same happening. The
    // row is what the wardrobe screen reads; the event is what makes the
    // history replayable, and without it "added on" would be a field nobody
    // could verify.
    await _ref
        .read(eventLogProvider)
        .append(
          ItemAdded(
            id: EventId(ids.next()),
            itemId: item.id,
            occurredAt: item.addedAt,
            recordedAt: DateTime.now(),
          ),
        );
    return item;
  }

  /// Recomputes the care profile from the item's own facts.
  ///
  /// `forItem` rather than `resolve`, and that is load-bearing now that a
  /// garment can arrive with its label already attached. It passes the label
  /// and its confidence through, so correcting the fabric on the review screen
  /// re-runs the rules *underneath* the manufacturer's instruction instead of
  /// quietly demoting a tag scan back to a guess.
  ///
  /// For a garment scanned without a tag there is no label to pass and this
  /// behaves exactly as the plain resolve did: the rule table reasoning about
  /// fabric, reporting itself as inference, which is what raises the "scan the
  /// label" prompt on the items that need it.
  WardrobeItem reresolveCare(WardrobeItem item) => item.copyWith(
    care: _ref.read(careResolverProvider).forItem(item).profile,
  );

  /// Stores the captured photographs and asks the server for a cutout.
  ///
  /// Failures here are swallowed on purpose. A missing picture is a cosmetic
  /// loss; refusing to save the garment over it would throw away a scan the
  /// user has already reviewed and approved, which is a far worse outcome than
  /// a row that falls back to its colour swatch.
  Future<WardrobeItem> _withPhotos(
    WardrobeItem item,
    List<ScanShot> shots,
  ) async {
    if (shots.isEmpty) return item;

    final store = _ref.read(imageStoreProvider);
    final gateway = _ref.read(aiGatewayProvider);
    final now = DateTime.now();

    var photos = item.photos;
    // The front is cut out, and only once. Two photographs both marked front —
    // which the user is free to do — would otherwise mean two uploads and a
    // second file overwriting the first.
    var cutoutDone = false;

    for (final (index, shot) in shots.indexed) {
      final role = shot.role;
      // Distinct per photograph, because the stored name is derived from it.
      // Without this two details, or two backs, resolve to one name: the
      // second overwrites the first and the set ends up with two records
      // pointing at one file, carrying the wrong dimensions for one of them.
      final capturedAt = now.add(Duration(microseconds: index));

      try {
        final uri = await store.save(
          Uint8List.fromList(shot.image.bytes),
          name: imageName(item.id, role, takenAt: capturedAt),
        );

        String? cutoutUri;
        if (role == PhotoRole.front && !cutoutDone) {
          cutoutDone = true;
          final cutout = await gateway.cutout(shot.image);
          if (cutout != null) {
            cutoutUri = await store.save(
              cutout,
              name: imageName(item.id, role, takenAt: capturedAt, cutout: true),
            );
          }
        }

        photos = photos.add(
          ItemPhoto(
            uri: uri,
            cutoutUri: cutoutUri,
            role: role,
            capturedAt: capturedAt,
            width: shot.image.width,
            height: shot.image.height,
          ),
        );
      } on Exception {
        // Storage full, permission revoked, disk error. Keep going: the other
        // photographs and the item itself are still worth saving.
        continue;
      }
    }

    return item.copyWith(photos: photos);
  }

  /// Turns a scan result into a saveable item.
  ///
  /// The care profile is *derived*, not carried over: the vision layer reports
  /// what it saw, and the core's rule table decides what that means for washing
  /// it. Letting a model state care directly would put laundry judgement in the
  /// provider, which is exactly what the rule table exists to prevent.
  WardrobeItem _draftFrom(GarmentScanResult result) {
    final now = DateTime.now();
    final draft = WardrobeItem(
      id: ItemId(_ref.read(idGeneratorProvider).next()),
      name: result.suggestedName ?? result.type.value.label,
      type: result.type,
      composition:
          result.composition ??
          Confident(
            FabricComposition(const {}),
            confidence: 0,
            source: Provenance.fallbackDefault,
          ),
      colors: result.colors,
      brand: result.brand,
      pattern: result.pattern,
      sleeveLength: result.sleeveLength?.value,
      fit: result.fit?.value,
      styleCut: result.styleCut?.value,
      seasons: result.seasons,
      distinguishingText: result.distinguishingText,
      care: const CareProfile.unknown(),
      addedAt: now,
      updatedAt: now,
    );
    return reresolveCare(draft);
  }
}

final garmentIntakeProvider = Provider<GarmentIntake>(GarmentIntake.new);
