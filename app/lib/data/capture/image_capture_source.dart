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

import 'package:image_picker/image_picker.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

/// A source of photographs.
abstract interface class ImageCaptureSource {
  /// Takes a photo, or returns null if the user backed out.
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
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: _maxEdge,
      maxHeight: _maxEdge,
      imageQuality: _quality,
    );
    return file == null ? null : _toScanImage(file);
  }

  @override
  Future<List<ScanImage>> pickMultiple() async {
    final files = await _picker.pickMultiImage(
      maxWidth: _maxEdge,
      maxHeight: _maxEdge,
      imageQuality: _quality,
    );
    return [for (final file in files) await _toScanImage(file)];
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
