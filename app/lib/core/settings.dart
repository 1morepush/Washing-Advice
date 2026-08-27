/// User settings that are not domain data.
///
/// Just the backend address for now. Deliberately *not* in the wardrobe
/// database: it is configuration, it has no history worth keeping, and mixing
/// it into the item store would mean a schema migration to change a URL.
library;

import 'dart:convert';

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
  static const _customWasherKey = 'customWasherProfile';
  static const _customDryerKey = 'customDryerProfile';
  static const _splitDryingKey = 'splitDrying';
  static const _syncTokenKey = 'syncToken';
  static const _syncCursorKey = 'syncCursorRemote';
  static const _syncLocalCursorKey = 'syncCursorLocal';

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

  /// Whether a load may be split into more than one drying group.
  ///
  /// Off by default, which is what the app has always done: the load dries as
  /// one, at the most restrictive spec any member demands. Safe, and wasteful
  /// — one air-dry-only garment sends the whole drum to the airer.
  bool get splitDrying => _prefs.getBool(_splitDryingKey) ?? false;

  Future<void> setSplitDrying(bool value) =>
      _prefs.setBool(_splitDryingKey, value);

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

  /// A machine AI identified from its exact brand and model, if one was ever
  /// built.
  ///
  /// The opposite kind of storage from [washerBrand]: that is a lookup key
  /// into a catalogue that keeps improving, so a fresh copy is read from it
  /// every time. This *is* a frozen copy — the entire point of asking AI for
  /// one exact machine's programme list is to keep the answer for that
  /// machine, not to look anything up again. A corrupted or outdated record
  /// is read as absent rather than thrown, the same reasoning `ImageStore`
  /// already applies to a photo that no longer decodes: a wardrobe that
  /// crashes on a bad cache entry is worse than one that quietly falls back.
  WasherProfile? get customWasher =>
      _readProfile(_customWasherKey, WasherProfile.fromJson);

  DryerProfile? get customDryer =>
      _readProfile(_customDryerKey, DryerProfile.fromJson);

  Future<void> setCustomWasher(WasherProfile? profile) =>
      _writeProfile(_customWasherKey, profile?.toJson());

  Future<void> setCustomDryer(DryerProfile? profile) =>
      _writeProfile(_customDryerKey, profile?.toJson());

  /// The sync credential, or null when sync has not been set up.
  ///
  /// A bearer token: whoever holds it owns the wardrobe on the server. Kept in
  /// the same preferences as everything else, which is honest about the level
  /// of protection — this is not a secure enclave, and pretending otherwise by
  /// hiding it somewhere marginally less obvious would be worse than saying so.
  String? get syncToken {
    final stored = _prefs.getString(_syncTokenKey)?.trim();
    return stored == null || stored.isEmpty ? null : stored;
  }

  Future<void> setSyncToken(String? value) {
    final trimmed = value?.trim() ?? '';
    return _write(_syncTokenKey, trimmed.isEmpty ? null : trimmed);
  }

  /// The two sync cursors, persisted so a restart does not re-pull everything.
  ///
  /// Two rather than one because they are in different clocks — see the note
  /// on `SyncCursor` in the core. Storing them under one key would recreate
  /// exactly the bug that separating them fixed.
  DateTime? get syncedAt => _readTime(_syncCursorKey);

  DateTime? get pushedAt => _readTime(_syncLocalCursorKey);

  Future<void> setCursors({required DateTime at, DateTime? localAt}) async {
    await _prefs.setString(_syncCursorKey, at.toUtc().toIso8601String());
    if (localAt != null) {
      await _prefs.setString(
        _syncLocalCursorKey,
        localAt.toUtc().toIso8601String(),
      );
    }
  }

  /// Forgets both cursors, so the next run pulls the whole wardrobe again.
  ///
  /// What "sign out" and "change token" both need: cursors belong to an
  /// account, and carrying one across a change of credential would make the
  /// new account look like it had already been synced.
  Future<void> clearCursors() async {
    await _prefs.remove(_syncCursorKey);
    await _prefs.remove(_syncLocalCursorKey);
  }

  DateTime? _readTime(String key) {
    final stored = _prefs.getString(key);
    return stored == null ? null : DateTime.tryParse(stored)?.toUtc();
  }

  /// Reads a stored key, discarding one the catalogue no longer has.
  ///
  /// A brand can disappear between releases, and a dangling key would leave
  /// the app with a machine it cannot resolve — which reads to the user as
  /// their settings being silently ignored.
  String? _readBrand(String key, Map<String, Object?> catalogue) {
    final stored = _prefs.getString(key);
    return stored != null && catalogue.containsKey(stored) ? stored : null;
  }

  T? _readProfile<T>(String key, T Function(Map<String, Object?>) fromJson) {
    final stored = _prefs.getString(key);
    if (stored == null) return null;
    try {
      return fromJson(jsonDecode(stored) as Map<String, Object?>);
    } on FormatException {
      return null;
    } on TypeError {
      // A shape from an older or newer version of the app that this one
      // cannot read. Treated the same as absent, not as corruption to fix —
      // there is nothing here worth trying to repair.
      return null;
    } on ArgumentError {
      // `WashProgramKind.values.byName` and its siblings throw this for an
      // enum member this build no longer knows, which is the same "an older
      // or newer install wrote this" case as the cast failures above.
      return null;
    }
  }

  Future<void> _writeProfile(String key, Map<String, Object?>? json) {
    return _write(key, json == null ? null : jsonEncode(json));
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

/// Whether a load is split into more than one drying group.
///
/// A plain default rather than a read of the store, unlike the settings around
/// it. The laundry sorter watches this, and sorting laundry is something the
/// core does without knowing anything about preferences — making every test
/// that groups a basket wire up SharedPreferences first would be the tail
/// wagging the dog. `main()` seeds it from the stored value at startup and the
/// settings screen writes through to both.
final splitDryingProvider = StateProvider<bool>((ref) => false);

/// The user's machines, by catalogue key. Null means "not set up yet".
final washerBrandProvider = StateProvider<String?>(
  (ref) => ref.watch(settingsStoreProvider).washerBrand,
);

final dryerBrandProvider = StateProvider<String?>(
  (ref) => ref.watch(settingsStoreProvider).dryerBrand,
);

/// A machine AI identified from its exact brand and model, as state so
/// building or removing one rebuilds everything that reads [washerProvider].
final customWasherProvider = StateProvider<WasherProfile?>(
  (ref) => ref.watch(settingsStoreProvider).customWasher,
);

final customDryerProvider = StateProvider<DryerProfile?>(
  (ref) => ref.watch(settingsStoreProvider).customDryer,
);

/// The chosen washer, or null.
///
/// Null is a supported state throughout, not an error: `LaundrySorter` still
/// groups items and states abstract requirements without a machine, it just
/// cannot name a programme. Forcing setup before the app does anything useful
/// would put a configuration screen between someone and their first answer.
///
/// A machine AI built from an exact model wins outright over a seeded brand
/// archetype — it is the more specific answer, and the whole reason someone
/// went to the trouble of typing their exact model in was to stop getting the
/// generic one.
final washerProvider = Provider<WasherProfile?>(
  (ref) =>
      ref.watch(customWasherProvider) ??
      seededWashers[ref.watch(washerBrandProvider)],
);

final dryerProvider = Provider<DryerProfile?>(
  (ref) =>
      ref.watch(customDryerProvider) ??
      seededDryers[ref.watch(dryerBrandProvider)],
);

/// The configured sync token, as state so saving one rebuilds the engine.
final syncTokenProvider = StateProvider<String?>(
  (ref) => ref.watch(settingsStoreProvider).syncToken,
);
