/// The evening reminder, in Settings.
///
/// One switch and one time. The switch asks the platform's permission at the
/// moment it is flipped — the only moment the question makes sense to the
/// person answering it — and stays off, saying why, if the answer is no. A
/// reminder scheduled without permission would simply never arrive, and
/// nothing would say so.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../laundry/evening_nudge.dart';

class NudgeSection extends ConsumerWidget {
  const NudgeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final nudges = ref.watch(nudgesProvider);
    final time = ref.watch(nudgeTimeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Evening reminder', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          '"What did you wear today?" is quick to answer and easy to forget. '
          'A reminder in the evening opens the screen that asks it.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),

        if (!nudges.isSupported)
          // Said rather than hidden. The person using the browser build on a
          // phone would otherwise never learn the feature exists.
          Text(
            'Reminders need the phone app. A browser cannot schedule a '
            'notification for later, so the web version has none.',
            style: theme.textTheme.bodyMedium,
          )
        else ...[
          SwitchListTile(
            value: time != null,
            onChanged: (on) => _toggle(context, ref, on),
            contentPadding: EdgeInsets.zero,
            title: const Text('Ask what I wore, every evening'),
            subtitle: const Text(
              'A notification at a time you choose. Tap it and the three-tap '
              'screen is open.',
            ),
          ),
          if (time != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_outlined),
              title: Text(
                'Every day at ${_format(context, time)}',
                style: theme.textTheme.bodyMedium,
              ),
              trailing: const Text('Change'),
              onTap: () => _pick(context, ref, time),
            ),
        ],
      ],
    );
  }

  String _format(BuildContext context, NudgeTime time) =>
      TimeOfDay(hour: time.hour, minute: time.minute).format(context);

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool on) async {
    if (!on) {
      await _set(ref, null);
      return;
    }

    final granted = await ref.read(nudgesProvider).requestPermission();
    if (!granted) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Notifications are off for this app in the phone's settings. "
            'Allow them there, then turn this on.',
          ),
        ),
      );
      return;
    }
    await _set(ref, NudgeTime.defaultEvening);
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    NudgeTime current,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: 'Remind me at',
    );
    if (picked == null) return;
    await _set(ref, NudgeTime(hour: picked.hour, minute: picked.minute));
  }

  /// Stores it, shows it, and tells the platform — in that order, so a
  /// platform that refuses still leaves the setting where the person put it
  /// for the next launch to try again.
  Future<void> _set(WidgetRef ref, NudgeTime? time) async {
    await ref.read(settingsStoreProvider).setNudgeMinutes(time?.minutes);
    ref.read(nudgeTimeProvider.notifier).state = time;
    await ref.read(nudgeSchedulerProvider).apply(time);
  }
}
