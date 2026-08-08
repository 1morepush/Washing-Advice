/// One machine's controls, on the settings screen — a washer or a dryer.
///
/// Two ways to say what you own. Pick a brand and get its archetype: a
/// plausible programme line-up for that manufacturer's machines in general,
/// stated up front as unverified. Or type the exact model and let AI build a
/// profile from its own knowledge of that specific appliance — built once,
/// stored like any other profile, and run through the same [ProgramMatcher]
/// afterwards. Neither is "the real one" — both are corrected the first time
/// a programme doesn't match the dial.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../core/settings.dart';
import '../../data/api/ai_gateway.dart';

enum MachineKind {
  washer('Washing machine'),
  dryer('Tumble dryer');

  const MachineKind(this.label);

  final String label;
}

class MachineSection extends ConsumerStatefulWidget {
  const MachineSection({required this.kind, super.key});

  final MachineKind kind;

  @override
  ConsumerState<MachineSection> createState() => _MachineSectionState();
}

class _MachineSectionState extends ConsumerState<MachineSection> {
  final _brand = TextEditingController();
  final _model = TextEditingController();

  bool _entering = false;
  bool _identifying = false;
  bool _waking = false;
  Timer? _wakingTimer;
  String? _error;

  @override
  void dispose() {
    _wakingTimer?.cancel();
    _brand.dispose();
    _model.dispose();
    super.dispose();
  }

  List<String> get _brands => switch (widget.kind) {
    MachineKind.washer => seededWashers.keys.toList(),
    MachineKind.dryer => seededDryers.keys.toList(),
  };

  String? _selectedBrand() => switch (widget.kind) {
    MachineKind.washer => ref.watch(washerBrandProvider),
    MachineKind.dryer => ref.watch(dryerBrandProvider),
  };

  /// Brand, model and programme count of a custom profile, extracted here
  /// rather than exposing the profile itself — `WasherProfile` and
  /// `DryerProfile` share no common type, and this is the one shape the rest
  /// of this widget actually needs.
  ({String brand, String model, int programCount})? _customSummary() =>
      switch (widget.kind) {
        MachineKind.washer => switch (ref.watch(customWasherProvider)) {
          null => null,
          final p => (
            brand: p.brand,
            model: p.model,
            programCount: p.programs.length,
          ),
        },
        MachineKind.dryer => switch (ref.watch(customDryerProvider)) {
          null => null,
          final p => (
            brand: p.brand,
            model: p.model,
            programCount: p.programs.length,
          ),
        },
      };

  Future<void> _selectBrand(String? brand) async {
    final settings = ref.read(settingsStoreProvider);
    switch (widget.kind) {
      case MachineKind.washer:
        await settings.setWasherBrand(brand);
        ref.read(washerBrandProvider.notifier).state = brand;
      case MachineKind.dryer:
        await settings.setDryerBrand(brand);
        ref.read(dryerBrandProvider.notifier).state = brand;
    }
  }

  Future<void> _identify() async {
    final brand = _brand.text.trim();
    final model = _model.text.trim();
    if (brand.isEmpty || model.isEmpty) return;

    setState(() {
      _identifying = true;
      _waking = false;
      _error = null;
    });
    _wakingTimer?.cancel();
    _wakingTimer = Timer(wakingAfter, () {
      if (mounted) setState(() => _waking = true);
    });

    try {
      final gateway = ref.read(aiGatewayProvider);
      final settings = ref.read(settingsStoreProvider);
      switch (widget.kind) {
        case MachineKind.washer:
          final profile = await gateway.identifyWasher(
            brand: brand,
            model: model,
          );
          await settings.setCustomWasher(profile);
          ref.read(customWasherProvider.notifier).state = profile;
        case MachineKind.dryer:
          final profile = await gateway.identifyDryer(
            brand: brand,
            model: model,
          );
          await settings.setCustomDryer(profile);
          ref.read(customDryerProvider.notifier).state = profile;
      }
      if (mounted) {
        setState(() {
          _entering = false;
          _brand.clear();
          _model.clear();
        });
      }
    } on ScanFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      _wakingTimer?.cancel();
      if (mounted) {
        setState(() {
          _identifying = false;
          _waking = false;
        });
      }
    }
  }

  Future<void> _removeCustom() async {
    final settings = ref.read(settingsStoreProvider);
    switch (widget.kind) {
      case MachineKind.washer:
        await settings.setCustomWasher(null);
        ref.read(customWasherProvider.notifier).state = null;
      case MachineKind.dryer:
        await settings.setCustomDryer(null);
        ref.read(customDryerProvider.notifier).state = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = _customSummary();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (summary != null)
          _CustomMachineCard(
            label: widget.kind.label,
            brand: summary.brand,
            model: summary.model,
            programCount: summary.programCount,
            onRemove: _removeCustom,
          )
        else ...[
          _MachinePicker(
            label: widget.kind.label,
            brands: _brands,
            selected: _selectedBrand(),
            onChanged: _selectBrand,
          ),
          const SizedBox(height: 8),
          if (_entering)
            _EntryForm(
              brand: _brand,
              model: _model,
              identifying: _identifying,
              waking: _waking,
              onSubmit: _identify,
              onCancel: () => setState(() {
                _entering = false;
                _error = null;
                _brand.clear();
                _model.clear();
              }),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _entering = true),
                child: const Text("Don't see it? Enter the exact model"),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            // Said here rather than only in the README. A user who takes a
            // brand pick for a model-exact specification will trust a
            // programme name that may not exist on their machine. Shown only
            // for the picker: a custom profile carries its own, sharper
            // caveat instead.
            'A brand pick is an archetype, not your exact model. Check the '
            'programme against your own machine the first time.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_error case final message?) ...[
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// A machine AI already identified — its brand, model, and a way to remove it
/// and go back to picking a brand archetype instead.
class _CustomMachineCard extends StatelessWidget {
  const _CustomMachineCard({
    required this.label,
    required this.brand,
    required this.model,
    required this.programCount,
    required this.onRemove,
  });

  final String label;
  final String brand;
  final String model;
  final int programCount;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelSmall),
                Text('$brand $model', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  // Named, not hidden: an AI guess at a specific model reads
                  // as more authoritative than a labelled brand archetype,
                  // and that is exactly backwards from how sure it actually is.
                  "AI's best guess at this exact model's $programCount "
                  'programmes — not checked against a manual. Correct it the '
                  'first time a programme does not match your dial.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close),
            tooltip: 'Remove and pick a brand instead',
          ),
        ],
      ),
    );
  }
}

/// Brand and model, and the button that turns them into a profile.
class _EntryForm extends StatelessWidget {
  const _EntryForm({
    required this.brand,
    required this.model,
    required this.identifying,
    required this.waking,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController brand;
  final TextEditingController model;
  final bool identifying;
  final bool waking;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: brand,
            enabled: !identifying,
            decoration: const InputDecoration(
              labelText: 'Brand',
              hintText: 'Samsung',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: model,
            enabled: !identifying,
            decoration: const InputDecoration(
              labelText: 'Model',
              hintText: 'WF45T6000AW',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: identifying ? null : onSubmit,
                child: const Text('Identify'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: identifying ? null : onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              if (identifying)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (waking) ...[
            const SizedBox(height: 8),
            Text(
              'Still waiting. A server that sleeps when idle can take up to a '
              'minute to wake.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Chooses a machine brand, or none.
class _MachinePicker extends StatelessWidget {
  const _MachinePicker({
    required this.label,
    required this.brands,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<String> brands;
  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String?>(
    initialValue: selected,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      // "Not set" is a real choice, not an empty state. Someone without a
      // dryer should be able to say so rather than leave a field looking
      // unfinished.
      const DropdownMenuItem(value: null, child: Text('Not set')),
      for (final brand in brands)
        DropdownMenuItem(value: brand, child: Text(brand)),
    ],
    onChanged: onChanged,
  );
}
