/// Getting an image from the user.
///
/// This is the one part of the app that cannot be exercised in CI: there is no
/// camera in a container. So it is deliberately the smallest interface that
/// will do, with everything downstream of it — upload, parsing, review, save —
/// running against ordinary bytes and therefore fully testable.
///
/// On a phone [ImagePickerCaptureSource] opens the camera; on the web it opens
/// a file dialog. That is the same class either way, which is why the whole
/// scan flow can be driven in a browser here.
library;

import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

/// A photograph could not be taken.
///
/// Platform errors are translated here rather than in each screen, because the
/// distinction that matters to a screen is not the error code — it is whether
/// tapping the button again could possibly work. A denied permission cannot be
/// retried by trying again; it needs the user to change a setting, and offering
/// them a "Try again" that will fail identically forever is worse than saying
/// nothing.
class CaptureFailure implements Exception {
  const CaptureFailure(this.message, {required this.isRetryable});

  final String message;

  /// Whether tapping again has any chance of succeeding.
  final bool isRetryable;

  @override
  String toString() => message;
}

/// A source of photographs.
abstract interface class ImageCaptureSource {
  /// Takes a photo, or returns null if the user backed out.
  ///
  /// Throws [CaptureFailure] when the camera could not be opened at all.
  /// Backing out is *not* a failure and returns null: someone who changes
  /// their mind should get the screen back, not an error.
  Future<ScanImage?> capture();

  /// Picks one or more existing images.
  Future<List<ScanImage>> pickMultiple();
}

class ImagePickerCaptureSource implements ImageCaptureSource {
  ImagePickerCaptureSource({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// Capped so a 12-megapixel photo is not uploaded whole.
  ///
  /// A garment fills the frame and its care label is read from a close-up, so
  /// nothing here needs more than about 1600px. The saving is mostly the user's
  /// mobile data and the time they spend watching a progress spinner.
  static const _maxEdge = 1600.0;
  static const _quality = 85;

  @override
  Future<ScanImage?> capture() async {
    final file = await _translating(
      () => _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: _maxEdge,
        maxHeight: _maxEdge,
        imageQuality: _quality,
      ),
    );
    return file == null ? null : _toScanImage(file);
  }

  @override
  Future<List<ScanImage>> pickMultiple() async {
    final files = await _translating(
      () => _picker.pickMultiImage(
        maxWidth: _maxEdge,
        maxHeight: _maxEdge,
        imageQuality: _quality,
      ),
    );
    return [for (final file in files) await _toScanImage(file)];
  }

  /// Turns a platform error into something a person can act on.
  ///
  /// The codes come from `image_picker`. They are matched rather than passed
  /// through because `PlatformException(camera_access_denied, null, null, null)`
  /// on screen tells a user nothing about what to do next.
  Future<T> _translating<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (error) {
      throw switch (error.code) {
        'camera_access_denied' => const CaptureFailure(
          'Washing Advice does not have permission to use the camera. '
          'Turn it on in your phone settings, then try again.',
          // Not retryable: the button will fail identically until a setting
          // changes somewhere this app cannot reach.
          isRetryable: false,
        ),
        'photo_access_denied' => const CaptureFailure(
          'Washing Advice does not have permission to use your photos. '
          'Turn it on in your phone settings, then try again.',
          isRetryable: false,
        ),
        'invalid_image' => const CaptureFailure(
          'That file is not an image this app can read.',
          isRetryable: true,
        ),
        // A second request while one is in flight — a double tap, essentially.
        // Retrying once the first finishes is exactly right.
        'multiple_request' => const CaptureFailure(
          'Still working on the last photo. Try again in a moment.',
          isRetryable: true,
        ),
        _ => CaptureFailure(
          'The camera could not be opened. ${error.message ?? error.code}',
          isRetryable: true,
        ),
      };
    }
  }
}

Future<ScanImage> _toScanImage(XFile file) async => ScanImage(
  bytes: await file.readAsBytes(),
  // `image_picker` reports the type on web and often not on mobile, where
  // the compressor above has already re-encoded to JPEG.
  mimeType: file.mimeType ?? 'image/jpeg',
);

/// A source that returns prepared bytes.
///
/// Used by tests and by the screenshot run, so the scan flow can be driven from
/// end to end without a camera.
class FixedImageCaptureSource implements ImageCaptureSource {
  FixedImageCaptureSource(this.images);

  final List<ScanImage> images;

  @override
  Future<ScanImage?> capture() async => images.isEmpty ? null : images.first;

  @override
  Future<List<ScanImage>> pickMultiple() async => images;
}
