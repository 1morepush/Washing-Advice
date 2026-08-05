/// User settings that are not domain data.
///
/// Just the backend address for now. Deliberately *not* in the wardrobe
/// database: it is configuration, it has no history worth keeping, and mixing
/// it into the item store would mean a schema migration to change a URL.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

/// Where the scan backend lives.
///
/// A physical device cannot reach the developer's `localhost`, so this is
/// editable in the app rather than baked in at build time — which also means a
/// tester can be handed a build and pointed at a server without a rebuild.
const defaultBackendUrl = 'http://localhost:8000';

class SettingsStore {
  SettingsStore(this._prefs);

  static const _backendUrlKey = 'backendUrl';
  static const _washerKey = 'washerBrand';
  static const _dryerKey = 'dryerBrand';

  final SharedPreferences _prefs;

  String get backendUrl =>
      _prefs.getString(_backendUrlKey) ?? defaultBackendUrl;

  Future<void> setBackendUrl(String value) async {
    final trimmed = value.trim();
    await _prefs.setString(
      _backendUrlKey,
      trimmed.isEmpty ? defaultBackendUrl : trimmed,
    );
  }

  /// The chosen machines, by catalogue key.
  ///
  /// Stored as a key rather than a serialised profile so a corrected or
  /// expanded catalogue reaches existing users. The profiles are brand
  /// archetypes that will be refined; freezing a copy into preferences would
  /// mean every improvement only ever applied to new installs.
  String? get washerBrand => _readBrand(_washerKey, seededWashers);

  String? get dryerBrand => _readBrand(_dryerKey, seededDryers);

  Future<void> setWasherBrand(String? brand) => _write(_washerKey, brand);

  Future<void> setDryerBrand(String? brand) => _write(_dryerKey, brand);

  /// Reads a stored key, discarding one the catalogue no longer has.
  ///
  /// A brand can disappear between releases, and a dangling key would leave
  /// the app with a machine it cannot resolve — which reads to the user as
  /// their settings being silently ignored.
  String? _readBrand(String key, Map<String, Object?> catalogue) {
    final stored = _prefs.getString(key);
    return stored != null && catalogue.containsKey(stored) ? stored : null;
  }

  Future<void> _write(String key, String? value) async {
    if (value == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, value);
    }
  }
}

/// Resolved once at startup, before the first frame, so nothing has to render a
/// spinner while waiting for a preference read.
final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => throw StateError(
    'settingsStoreProvider must be overridden in main() with a loaded store',
  ),
);

/// The current backend URL, as state so editing it rebuilds the gateway.
final backendUrlProvider = StateProvider<String>(
  (ref) => ref.watch(settingsStoreProvider).backendUrl,
);

/// The user's machines, by catalogue key. Null means "not set up yet".
final washerBrandProvider = StateProvider<String?>(
  (ref) => ref.watch(settingsStoreProvider).washerBrand,
);

final dryerBrandProvider = StateProvider<String?>(
  (ref) => ref.watch(settingsStoreProvider).dryerBrand,
);

/// The chosen washer, or null.
///
/// Null is a supported state throughout, not an error: `LaundrySorter` still
/// groups items and states abstract requirements without a machine, it just
/// cannot name a programme. Forcing setup before the app does anything useful
/// would put a configuration screen between someone and their first answer.
final washerProvider = Provider<WasherProfile?>(
  (ref) => seededWashers[ref.watch(washerBrandProvider)],
);

final dryerProvider = Provider<DryerProfile?>(
  (ref) => seededDryers[ref.watch(dryerBrandProvider)],
);
