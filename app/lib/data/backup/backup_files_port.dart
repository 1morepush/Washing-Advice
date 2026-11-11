/// Getting a backup file off the app, and onto it.
///
/// The one place that differs by platform. A browser has no share sheet and no
/// save dialog it can drive: it downloads. A phone has a share sheet, which on
/// both Android and iOS includes "save to files". A desktop has a save dialog.
/// Everything above this line asks for a file and gets one, and a test hands
/// in a fake that remembers what it was given.
library;

import 'dart:typed_data';

/// What became of a backup handed to the person.
enum BackupHandover {
  /// Downloaded, shared or saved. As far as the app can tell, it went
  /// somewhere.
  done,

  /// The person closed the sheet or dialog without choosing anywhere.
  cancelled,
}

/// A file the person chose to restore from.
final class PickedBackupFile {
  const PickedBackupFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

abstract interface class BackupFiles {
  /// Hands [bytes] to the person under [fileName].
  Future<BackupHandover> save(Uint8List bytes, {required String fileName});

  /// Asks the person for a backup file, or null if they decline.
  Future<PickedBackupFile?> pick();
}
