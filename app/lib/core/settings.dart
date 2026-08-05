/// User settings that are not domain data.
///
/// Just the backend address for now. Deliberately *not* in the wardrobe
/// database: it is configuration, it has no history worth keeping, and mixing
/// it into the item store would mean a schema migration to change a URL.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the scan backend lives.
///
/// A physical device cannot reach the developer's `localhost`, so this is
/// editable in the app rather than baked in at build time — which also means a
/// tester can be handed a build and pointed at a server without a rebuild.
const defaultBackendUrl = 'http://localhost:8000';

class SettingsStore {
  SettingsStore(this._prefs);

  static const _backendUrlKey = 'backendUrl';

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
