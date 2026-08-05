/// One wash load, as instructions someone can follow at the machine.
///
/// The whole system exists to produce this card. Everything above it — the
/// care model, the rule table, the label scans, the machine archetypes — is in
/// service of turning a heap of clothes into "select Delicates, 30°, 600 rpm,
/// extra rinse on" and being able to say why.
///
/// The **why** is not a footnote. A recommendation without a reason is
/// indistinguishable from a guess, and the first time it disagrees with what
/// someone would have done, they need to see whose care requirement forced it
/// before they will believe it.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

/// The rationale entries that explain the settings, as opposed to instructing.
List<LoadRationale> _explanations(LaundryLoad load) => [
  for (final entry in load.rationale)
    if (entry.kind != RationaleKind.handling) entry,
];

class LoadCard extends StatelessWidget {
  const LoadCard({required this.load, super.key});

  final LaundryLoad load;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final washer = load.washerSetting;
    final dryer = load.dryerSetting;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(load.label, style: theme.textTheme.titleMedium),
                ),
                if (load.isCompromise)
                  // Never present a compromise as a perfect match. The machine
                  // could not do exactly what was required, and hiding that is
                  // how a garment gets washed hotter than its label allows.
                  Tooltip(
                    message: 'Closest your machine can manage',
                    child: Icon(
                      Icons.warning_amber_outlined,
                      size: 20,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
              ],
            ),
            Text(
              '${load.itemCount} ${load.itemCount == 1 ? 'item' : 'items'} · '
              '${load.totalWeightKg.toStringAsFixed(1)} kg',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 12),
            for (final item in load.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '• ${item.displayName}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),

            const SizedBox(height: 16),
            if (washer != null)
              _Settings(setting: washer)
            else
              // Without a machine the load still has requirements; it just has
              // no dial position. Saying so beats saying nothing.
              _Requirements(spec: load.washSpec),

            if (dryer != null) ...[
              const SizedBox(height: 12),
              _DrySettings(setting: dryer),
            ] else ...[
              const SizedBox(height: 12),
              _DryRequirements(spec: load.drySpec),
            ],

            // Split by kind, because the two read differently. Explanations
            // are sentences about why the settings are what they are;
            // handling warnings are imperatives about what to do at the
            // machine. Listing "Wash inside out" under "Why" makes it look
            // like an answer to a question nobody asked.
            if (_explanations(load).isNotEmpty) ...[
              const SizedBox(height: 16),
              _Reasons(title: 'Why', entries: _explanations(load)),
            ],
            if (load.rationaleOf(RationaleKind.handling) case final handling
                when handling.isNotEmpty) ...[
              const SizedBox(height: 12),
              _Reasons(title: 'Also', entries: handling),
            ],
          ],
        ),
      ),
    );
  }
}

/// What to select on the machine.
class _Settings extends StatelessWidget {
  const _Settings({required this.setting});

  final WasherSetting setting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wash',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        _Row(label: 'Programme', value: setting.programName),
        _Row(
          label: 'Temperature',
          // Zero is the cold tap, not "no temperature". Printing "0°C" would
          // send someone looking for a setting that is not on the dial.
          value: setting.temperatureC == 0
              ? 'Cold'
              : '${setting.temperatureC}°C',
        ),
        _Row(
          label: 'Spin',
          value: setting.spinRpm == 0 ? 'Off' : '${setting.spinRpm} rpm',
        ),
        // Only options to switch *on*. A list that also says "Extra rinse:
        // Off" is asking the user to verify the absence of things, which is
        // both longer and easier to misread than a short list of what to press.
        //
        // `WasherOptionSetting` is a String: the option as the machine labels
        // it, not an enum we translate. Different machines call the same thing
        // different names, and printing our word for it would send someone
        // hunting for a button that is not there.
        for (final entry in setting.options.entries)
          if (entry.value) _Row(label: entry.key, value: 'On'),
        for (final note in setting.notes)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              note.text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
      ],
    );
  }
}

class _DrySettings extends StatelessWidget {
  const _DrySettings({required this.setting});

  final DryerSetting setting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dry',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        _Row(label: 'Programme', value: setting.programName),
        for (final note in setting.notes)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              note.text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
          ),
      ],
    );
  }
}

/// The load's requirements, when no machine is configured.
class _Requirements extends StatelessWidget {
  const _Requirements({required this.spec});

  final WashSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wash',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        _Row(label: 'Method', value: spec.method.label),
        _Row(
          label: 'Temperature',
          value: spec.maxTempC == null ? 'Any' : 'Up to ${spec.maxTempC}°C',
        ),
        _Row(label: 'Cycle', value: spec.agitation.label),
        if (spec.maxSpinRpm case final int rpm)
          _Row(label: 'Spin', value: 'Up to $rpm rpm'),
        if (spec.needsExtraRinse) _Row(label: 'Rinse', value: 'Extra'),
        if (spec.avoidSoftener) _Row(label: 'Softener', value: 'Do not use'),
      ],
    );
  }
}

class _DryRequirements extends StatelessWidget {
  const _DryRequirements({required this.spec});

  final DrySpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dry',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        if (spec.tumbleDryAllowed)
          _Row(label: 'Tumble', value: spec.maxHeat.label)
        else
          _Row(label: 'Tumble', value: 'Do not tumble dry'),
        if (spec.naturalDry case final NaturalDryMethod method)
          _Row(label: 'Air dry', value: method.label),
      ],
    );
  }
}

/// Everything the sorter has to say about a load, under one heading.
class _Reasons extends StatelessWidget {
  const _Reasons({required this.title, required this.entries});

  final String title;
  final List<LoadRationale> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '· ${entry.reason}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
