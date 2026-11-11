/// Backup files in a browser, which is where the app is mostly used.
///
/// Saving is a download: a Blob, a temporary link, a click. That is what an
/// installed home-screen web app on an iPhone offers too, and the file lands in
/// Files > Downloads. Nothing here needs a service worker or a server.
///
/// Picking uses `file_selector`, whose web implementation is an `<input
/// type=file>`; the person's gesture that opened it is what lets it open.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' as selector;
import 'package:web/web.dart' as web;

import 'backup_files_port.dart';

const _zip = selector.XTypeGroup(
  label: 'Washing Advice backup',
  extensions: ['zip'],
  mimeTypes: ['application/zip'],
);

class PlatformBackupFiles implements BackupFiles {
  const PlatformBackupFiles();

  @override
  Future<BackupHandover> save(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/zip'),
    );
    final url = web.URL.createObjectURL(blob);
    try {
      final link = web.HTMLAnchorElement()
        ..href = url
        ..download = fileName
        ..style.display = 'none';
      web.document.body?.append(link);
      link.click();
      link.remove();
    } finally {
      // Not at once: a browser that has not finished reading the blob would
      // be left with a dead link, and a download that starts and fails.
      Future<void>.delayed(
        const Duration(seconds: 30),
        () => web.URL.revokeObjectURL(url),
      );
    }
    return BackupHandover.done;
  }

  @override
  Future<PickedBackupFile?> pick() async {
    final file = await selector.openFile(acceptedTypeGroups: const [_zip]);
    if (file == null) return null;
    return PickedBackupFile(name: file.name, bytes: await file.readAsBytes());
  }
}
