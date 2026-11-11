/// When to mention that there is no recent backup.
///
/// Said quietly, on the settings screen, to the person who is already there.
/// It is never a notification: a wardrobe that nags is one people stop
/// opening, and the cost of not being told is only ever a missing line of text.
library;

enum BackupNudge {
  /// Nothing to say.
  none,

  /// There is a wardrobe and never has been a backup of it.
  neverBackedUp,

  /// The last backup is old, and the wardrobe has grown since.
  outOfDate,
}

/// How old a backup has to be before it is worth a mention.
const Duration backupStaleAfter = Duration(days: 30);

/// Whether to nudge, and about what.
///
/// [garmentsNow] and [garmentsAtLastBackup] count the same thing — the
/// garments the person owns — so growth means something. A backup that is
/// over a month old but of a wardrobe that has not changed size is not out of
/// date in any way worth interrupting for, so says nothing; the line showing
/// when it was made is still there for anyone who wants to look.
///
/// An empty wardrobe has nothing to lose and gets no nudge.
BackupNudge backupNudge({
  required DateTime? lastBackupAt,
  required int? garmentsAtLastBackup,
  required int garmentsNow,
  required DateTime now,
}) {
  if (garmentsNow <= 0) return BackupNudge.none;
  if (lastBackupAt == null) return BackupNudge.neverBackedUp;

  final old = now.difference(lastBackupAt) > backupStaleAfter;
  final grown = garmentsNow > (garmentsAtLastBackup ?? 0);
  return old && grown ? BackupNudge.outOfDate : BackupNudge.none;
}
