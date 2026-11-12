/// What the "not worn in a year" suggestion reads and remembers.
///
/// The rule — which garments, and what a Keep does to them — is the core's
/// `letGoCandidates`. This file feeds it the wardrobe, the clock and the
/// answers people have given, and keeps those answers on the phone.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../sell/list/listing_clock.dart';

/// When each garment was last answered "Keep", by item id.
///
/// One preferences entry holding a small JSON object of ids and dates, rather
/// than a key per garment: it is read once, written whole, and cannot be left
/// half-updated. Dates are ISO-8601 in UTC, so the six months are counted the
/// same wherever the phone is carried.
///
/// Lives in shared preferences and not in the wardrobe database, because it is
/// a preference about a suggestion and not a fact about a garment, and a
/// schema migration to remember "not now" would be out of proportion. A
/// preference that cannot be read (a private window, a failing store) is
/// treated as none given: the suggestion comes back, which is the harmless way
/// to be wrong.
class LetGoKeeps extends AsyncNotifier<Map<ItemId, DateTime>> {
  static const _key = 'letGoKeptOn';

  @override
  Future<Map<ItemId, DateTime>> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(_key);
      if (text == null) return const {};
      final decoded = jsonDecode(text);
      if (decoded is! Map) return const {};
      return {
        for (final MapEntry(:key, :value) in decoded.entries)
          if (key is String &&
              value is String &&
              DateTime.tryParse(value) != null)
            ItemId(key): DateTime.parse(value),
      };
    } on Object {
      // Anything unreadable is the same as nothing remembered.
      return const {};
    }
  }

  /// Quiets the suggestion for [id] for [keepForMonths].
  Future<void> keep(ItemId id) async {
    final now = ref.read(listingClockProvider)().toUtc();
    final cutoff = monthsBefore(now, keepForMonths);
    final current = state.valueOrNull ?? const <ItemId, DateTime>{};
    // Lapsed answers are dropped as a new one is written, so the entry does not
    // grow for as long as the app is installed.
    final next = {
      for (final entry in current.entries)
        if (!entry.value.isBefore(cutoff)) entry.key: entry.value,
      id: now,
    };
    state = AsyncData(next);
    await _write(next);
  }

  /// Takes a Keep back, for the Undo on its confirmation.
  Future<void> forget(ItemId id) async {
    final next = {...?state.valueOrNull}..remove(id);
    state = AsyncData(next);
    await _write(next);
  }

  Future<void> _write(Map<ItemId, DateTime> kept) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          for (final entry in kept.entries)
            entry.key.value: entry.value.toIso8601String(),
        }),
      );
    } on Object {
      // Still hidden for this run. Failing to remember is not worth an error
      // on a button that only said "not now".
    }
  }
}

final letGoKeepsProvider =
    AsyncNotifierProvider<LetGoKeeps, Map<ItemId, DateTime>>(LetGoKeeps.new);

/// The garments to offer to let go of, longest unworn first.
///
/// Loading until the remembered answers are read as well as the wardrobe, so a
/// garment somebody already kept does not flash into the list and out again.
final letGoProvider = Provider<AsyncValue<List<LetGoCandidate>>>((ref) {
  final owned = ref.watch(ownedItemsProvider);
  final keeps = ref.watch(letGoKeepsProvider);
  final now = ref.watch(listingClockProvider)();

  if (keeps.isLoading && !keeps.hasValue) return const AsyncLoading();
  final kept = keeps.valueOrNull ?? const <ItemId, DateTime>{};

  return owned.whenData(
    (items) => letGoCandidates(items, now: now, keptOn: kept),
  );
});

/// `6 things you haven't worn in a year`.
String letGoHeadline(int count) => count == 1
    ? '1 thing you haven’t worn in a year'
    : '$count things you haven’t worn in a year';
