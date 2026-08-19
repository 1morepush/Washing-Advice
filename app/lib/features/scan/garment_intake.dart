/// Turning a handful of photographs into a garment in the wardrobe.
///
/// Shared by the single scan and the bulk flow, which differ only in what they
/// show while it happens. Nothing here touches state.
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
  /// Distinct from [label] being null, which also covers the ordinary case of
  /// no tag at all. Screens say so rather than letting somebody believe the
  /// manufacturer's instructions are in hand when a guess is showing.
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
/// Carries the gateway's retryable distinction: "the server is asleep" and
/// "this version cannot read that reply" need different words and buttons.
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
  /// Label shots go to the label reader rather than the garment one: a
  /// photograph of a tag tells the garment reader almost nothing.
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
      // A label on its own identifies nothing, and saying so beats relaying
      // whatever the garment reader makes of a photograph of a tag.
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
      // The app and the server disagreeing about the contract; retrying it
      // cannot help, hence the different wording.
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
  /// Never fails the scan: the garment is already identified and worth saving,
  /// and the label can be scanned again later from the item screen.
  Future<CareTagScanResult?> _readLabel(List<ScanImage> images) async {
    try {
      final reading = await _ref.read(aiGatewayProvider).scanCareTag(images);
      // A label stating nothing must not be attached: it would replace a
      // rule-derived profile with an empty one at `tagScan` provenance, making
      // the app more confident about care it learned nothing about.
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
    // The row is what the wardrobe screen reads; the event is what makes the
    // history replayable.
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
  /// `forItem` rather than `resolve`, because a garment can now arrive with a
  /// label attached: it passes that label through, so correcting the fabric
  /// cannot quietly demote a tag scan back to a guess.
  WardrobeItem reresolveCare(WardrobeItem item) => item.copyWith(
    care: _ref.read(careResolverProvider).forItem(item).profile,
  );

  /// Stores the captured photographs and asks the server for a cutout.
  ///
  /// Failures are swallowed: a missing picture is cosmetic, and refusing to
  /// save over it would throw away a scan the user already approved.
  Future<WardrobeItem> _withPhotos(
    WardrobeItem item,
    List<ScanShot> shots,
  ) async {
    if (shots.isEmpty) return item;

    final store = _ref.read(imageStoreProvider);
    final gateway = _ref.read(aiGatewayProvider);
    final now = DateTime.now();

    var photos = item.photos;
    // Only the front is cut out, and only once: two shots both marked front
    // would otherwise mean two uploads and the second overwriting the first.
    var cutoutDone = false;

    for (final (index, shot) in shots.indexed) {
      final role = shot.role;
      // Distinct per photograph, because the stored name derives from it:
      // otherwise two details resolve to one name and overwrite each other.
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
        // Storage full, permission revoked, disk error. The other photographs
        // and the item itself are still worth saving.
        continue;
      }
    }

    return item.copyWith(photos: photos);
  }

  /// Turns a scan result into a saveable item.
  ///
  /// The care profile is derived rather than carried over: the vision layer
  /// reports what it saw and the core's rule table decides what that means.
  /// Letting a model state care directly would put laundry judgement in the
  /// provider.
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
