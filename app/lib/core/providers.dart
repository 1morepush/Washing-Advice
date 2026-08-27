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
import '../data/images/image_store.dart';
import '../data/drift/drift_event_log.dart';
import '../data/drift/drift_outfit_repository.dart';
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

/// How the wardrobe is laid out.
///
/// A grid is the better default now that items carry cutouts: a wall of
/// garments on transparency is scannable by shape and colour before a single
/// word is read, which is how people find things in an actual wardrobe. The
/// list survives because it fits far more items on a screen and shows the full
/// fabric composition, which is what you want when comparing rather than
/// hunting.
enum WardrobeView { grid, list }

final wardrobeViewProvider = StateProvider<WardrobeView>(
  (ref) => WardrobeView.grid,
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

/// Countries any garment says it was made in, for the filter sheet.
final knownCountriesProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(wardrobeRepositoryProvider).knownCountries(),
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

/// Where photographs and cutouts are kept.
///
/// Overridden in `main()` with a platform store, and in tests and the demo
/// with an in-memory one. Unoverridden it throws rather than silently writing
/// files, for the same reason the database provider does.
final imageStoreProvider = Provider<ImageStore>(
  (ref) => throw StateError(
    'imageStoreProvider must be overridden in main() with a platform store',
  ),
);

/// New identifiers. Overridden in tests so ids are predictable.
final idGeneratorProvider = Provider<IdGenerator>((ref) => RandomIdGenerator());

/// Recognises a garment as something already in the wardrobe.
///
/// A provider rather than a constant so an embedding-based matcher can be
/// added beside the attribute one later without the pile flow changing.
final itemMatcherProvider = Provider<ItemMatcher>(
  (ref) => const AttributeMatcher(),
);

/// Turns ranked candidates into recognised / confirm / new.
final matchResolverProvider = Provider<MatchResolver>(
  (ref) => const MatchResolver(),
);

/// Groups items into loads and names the programmes.
final laundrySorterProvider = Provider<LaundrySorter>(
  (ref) => LaundrySorter(
    preferences: SortingPreferences(
      splitDrying: ref.watch(splitDryingProvider),
    ),
  ),
);

/// The care rule table.
///
/// A provider rather than a bare constant so a future build can swap in extra
/// rule sources — a brand's published instructions, say — without touching the
/// scan flow that consumes it.
final careResolverProvider = Provider<CareResolver>(
  (ref) => const CareResolver(),
);

/// Everything the user owns, unfiltered.
///
/// Separate from [wardrobeItemsProvider], which is deliberately narrowed by
/// whatever the wardrobe screen's search box says. Analytics computed over a
/// filtered list would quietly answer a different question from the one on
/// screen — "8% of my wardrobe is wool" is wrong if it means 8% of the four
/// things matching "jum".
final ownedItemsProvider = StreamProvider<List<WardrobeItem>>(
  (ref) =>
      ref.watch(wardrobeRepositoryProvider).watch(const WardrobeQuery.owned()),
);

/// What the wardrobe adds up to.
final wardrobeSummaryProvider = Provider<AsyncValue<WardrobeSummary>>(
  (ref) => ref.watch(ownedItemsProvider).whenData(WardrobeSummary.new),
);

/// What the wardrobe has been observed being worn together.
///
/// Derived from the event log rather than stored, so there is no second source
/// of truth to keep in step and it applies to history the app already has —
/// someone who has been logging wears for a month has a graph immediately.
final coWearGraphProvider = FutureProvider<RelationshipGraph>(
  (ref) async =>
      CoWearProjection.graphFrom(await ref.watch(eventLogProvider).all()),
);

/// Suggests things to wear.
///
/// Fed by [coWearGraphProvider], which closes the loop the feature was missing:
/// the app records what is worn, and that changes what it suggests next.
/// Before the graph resolves the builder runs without it, which is exactly its
/// documented no-history behaviour — suggestions arrive immediately from
/// colour and usage, then improve.
final outfitBuilderProvider = Provider<OutfitBuilder>(
  (ref) =>
      OutfitBuilder(relationships: ref.watch(coWearGraphProvider).valueOrNull),
);

final packingPlannerProvider = Provider<PackingPlanner>(
  (ref) => const PackingPlanner(),
);

/// Saved outfits.
final outfitRepositoryProvider = Provider<OutfitRepository>(
  (ref) => DriftOutfitRepository(ref.watch(databaseProvider)),
);

/// The saved outfits, kept live so saving one makes it appear.
final savedOutfitsProvider = StreamProvider<List<Outfit>>(
  (ref) => ref.watch(outfitRepositoryProvider).watch(),
);

/// A saved outfit resolved to the items it references.
///
/// Items are looked up rather than stored on the outfit, so an edited or
/// deleted garment is reflected immediately. Anything missing is dropped from
/// the result rather than rendered as a gap: the repository already deletes
/// outfits that fall below two items, so a missing one here means a race, not
/// a state worth drawing.
final outfitItemsProvider = FutureProvider.family<List<WardrobeItem>, OutfitId>(
  (ref, id) async {
    final outfit = await ref.watch(outfitRepositoryProvider).byId(id);
    if (outfit == null) return const [];

    final items = <WardrobeItem>[];
    for (final itemId in outfit.itemIds) {
      final item = await ref.watch(wardrobeRepositoryProvider).byId(itemId);
      if (item != null) items.add(item);
    }
    return items;
  },
);

/// What the outfits screen is currently asking for.
final outfitRequestProvider = StateProvider<OutfitRequest>(
  (ref) => const OutfitRequest(),
);

final outfitSuggestionsProvider = Provider<AsyncValue<List<OutfitSuggestion>>>(
  (ref) => ref
      .watch(ownedItemsProvider)
      .whenData(
        (items) => ref
            .watch(outfitBuilderProvider)
            .suggest(items, ref.watch(outfitRequestProvider)),
      ),
);

/// The trip the packing screen is planning for.
final tripSpecProvider = StateProvider<TripSpec>(
  (ref) => const TripSpec(days: 5),
);

final packingListProvider = Provider<AsyncValue<PackingList>>(
  (ref) => ref
      .watch(ownedItemsProvider)
      .whenData(
        (items) => ref
            .watch(packingPlannerProvider)
            .plan(items, ref.watch(tripSpecProvider)),
      ),
);
