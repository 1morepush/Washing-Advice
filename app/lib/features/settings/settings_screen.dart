/// Settings.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../widgets/back_navigation.dart';
import '../../data/api/ai_gateway.dart';
import '../sync/sync_section.dart';
import 'appearance_section.dart';
import 'machine_section.dart';
import 'nudge_section.dart';
import 'patch_notes.dart';
import 'sorting_section.dart';
import 'setting_info.dart';
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
      appBar: AppBar(
        // Opened from More there is a screen to go back to and the app bar
        // draws its own arrow; opened by address, with nothing beneath it, a
        // button to More instead of no way out.
        leading: backLeading(context, '/more'),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          // In the order a person reaches for them: how it looks, how the
          // laundry is run, when it nags, then the things set once and left.
          SettingsGroup(
            title: 'Appearance',
            value: appearanceValue(ref.watch(appearanceProvider)),
            info: appearanceInfo,
            children: const [AppearanceSection()],
          ),

          SettingsGroup(
            title: 'Washing and drying',
            children: [
              TitleWithInfo(
                'Your machines',
                style: theme.textTheme.titleSmall,
                info:
                    'Used to turn "40°C, gentle, low spin" into the program '
                    'actually printed on your dial. Optional — without them '
                    'the app still says what each load needs, it just cannot '
                    'name the setting.',
              ),
              const SizedBox(height: 8),
              const MachineSection(kind: MachineKind.washer),
              const SizedBox(height: 20),
              const MachineSection(kind: MachineKind.dryer),
              const SizedBox(height: 20),
              const SortingSection(),
            ],
          ),

          const SettingsGroup(title: 'Reminders', children: [NudgeSection()]),

          const SettingsGroup(
            title: 'Sync',
            info: syncInfo,
            children: [SyncSection()],
          ),

          // The things that are set once, or only when something is wrong.
          SettingsGroup(
            title: 'Advanced',
            children: [
              _ServerAddress(
                controller: _url,
                checking: _checking,
                waking: _waking,
                saved: ref.watch(backendUrlProvider),
                health: _health,
                onSave: _save,
              ),
              // Only where there is a service worker to clear — a native
              // build, should one ever exist, has no stale cache to get past.
              if (kIsWeb) ...[
                const SizedBox(height: 16),
                const UpdateSection(),
              ],
            ],
          ),

          // Under the update button's group, and not behind the same
          // `kIsWeb`: the notes are how anyone tells which version they have,
          // which is worth having whether or not there is a cache to clear.
          const SettingsGroup(title: 'About', children: [PatchNotes()]),
        ],
      ),
    );
  }
}

/// Where photographs are sent to be identified, and whether it answers.
///
/// Folded away under Advanced with the address it currently holds shown on the
/// row, because it is set once and the only thing most people need from it is to
/// see that it is right.
class _ServerAddress extends StatelessWidget {
  const _ServerAddress({
    required this.controller,
    required this.checking,
    required this.waking,
    required this.saved,
    required this.health,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool checking;
  final bool waking;

  /// The address in force, as last saved. The row's value is this and not what
  /// is typed in the field, which may be half an edit nobody has tested.
  final String saved;
  final ({bool reachable, String status, String? problem})? health;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ExpansionTile(
      // The default draws a line above and below, which reads as a section
      // break in the middle of a group.
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      title: const TitleWithInfo(
        'Server address',
        infoTitle: 'Scan backend',
        info:
            'Where photographs are sent to be identified. A phone cannot '
            "reach a development machine's localhost, so this is set here "
            'rather than built in.',
      ),
      // The current value, as the row's second line.
      subtitle: Text(saved, maxLines: 1, overflow: TextOverflow.ellipsis),
      children: [
        const SizedBox(height: 8),
        TextField(
          controller: controller,
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
              onPressed: checking ? null : onSave,
              child: const Text('Save and test'),
            ),
            const SizedBox(width: 12),
            if (checking)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        if (waking) ...[
          const SizedBox(height: 12),
          Text(
            'Still waiting. A server that sleeps when idle can take up to a '
            'minute to wake, and this is the request that wakes it.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (health case final health?) ...[
          const SizedBox(height: 16),
          _HealthResult(health: health),
        ],
        const SizedBox(height: 8),
      ],
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
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
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
