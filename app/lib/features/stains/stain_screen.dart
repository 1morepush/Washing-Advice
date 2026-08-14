/// Treating a stain, step by step.
///
/// The one screen in the app someone reads standing over a sink with a wet
/// garment in one hand, which is what shapes it: big numbered steps, the reason
/// underneath in smaller type, and nothing between the answer and the top of
/// the page.
///
/// What was dropped is shown too, at the bottom and greyed. That is not an
/// apology — "the usual next step is a chlorine soak, and this label forbids
/// it" is genuinely useful, and it is the only way the user learns why their
/// treatment is shorter than the one they would find on the internet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../widgets/status_message.dart';
import '../laundry/laundry_controller.dart';
import 'stain_controller.dart';

/// The spills people actually have, as one tap each.
///
/// Not a closed list — the field beside them takes anything, and the model's
/// whole reason for being here is the long tail. These are only the ones common
/// enough that typing them is friction.
const _common = [
  'Red wine',
  'Coffee',
  'Olive oil',
  'Blood',
  'Grass',
  'Ink',
  'Tomato sauce',
  'Make-up',
  'Sweat',
  'Mud',
];

class StainScreen extends ConsumerWidget {
  const StainScreen({required this.id, super.key});

  final ItemId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(stainControllerProvider(id));
    final controller = ref.read(stainControllerProvider(id).notifier);

    void back() {
      controller.reset();
      context.go('/item/${id.value}');
    }

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: back),
        title: const Text('Treat a stain'),
      ),
      body: switch (state) {
        StainIdle() => _Ask(id: id, controller: controller),
        StainThinking() => const _Thinking(),
        StainAdvised() => _Advice(id: id, state: state, controller: controller),
        StainFailed(:final message, :final isRetryable) => StatusMessage(
          icon: Icons.error_outline,
          title: 'Could not work out a treatment',
          detail: message,
          action: isRetryable
              ? TextButton(
                  onPressed: controller.reset,
                  child: const Text('Try again'),
                )
              : null,
        ),
      },
    );
  }
}

class _Ask extends ConsumerStatefulWidget {
  const _Ask({required this.id, required this.controller});

  final ItemId id;
  final StainController controller;

  @override
  ConsumerState<_Ask> createState() => _AskState();
}

class _AskState extends ConsumerState<_Ask> {
  final _substance = TextEditingController();
  ScanImage? _photo;

  @override
  void dispose() {
    _substance.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    try {
      final image = await ref.read(imageCaptureProvider).capture();
      if (image != null && mounted) setState(() => _photo = image);
    } on Exception {
      // A camera that will not open costs the optional half of this screen and
      // nothing else. The description is what the advice actually rests on.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = ref.watch(itemProvider(widget.id)).valueOrNull;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (item != null)
          Text(
            'On your ${item.displayName.toLowerCase()} — '
            '${item.composition.value.label}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 16),
        Text('What was spilled?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _substance,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'What it is',
            hintText: 'Red wine, bike chain grease, turmeric…',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _ask(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final spill in _common)
              ActionChip(
                label: Text(spill),
                onPressed: () {
                  _substance.text = spill;
                  setState(() {});
                },
              ),
          ],
        ),

        const SizedBox(height: 24),
        Text(
          _photo == null
              ? 'A photo is optional. It helps when you are not sure what the '
                    'mark is — what you tell it still comes first.'
              : 'Photo attached.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addPhoto,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(_photo == null ? 'Add a photo' : 'Replace the photo'),
          ),
        ),

        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _substance.text.trim().isEmpty ? null : _ask,
          icon: const Icon(Icons.cleaning_services_outlined),
          label: const Text('How do I get it out?'),
        ),
      ],
    );
  }

  void _ask() =>
      widget.controller.advise(substance: _substance.text, photo: _photo);
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Working out what is safe for this garment…'),
      ],
    ),
  );
}

class _Advice extends ConsumerWidget {
  const _Advice({
    required this.id,
    required this.state,
    required this.controller,
  });

  final ItemId id;
  final StainAdvised state;
  final StainController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final plan = state.plan;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(state.substance, style: theme.textTheme.titleMedium),
              if (state.identifiedAs case final String identified)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Treated as $identified.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 20),

              // Only once the treatment is whole. Mid-stream the plan is
              // legitimately empty — the first step may have been refused while
              // the second is still being written — and announcing "nothing is
              // safe" there tells the user to give up on a treatment that is
              // about to arrive.
              if (plan.isEmpty && state.isComplete)
                StatusMessage(
                  icon: Icons.pan_tool_outlined,
                  title: 'Nothing safe to try at home',
                  detail:
                      'Every treatment for this goes against what this '
                      'garment\'s care label allows. A specialist cleaner is '
                      'the honest answer — tell them what was spilled and how '
                      'long ago. Everything that was ruled out is listed '
                      'below.',
                )
              else
                for (final (index, step) in plan.steps.indexed)
                  _Step(number: index + 1, step: step),

              if (plan.cautions.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final caution in plan.cautions)
                  _Note(
                    icon: Icons.info_outline,
                    text: caution,
                    color: theme.colorScheme.tertiary,
                  ),
              ],

              if (plan.refused.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Left out', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'The usual treatment includes these. This garment cannot '
                  'take them.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                for (final refused in plan.refused)
                  _Note(
                    icon: Icons.block,
                    text: '${refused.step.instruction} — ${refused.reason}',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],

              // Shown under the steps rather than over them. The steps above
              // are finished and vetted and can be started on now — which is
              // the whole reason for streaming — so the indicator belongs where
              // the next one will appear, not somewhere that implies the page
              // is not ready.
              if (!state.isComplete) ...[
                const SizedBox(height: 16),
                const _StillWriting(),
              ],
            ],
          ),
        ),
        // Withheld until the treatment is whole. "Done" on a half-written one
        // would record a treatment nobody finished and send the garment to the
        // wash before the step that says to check the mark first.
        if (state.isComplete)
          _Done(id: id, state: state, controller: controller),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.step});

  final int number;
  final TreatmentStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              '$number',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Unflexed, a full instruction beside a fixed-width avatar is the
          // classic overflow, and this screen is read on a phone at arm's
          // length with the text scale turned up.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.instruction, style: theme.textTheme.bodyLarge),
                if (step.because case final String because)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      because,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}

/// What happens once the steps have been followed.
class _Done extends ConsumerWidget {
  const _Done({
    required this.id,
    required this.state,
    required this.controller,
  });

  final ItemId id;
  final StainAdvised state;
  final StainController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          TextButton(
            onPressed: controller.reset,
            child: const Text('Something else'),
          ),
          const Spacer(),
          FilledButton.icon(
            // Both at once: the treatment goes in the garment's history, and
            // the garment goes in the basket. Almost every stain treatment
            // ends with "now wash it", and leaving the user to go and do that
            // by hand is how a half-finished job gets forgotten.
            onPressed: () async {
              await controller.record(state.substance);
              await ref.read(laundryControllerProvider).move([
                id,
              ], LifecycleState.inLaundry);
              if (context.mounted) context.go('/laundry');
            },
            icon: const Icon(Icons.local_laundry_service_outlined),
            label: const Text('Done — put it in the wash'),
          ),
        ],
      ),
    ),
  );
}

/// That there is more of the treatment still coming.
///
/// Its own line under the last step rather than a spinner over the page. What
/// is already drawn is final — each step was vetted against this garment as it
/// arrived — so covering it would hide advice that is ready to act on, which is
/// exactly what streaming was meant to stop doing.
class _StillWriting extends StatelessWidget {
  const _StillWriting();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'Working out the rest…',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
