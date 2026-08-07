/// The Drift event log, held to the core's contract.
///
/// Run with `dart test`, not `flutter test` — the contract suite imports
/// `package:test/test.dart`, and storage is deliberately free of Flutter so it
/// can be exercised against real sqlite3.
///
/// The whole suite comes from `wardrobe_core`, the same one that verifies
/// `InMemoryEventLog`. That pairing is not ceremony: the in-memory log was not
/// idempotent while this one was, and nothing noticed until a sync counted a
/// re-delivered wear twice.
library;

import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/data/drift/database.dart';
import 'package:washing_advice/data/drift/drift_event_log.dart';

import '../../../packages/wardrobe_core/test/events/event_log_test.dart'
    show runEventLogContractTests;

void main() {
  final open = <AppDatabase>[];

  tearDown(() async {
    for (final db in open) {
      await db.close();
    }
    open.clear();
  });

  runEventLogContractTests('DriftEventLog', () async {
    final db = AppDatabase(NativeDatabase.memory());
    open.add(db);
    return DriftEventLog(db);
  });

  test('an event survives a round trip through SQLite unchanged', () async {
    final db = AppDatabase(NativeDatabase.memory());
    open.add(db);
    final log = DriftEventLog(db);

    final washedAt = DateTime.utc(2026, 8, 5, 9, 30);
    await log.append(
      ItemWashed(
        id: const EventId('wash-1'),
        itemId: const ItemId('jumper'),
        occurredAt: washedAt,
        record: LaundryRecord(
          washedAt: washedAt,
          washerName: 'Bosch',
          programName: 'Easy-Care',
          temperatureC: 30,
          spinRpm: 1200,
          followedRecommendation: true,
        ),
      ),
    );

    final read = (await log.all()).single as ItemWashed;
    expect(read.record.programName, 'Easy-Care');
    expect(read.record.temperatureC, 30);
    expect(read.record.washerName, 'Bosch');
    expect(read.record.followedRecommendation, isTrue);
  });
}
