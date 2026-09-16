/// The composition root.
///
/// The only place that both constructs things and knows about Flutter. Every
/// other file either describes the domain (and lives in `wardrobe_core`) or
/// asks a provider for what it needs.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/providers.dart';
import 'core/router.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'data/images/image_store.dart';
import 'data/images/memory_image_store.dart';
import 'data/images/store_factory.dart';
import 'data/notifications/local_nudges.dart';
import 'data/notifications/nudges.dart';
import 'features/laundry/evening_nudge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Settings are read before the first frame rather than awaited inside a
  // provider, so no screen has to render a spinner while waiting to find out
  // where the backend is.
  //
  // Both of these open platform storage, and on the web that is a browser API
  // that can simply refuse: private browsing, a wiped origin, a quota, an
  // engine that will not give an installed page a filesystem. Unguarded, any
  // of those throws before `runApp` and the app is a permanently blank page —
  // no error, nothing to report, nothing to try. That is the worst outcome
  // available, and it is also the one that has actually happened here.
  final SharedPreferences prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (error, stack) {
    // Nothing survives this: the backend address, the sync token and every
    // machine profile live here, so there is no useful degraded app to offer.
    debugPrint('Washing Advice could not read its settings: $error\n$stack');
    runApp(StartupFailureApp(error: error));
    return;
  }

  // The picture store is a *second* database, and it failing does not stop the
  // wardrobe working — items, care profiles and history are all in the first.
  // Falling back to memory keeps the app fully usable and costs only that
  // photographs taken this session are not kept, which is a far better outcome
  // than refusing to start over the one part that is decoration.
  ImageStore images;
  try {
    images = await openImageStore();
  } catch (error, stack) {
    debugPrint(
      'Washing Advice could not open its picture store: $error\n$stack',
    );
    images = MemoryImageStore();
  }

  // Reminders: the platform's own notifications on a phone, nothing on the
  // web, where no browser can schedule one for later. A phone whose
  // notifications will not start still has a wardrobe, so that failure is
  // logged and the feature is absent rather than the app.
  Nudges nudges = const NoNudges();
  if (!kIsWeb) {
    try {
      nudges = await LocalNudges.open();
    } catch (error, stack) {
      debugPrint('Washing Advice could not set up reminders: $error\n$stack');
    }
  }

  final settings = SettingsStore(prefs);

  // The platform's schedule is re-stated from the stored setting on every
  // launch rather than trusted to survive updates and cleared data. Not
  // awaited: nothing on screen depends on it.
  unawaited(NudgeScheduler(nudges).apply(nudgeTimeOf(settings)));

  // Read before the first frame, so a tap on the reminder while the app was
  // closed opens the screen it was for — not the wardrobe, then a jump.
  final launchRoute = await nudges.launchRoute();

  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(settings),
        // Seeded here rather than read on demand: see `splitDryingProvider`.
        splitDryingProvider.overrideWith((ref) => settings.splitDrying),
        separateWashingProvider.overrideWith((ref) => settings.separateWashing),
        imageStoreProvider.overrideWithValue(images),
        nudgesProvider.overrideWithValue(nudges),
      ],
      child: WashingAdviceApp(initialLocation: launchRoute ?? '/'),
    ),
  );
}

/// Shown when settings could not be read and there is no app to start.
///
/// Says what failed and what tends to cause it, because the alternative is a
/// blank screen that gives someone standing at a washing machine nothing to
/// act on and no way to tell a broken app from a broken phone.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({required this.error, super.key});

  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Washing Advice',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: ThemeMode.system,
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storage_outlined, size: 48),
                const SizedBox(height: 24),
                Text(
                  'Washing Advice could not open its storage',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'This usually means the browser is in private mode, or the '
                  'site’s storage has been cleared or blocked. Your wardrobe '
                  'has not been lost — it is kept in that storage, and it '
                  'comes back when the storage does. Closing this page and '
                  'opening it again outside private browsing is the usual fix.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Text(
                  '$error',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class WashingAdviceApp extends ConsumerStatefulWidget {
  const WashingAdviceApp({this.initialLocation = '/', super.key});

  /// Where to open. The wardrobe, unless a reminder's tap launched the app.
  final String initialLocation;

  @override
  ConsumerState<WashingAdviceApp> createState() => _WashingAdviceAppState();
}

class _WashingAdviceAppState extends ConsumerState<WashingAdviceApp> {
  late final GoRouter _router = buildRouter(
    initialLocation: widget.initialLocation,
  );
  StreamSubscription<String>? _taps;

  @override
  void initState() {
    super.initState();
    // A reminder tapped while the app is running, or in the background, goes
    // to the screen it was for. A tap on a closed app is handled before this
    // widget exists, through `initialLocation`.
    _taps = ref.read(nudgesProvider).taps.listen(_router.go);
  }

  @override
  void dispose() {
    _taps?.cancel();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Washing Advice',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Follows the system. A laundry app is used in a utility room at night
      // as often as in daylight.
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
