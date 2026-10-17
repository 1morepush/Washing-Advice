/// A [LinkOpener] that opens nothing and remembers what it was asked to, for
/// tests.
library;

import 'package:washing_advice/core/link_opener.dart';

final class RecordingLinkOpener implements LinkOpener {
  RecordingLinkOpener({this.succeeds = true});

  /// What [open] answers: whether anything opened.
  bool succeeds;

  /// Every address asked for, in order.
  final List<Uri> opened = [];

  /// The last address asked for, or null if none was.
  Uri? get last => opened.isEmpty ? null : opened.last;

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return succeeds;
  }
}
