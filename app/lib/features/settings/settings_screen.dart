/// Settings.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../data/api/ai_gateway.dart';
import '../../widgets/app_drawer.dart';
import '../sync/sync_section.dart';
import 'machine_section.dart';
import 'patch_notes.dart';
import 'sorting_section.dart';
import 'update_section.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _url = TextEditingController(
    text: ref.read(backendUrlProvider),
  );

  ({bool reachable, String status, String? problem})? _health;
  bool _checking = false;

  /// Whether the check has been running long enough to need explaining.
  ///
  /// A sleeping free-tier host takes tens of seconds to answer its first
  /// request. Silence for that long reads as a failure, and the user's next
  /// move is to change a setting that was never wrong.
  bool _waking = false;
  Timer? _wakingTimer;

  @override
  void dispose() {
    _wakingTimer?.cancel();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(settingsStoreProvider).setBackendUrl(_url.text);
    ref.read(backendUrlProvider.notifier).state = _url.text.trim().isEmpty
        ? defaultBackendUrl
        : _url.text.trim();
    await _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _waking = false;
    });

    _wakingTimer?.cancel();
    _wakingTimer = Timer(wakingAfter, () {
      if (mounted) setState(() => _waking = true);
    });

    final result = await ref.read(aiGatewayProvider).health();

    _wakingTimer?.cancel();
    if (mounted) {
      setState(() {
        _health = result;
        _checking = false;
        _waking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      // Now a top-level destination rather than a detour from the wardrobe, so
      // it gets the drawer instead of a back button that only ever went home.
      drawer: const AppDrawer(current: AppDestination.settings),
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Scan backend', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            'Where photographs are sent to be identified. A phone cannot reach '
            "a development machine's localhost, so this is set here rather "
            'than built in.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Server address',
              hintText: defaultBackendUrl,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: _checking ? null : _save,
                child: const Text('Save and test'),
              ),
              const SizedBox(width: 12),
              if (_checking)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (_waking) ...[
            const SizedBox(height: 12),
            Text(
              'Still waiting. A server that sleeps when idle can take up to a '
              'minute to wake, and this is the request that wakes it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_health case final health?) ...[
            const SizedBox(height: 16),
            _HealthResult(health: health),
          ],

          const SizedBox(height: 32),
          const SyncSection(),

          const SizedBox(height: 32),
          Text('Your machines', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            'Used to turn "40°C, gentle, low spin" into the program actually '
            'printed on your dial. Optional — without them the app still says '
            'what each load needs, it just cannot name the setting.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          const MachineSection(kind: MachineKind.washer),
          const SizedBox(height: 20),
          const MachineSection(kind: MachineKind.dryer),

          const SizedBox(height: 32),
          const SortingSection(),

          // Only where there is a service worker to clear — a native build,
          // should one ever exist, has no stale cache to get past.
          if (kIsWeb) ...[const SizedBox(height: 32), const UpdateSection()],

          // Directly under the update button, and not behind the same
          // `kIsWeb`: the notes are how anyone tells which version they have,
          // which is worth having whether or not there is a cache to clear.
          const SizedBox(height: 32),
          const PatchNotes(),
        ],
      ),
    );
  }
}

/// What `/health` said.
///
/// Three outcomes, not two. The server answers `degraded` at 200 when it is
/// running but its vision provider is misconfigured, which is a different
/// problem from being unreachable and needs a different fix from the user.
class _HealthResult extends StatelessWidget {
  const _HealthResult({required this.health});

  final ({bool reachable, String status, String? problem}) health;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOk = health.reachable && health.status == 'ok';

    final (IconData icon, Color color, String title) = switch (health) {
      (reachable: false, status: _, problem: _) => (
        Icons.cloud_off,
        scheme.error,
        'Could not reach the server',
      ),
      (reachable: true, status: 'ok', problem: _) => (
        Icons.check_circle_outline,
        scheme.primary,
        'Connected',
      ),
      _ => (
        Icons.warning_amber_outlined,
        scheme.tertiary,
        'Reachable, but not ready to scan',
      ),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOk
            ? scheme.surfaceContainerHighest
            : scheme.errorContainer.withValues(alpha: isOk ? 1 : 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium),
                if (health.problem case final String problem) ...[
                  const SizedBox(height: 4),
                  Text(
                    problem,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
