/// Settings.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/settings.dart';

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

  @override
  void dispose() {
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
    setState(() => _checking = true);
    final result = await ref.read(aiGatewayProvider).health();
    if (mounted) {
      setState(() {
        _health = result;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/')),
        title: const Text('Settings'),
      ),
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
          if (_health case final health?) ...[
            const SizedBox(height: 16),
            _HealthResult(health: health),
          ],
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
