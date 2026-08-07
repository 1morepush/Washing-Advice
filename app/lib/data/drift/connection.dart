/// Opening the on-device database.
///
/// The only Flutter-aware part of the storage layer, kept apart from
/// `database.dart` so the schema and every query can be tested with plain
/// `dart test` against sqlite3 rather than needing a Flutter binding.
library;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'database.dart';

/// The application's database, stored in the platform's documents directory
/// natively, or in IndexedDB/OPFS on the web via `web/sqlite3.wasm` and
/// `web/drift_worker.js` (compiled from `tool/drift_worker.dart`).
AppDatabase openAppDatabase() => AppDatabase(
  driftDatabase(
    name: 'washing_advice',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  ),
);

/// An in-memory database, for widget tests that need a real one.
AppDatabase openMemoryDatabase(QueryExecutor executor) => AppDatabase(executor);
