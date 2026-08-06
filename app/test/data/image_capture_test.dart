/// Taking a photograph with a real camera.
///
/// The camera itself cannot be exercised here — there is none in a container,
/// which is the whole reason capture sits behind an interface. What *can* be
/// tested is everything the app does around it, and the part that actually
/// bites a user on a phone: what happens when the camera refuses.
///
/// A `PlatformException(camera_access_denied)` shown verbatim tells someone
/// nothing about what to do next, and offering them a "Try again" that will
/// fail identically forever is worse than saying nothing at all.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';

void main() {
  ImagePickerCaptureSource sourceThat(Object? failure, {XFile? file}) =>
      ImagePickerCaptureSource(picker: _StubPicker(failure, file));

  Future<CaptureFailure> failureFrom(Future<void> Function() call) async {
    try {
      await call();
    } on CaptureFailure catch (failure) {
      return failure;
    }
    fail('expected a CaptureFailure');
  }

  group('when the camera refuses', () {
    test('a denied camera says what to do, and is not retryable', () async {
      // The important one. Tapping again cannot help — a setting has to change
      // somewhere this app cannot reach — so the screen must not offer it.
      final source = sourceThat(
        PlatformException(code: 'camera_access_denied'),
      );

      final failure = await failureFrom(source.capture);

      expect(failure.isRetryable, isFalse);
      expect(failure.message, contains('permission'));
      expect(failure.message, contains('settings'));
    });

    test('denied photos says the same about photos', () async {
      final source = sourceThat(PlatformException(code: 'photo_access_denied'));

      final failure = await failureFrom(source.pickMultiple);

      expect(failure.isRetryable, isFalse);
      expect(failure.message, contains('photos'));
    });

    test(
      'a double tap is retryable, because the first one will finish',
      () async {
        final source = sourceThat(PlatformException(code: 'multiple_request'));

        expect((await failureFrom(source.capture)).isRetryable, isTrue);
      },
    );

    test('an unreadable file is retryable with a different file', () async {
      final source = sourceThat(PlatformException(code: 'invalid_image'));

      expect((await failureFrom(source.capture)).isRetryable, isTrue);
    });

    test('an unknown platform error is retryable rather than final', () async {
      // The safe direction for something we have not seen: a user who can try
      // again is better off than one told to give up over a transient fault.
      final source = sourceThat(
        PlatformException(code: 'something_new', message: 'no camera found'),
      );

      final failure = await failureFrom(source.capture);
      expect(failure.isRetryable, isTrue);
      expect(failure.message, contains('no camera found'));
    });

    test('no message ever shows a raw exception dump', () async {
      // `PlatformException(camera_access_denied, null, null, null)` is not a
      // sentence, and it is what a user would otherwise read.
      for (final code in [
        'camera_access_denied',
        'photo_access_denied',
        'invalid_image',
        'multiple_request',
      ]) {
        final failure = await failureFrom(
          sourceThat(PlatformException(code: code)).capture,
        );
        expect(failure.message, isNot(contains('PlatformException')));
        expect(failure.message, isNot(contains(code)));
      }
    });
  });

  group('backing out', () {
    test('is not a failure', () async {
      // Someone who opens the camera and changes their mind should get the
      // screen back, not an error.
      final source = sourceThat(null);

      expect(await source.capture(), isNull);
    });

    test('picking nothing is an empty list, not a failure', () async {
      final source = sourceThat(null);

      expect(await source.pickMultiple(), isEmpty);
    });
  });

  test('a non-platform error is not swallowed', () async {
    // Only platform errors are translated. Anything else is a bug in this app
    // and should surface as itself rather than be dressed up as a camera
    // problem the user could do something about.
    final source = sourceThat(StateError('bug'));

    await expectLater(source.capture(), throwsA(isA<StateError>()));
  });
}

/// An [ImagePicker] that fails, or returns a file, on command.
class _StubPicker implements ImagePicker {
  _StubPicker(this._failure, this._file);

  final Object? _failure;
  final XFile? _file;

  Never _throw() => throw _failure!;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    if (_failure != null) _throw();
    return _file;
  }

  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    if (_failure != null) _throw();
    return [if (_file case final XFile file) file];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}
