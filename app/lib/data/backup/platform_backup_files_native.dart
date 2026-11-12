/// Backup files on a phone or desktop.
///
/// Saving uses the share sheet on Android and iOS, which is the one control
/// both platforms offer for "put this file somewhere I keep files" — Files,
/// Drive, an email to oneself — and which a person already knows. On a desktop
/// there is no share sheet worth the name, so it is a save dialog.
///
/// Picking uses `file_selector`, the Flutter team's own plugin, which reaches
/// the system document picker on both phones.
library;

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as selector;
import 'package:share_plus/share_plus.dart';

import 'backup_files_port.dart';

const _zip = selector.XTypeGroup(
  label: 'Washing Advice backup',
  extensions: ['zip'],
  mimeTypes: ['application/zip'],
  uniformTypeIdentifiers: ['public.zip-archive'],
);

class PlatformBackupFiles implements BackupFiles {
  const PlatformBackupFiles();

  @override
  Future<BackupHandover> save(
    Uint8List bytes, {
    required String fileName,
  }) async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final location = await selector.getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [_zip],
      );
      if (location == null) return BackupHandover.cancelled;
      await selector.XFile.fromData(
        bytes,
        mimeType: 'application/zip',
        name: fileName,
      ).saveTo(location.path);
      return BackupHandover.done;
    }

    final result = await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(bytes, mimeType: 'application/zip', name: fileName),
        ],
        fileNameOverrides: [fileName],
        subject: fileName,
      ),
    );
    // Where the platform will not say what happened, believe the person.
    return result.status == ShareResultStatus.dismissed
        ? BackupHandover.cancelled
        : BackupHandover.done;
  }

  @override
  Future<PickedBackupFile?> pick() async {
    final file = await selector.openFile(acceptedTypeGroups: const [_zip]);
    if (file == null) return null;
    return PickedBackupFile(name: file.name, bytes: await file.readAsBytes());
  }
}
