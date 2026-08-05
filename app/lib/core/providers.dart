/// The object graph.
///
/// Riverpod is used without codegen here. The generator buys terse syntax for
/// a build step, and this file is small enough that the trade does not pay —
/// unlike Drift, where the generated code is thousands of lines nobody would
/// write by hand.
///
/// Everything the UI needs is reached through a provider, so a test or a
/// screenshot run can substitute an in-memory repository for the real database
/// by overriding one line. That is the whole reason `WardrobeRepository` is an
/// interface in the core rather than a Drift class the widgets import directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../data/api/ai_gateway.dart';
import '../data/capture/image_capture_source.dart';
import '../data/drift/connection.dart';
import '../data/drift/database.dart';
import '../data/drift/drift_event_log.dart';
import '../data/drift/drift_wardrobe_repository.dart';
import 'settings.dart';

/// The open database.
///
/// Overridden in tests and in the screenshot build; unoverridden it throws
/// rather than silently opening a file, because a widget test that quietly
/// writes to the platform documents directory is a test that will pass on one
/// machine and fail on another.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = openAppDatabase();
  ref.onDispose(db.close);
  return db;
});

final wardrobeRepositoryProvider = Provider<WardrobeRepository>(
  (ref) => DriftWardrobeRepository(ref.watch(databaseProvider)),
);

/// The filters and sort currently applied to the wardrobe screen.
///
/// Held as a whole [WardrobeQuery] rather than as a scattering of separate
/// booleans, so "what is the user looking at" is one value that can be logged,
/// restored, or — later — produced by a natural-language parser.
final wardrobeQueryProvider = StateProvider<WardrobeQuery>(
  (ref) => const WardrobeQuery.owned(),
);

/// The items matching the current query, kept live.
///
/// A stream rather than a future: saving an item after a scan has to make it
/// appear in the list without anyone remembering to refresh, and Drift already
/// knows which queries a write invalidates.
final wardrobeItemsProvider = StreamProvider<List<WardrobeItem>>((ref) {
  final query = ref.watch(wardrobeQueryProvider);
  return ref.watch(wardrobeRepositoryProvider).watch(query);
});

/// How many items the user owns in total, regardless of the current filter.
///
/// Lets the list say "12 of 40" instead of leaving someone to wonder whether
/// an empty screen means an empty wardrobe or a filter they forgot about.
final ownedCountProvider = FutureProvider<int>(
  (ref) =>
      ref.watch(wardrobeRepositoryProvider).count(const WardrobeQuery.owned()),
);

/// Brands present in the wardrobe, for the filter sheet.
final knownBrandsProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(wardrobeRepositoryProvider).knownBrands(),
);

/// A single item, watched so an edit on the detail screen is reflected at once.
final itemProvider = FutureProvider.family<WardrobeItem?, ItemId>(
  (ref, id) => ref.watch(wardrobeRepositoryProvider).byId(id),
);

/// The scan backend, rebuilt when the configured URL changes.
///
/// Typed as [AiGateway] rather than [VisionPort] only because the scan screen
/// reads `lastDiagnostics` off it. Everything that merely *scans* depends on
/// the core's interface.
final aiGatewayProvider = Provider<AiGateway>((ref) {
  final gateway = AiGateway(baseUrl: _baseUri(ref.watch(backendUrlProvider)));
  ref.onDispose(gateway.close);
  return gateway;
});

/// Normalises whatever the user typed in settings into a usable base.
///
/// A trailing slash matters to `Uri.resolve`: without one, `resolve('v1/scan')`
/// against `http://host/api` drops the `api` segment, which would send every
/// request to the wrong path with no obvious cause.
Uri _baseUri(String raw) {
  final parsed = Uri.parse(raw.trim());
  return parsed.path.endsWith('/')
      ? parsed
      : parsed.replace(path: '${parsed.path}/');
}

/// Where photographs come from.
///
/// Overridden with a [FixedImageCaptureSource] in tests and in the screenshot
/// run, which is what makes the scan flow drivable without a camera.
final imageCaptureProvider = Provider<ImageCaptureSource>(
  (ref) => ImagePickerCaptureSource(),
);

/// Appends events and keeps the cached counters on an item in step.
///
/// The event log is the source of truth and [UsageStats] is a projection of it;
/// pairing the two writes in one place is what stops them diverging.
final wardrobeRecorderProvider = Provider<WardrobeRecorder>(
  (ref) => WardrobeRecorder(
    items: ref.watch(wardrobeRepositoryProvider),
    events: ref.watch(eventLogProvider),
  ),
);

final eventLogProvider = Provider<EventLog>(
  (ref) => DriftEventLog(ref.watch(databaseProvider)),
);

/// New identifiers. Overridden in tests so ids are predictable.
final idGeneratorProvider = Provider<IdGenerator>((ref) => RandomIdGenerator());

/// The care rule table.
///
/// A provider rather than a bare constant so a future build can swap in extra
/// rule sources — a brand's published instructions, say — without touching the
/// scan flow that consumes it.
final careResolverProvider = Provider<CareResolver>(
  (ref) => const CareResolver(),
);
