/// The listing editor, opened the way a person opens it, for the tests of it.
///
/// The whole app is built, at `/listing/:id`, with every repository in memory
/// and everything that would leave the phone replaced: the server by a fake
/// that answers what it is told to, links by one that records them, the camera
/// by prepared photographs. What a test then does is what a person does — find
/// a thing by the words on it, tap it, type in it — and reads what the app
/// stored, which is the only evidence that counts for an editor with no Save
/// button.
///
/// Shared by the tests of the editor and by nothing else.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/data/capture/image_capture_source.dart';
import 'package:washing_advice/data/images/memory_image_store.dart';
import 'package:washing_advice/main.dart';

import '../../support/recording_link_opener.dart';

/// Everything an editor test may want to look at, after [openEditor].
class EditorApp {
  EditorApp._({
    required this.listings,
    required this.wardrobe,
    required this.events,
    required this.images,
    required this.gateway,
    required this.links,
    required this.container,
  });

  final InMemoryListingRepository listings;
  final InMemoryWardrobeRepository wardrobe;
  final InMemoryEventLog events;
  final MemoryImageStore images;
  final FakePriceGateway gateway;
  final RecordingLinkOpener links;
  final ProviderContainer container;

  /// The listing as it is stored now.
  Future<Listing?> stored(String id) => listings.byId(ListingId(id));
}

/// Opens the app at [location], or at the editor for [listing] when it is
/// given and [location] is not.
///
/// [listing] and [garments] are stored first. The surface is [size] logical
/// pixels at a device pixel ratio of one, so a test can say 320 and mean it.
Future<EditorApp> openEditor(
  WidgetTester tester, {
  Listing? listing,
  List<Listing> otherListings = const [],
  List<WardrobeItem> garments = const [],
  String? location,
  Size size = const Size(400, 900),
  double textScale = 1,
  Appearance appearance = Appearance.light,
  ImageCaptureSource? camera,
  FakePriceGateway? gateway,
}) async {
  SharedPreferences.setMockInitialValues({});

  final listings = InMemoryListingRepository([?listing, ...otherListings]);
  final wardrobe = InMemoryWardrobeRepository();
  await wardrobe.saveAll(garments);
  final events = InMemoryEventLog();
  final images = MemoryImageStore();
  final links = RecordingLinkOpener();
  final server = gateway ?? FakePriceGateway();

  final container = ProviderContainer(
    overrides: [
      settingsStoreProvider.overrideWithValue(
        SettingsStore(await SharedPreferences.getInstance()),
      ),
      wardrobeRepositoryProvider.overrideWithValue(wardrobe),
      outfitRepositoryProvider.overrideWithValue(InMemoryOutfitRepository()),
      listingRepositoryProvider.overrideWithValue(listings),
      eventLogProvider.overrideWithValue(events),
      imageStoreProvider.overrideWithValue(images),
      aiGatewayProvider.overrideWithValue(server),
      linkOpenerProvider.overrideWithValue(links),
      imageCaptureProvider.overrideWithValue(
        camera ?? FixedImageCaptureSource(const []),
      ),
      idGeneratorProvider.overrideWithValue(
        SequentialIdGenerator(prefix: 'test'),
      ),
      appearanceProvider.overrideWith((ref) => appearance),
    ],
  );
  addTearDown(container.dispose);

  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: WashingAdviceApp(
        initialLocation:
            location ??
            (listing == null
                ? '/listing/none'
                : '/listing/${listing.id.value}'),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return EditorApp._(
    listings: listings,
    wardrobe: wardrobe,
    events: events,
    images: images,
    gateway: server,
    links: links,
    container: container,
  );
}

/// Loads the typeface the app is drawn in, for tests that measure text.
///
/// The test font draws every glyph a full em wide, which makes any phone look
/// too narrow for any screen and says nothing about the app.
Future<void> loadAppFont() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loader = FontLoader(rinseFontFamily);
  for (final file in ['Regular', 'SemiBold', 'Bold', 'ExtraBold']) {
    loader.addFont(rootBundle.load('assets/fonts/Nunito-$file.ttf'));
  }
  await loader.load();
}

/// What was put on the clipboard, in a test where nothing really is.
class ClipboardSpy {
  ClipboardSpy(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          text = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  /// The last text copied, or null if nothing was.
  String? text;
}

/// A draft with every field filled in, as one made from photographs of a
/// sweatshirt would be after the person had been through it.
Listing sampleListing({
  String id = 'draft-1',
  String title = 'Nike vintage crewneck sweatshirt grey',
  ItemId? itemId,
  ListingStatus status = ListingStatus.draft,
  DateTime? listedAt,
  DateTime? soldAt,
  int? soldPriceCents,
  int? priceCents,
  PriceSearch? priceSearch,
  SearchQueries? editedQueries,
  ListingFacts? facts,
  DepopCondition? condition = DepopCondition.usedExcellent,
  DepopDepartment? department = DepopDepartment.men,
  ItemType itemType = ItemType.sweatshirt,
  List<DepopColour> colours = const [DepopColour.grey],
  List<String> flaws = const ['small mark on the left cuff'],
  List<ListingPhoto> photos = const [],
  List<int> typedComparableCents = const [],
  bool typedComparablesSold = false,
  Measurements measurements = const Measurements(pitToPitIn: 22, lengthIn: 27),
}) => Listing(
  id: ListingId(id),
  itemId: itemId,
  status: status,
  createdAt: DateTime.utc(2026, 10, 15),
  updatedAt: DateTime.utc(2026, 10, 15),
  listedAt: listedAt,
  soldAt: soldAt,
  soldPriceCents: soldPriceCents,
  department: department,
  title: title,
  itemType: itemType,
  brand: 'Nike',
  sizeLabel: 'M',
  condition: condition,
  colours: colours,
  material: '80% cotton, 20% polyester',
  measurements: measurements,
  flaws: flaws,
  styleWords: const ['vintage', 'crewneck', '90s'],
  era: '90s',
  priceCents: priceCents,
  priceSearch: priceSearch,
  editedQueries: editedQueries,
  facts: facts,
  photos: photos,
  typedComparableCents: typedComparableCents,
  typedComparablesSold: typedComparablesSold,
);

/// A search that found two listings, one sold at $32 and one asking $28: the
/// middle of them is $30, which leaves $28.56 after Depop's fees.
PriceSearch sampleSearch({
  DateTime? at,
  List<SaleComparable>? comparables,
  List<RetailReference>? retail,
  ExcludedCounts excluded = ExcludedCounts.none,
  PriceSearchStatus status = PriceSearchStatus.ok,
}) => PriceSearch(
  status: status,
  searchedAt: status == PriceSearchStatus.ok
      ? (at ?? DateTime.now().toUtc().subtract(const Duration(hours: 2)))
      : null,
  provider: status == PriceSearchStatus.ok ? 'tavily' : null,
  queries: const SearchQueries(
    depop: 'Nike vintage crewneck sweatshirt grey',
    retail: 'Nike Club Fleece crew sweatshirt grey',
  ),
  comparables:
      comparables ??
      (status == PriceSearchStatus.ok
          ? [
              SaleComparable(
                title: 'Vintage Nike grey crewneck sweatshirt',
                url: Uri.parse('https://www.depop.com/products/example-1/'),
                priceCents: 3200,
                sold: true,
                condition: 'Used - Good',
                match: ComparableMatch.same,
                why: 'Same Nike crewneck, also grey',
              ),
              SaleComparable(
                title: 'Nike crewneck sweatshirt grey size M',
                url: Uri.parse('https://www.depop.com/products/example-2/'),
                priceCents: 2800,
                sold: false,
                match: ComparableMatch.same,
                why: 'Same Nike crewneck, still for sale',
              ),
            ]
          : const []),
  retail:
      retail ??
      (status == PriceSearchStatus.ok
          ? [
              RetailReference(
                title: 'Nike Club Fleece crew sweatshirt',
                url: Uri.parse('https://www.nike.com/t/club-fleece-crew'),
                priceCents: 6500,
                match: ComparableMatch.same,
                seller: 'nike.com',
              ),
            ]
          : const []),
  excluded: excluded,
);

/// The server, as far as the editor can tell: it answers a price search with
/// what it has been told to, when it is let to.
class FakePriceGateway extends AiGateway {
  FakePriceGateway({PriceSearch? search})
    : search = search ?? sampleSearch(),
      super(baseUrl: Uri.parse('http://test.invalid/'));

  /// What a price search answers.
  PriceSearch search;

  /// While set, a search waits for it to complete before it answers.
  Completer<void>? hold;

  /// Thrown instead of answering, when set.
  Object? error;

  /// Every request the editor sent, in order.
  final List<Map<String, Object?>> searched = [];

  @override
  Future<PriceSearch> searchPrices(Map<String, Object?> request) async {
    searched.add(request);
    if (hold case final Completer<void> held) await held.future;
    if (error case final Object thrown) throw thrown;
    return search;
  }
}
