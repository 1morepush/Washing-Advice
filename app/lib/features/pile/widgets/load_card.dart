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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../core/theme.dart';
import '../../../widgets/care_symbol.dart';
import '../../../widgets/item_thumbnail.dart';
import '../../history/wear_recorder.dart';

/// The rationale entries that explain the settings, as opposed to instructing.
List<LoadRationale> _explanations(LaundryLoad load) => [
  for (final entry in load.rationale)
    if (entry.kind != RationaleKind.handling) entry,
];

/// The care symbols that belong with the wash row, and those that belong with
/// the dry row. Bleach rides with the wash; ironing and professional care are
/// not part of a load's settings and are left to the garment's own page.
const _washKinds = {
  CareSymbolKind.wash30Gentle,
  CareSymbolKind.wash30Mild,
  CareSymbolKind.wash40,
  CareSymbolKind.doNotBleach,
};
const _dryKinds = {
  CareSymbolKind.tumbleDryNoHeat,
  CareSymbolKind.tumbleDryLow,
  CareSymbolKind.tumbleDryMedium,
  CareSymbolKind.tumbleDryHigh,
  CareSymbolKind.doNotTumbleDry,
  CareSymbolKind.dryFlat,
  CareSymbolKind.lineDry,
};

class LoadCard extends ConsumerStatefulWidget {
  const LoadCard({required this.load, this.action, super.key});

  final LaundryLoad load;

  /// What to offer at the bottom of the card, replacing "I washed this".
  ///
  /// The pile scan is a one-off: you photograph a heap, follow the card, and
  /// tell the app it happened. The laundry screen tracks the same load through
  /// the machine instead, so its buttons move the items on a stage rather than
  /// closing the book on them. The card itself — settings, reasons, the
  /// compromise warning — is identical either way, and a second copy of it
  /// would be a second thing to keep correct.
  final Widget? action;

  @override
  ConsumerState<LoadCard> createState() => _LoadCardState();
}

class _LoadCardState extends ConsumerState<LoadCard> {
  bool _recorded = false;

  LaundryLoad get load => widget.load;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final washer = load.washerSetting;
    final dryer = load.dryerSetting;

    final rinse = context.rinse;
    // Symbols exist for only some instructions; the words below always say the
    // whole of it, so a missing symbol loses nothing.
    final symbols = careSymbolsFor(load.effectiveCare);
    final washSymbols = [
      for (final kind in symbols)
        if (_washKinds.contains(kind)) kind,
    ];
    final drySymbols = [
      for (final kind in symbols)
        if (_dryKinds.contains(kind)) kind,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    load.label,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
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
            const SizedBox(height: 2),
            Text(
              '${load.itemCount} ${load.itemCount == 1 ? 'item' : 'items'} · '
              '${load.totalWeightKg.toStringAsFixed(1)} kg',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 14),
            // Pictures rather than a list of names, because this card is read
            // with a basket in front of you. A name is what the app calls a
            // garment; a photograph is what you are holding, and matching
            // "heathered dark grey activewear pants" to the right pair by
            // reading meant scrolling down to the list below and back up
            // again for each one.
            for (final item in load.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(
                        rinse.tileRadius * .6,
                      ),
                      child: ItemThumbnail(item: item, size: 40),
                    ),
                    const SizedBox(width: 12),
                    // Wrapped rather than clipped: these names run long and
                    // the tail is often the part that tells two similar
                    // garments apart.
                    Expanded(
                      child: Text(
                        item.displayName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),
            if (washer != null)
              _Settings(setting: washer, symbols: washSymbols)
            else
              // Without a machine the load still has requirements; it just has
              // no dial position. Saying so beats saying nothing.
              _Requirements(spec: load.washSpec, symbols: washSymbols),

            // When the load dries in parts, the parts *are* the answer — a
            // single "do not tumble dry" above them would describe the
            // conservative reading the split exists to get past.
            if (load.driesInParts) ...[
              const SizedBox(height: 12),
              _DryingParts(load: load, symbols: drySymbols),
            ] else if (dryer != null) ...[
              const SizedBox(height: 12),
              _DrySettings(setting: dryer, symbols: drySymbols),
            ] else ...[
              const SizedBox(height: 12),
              _DryRequirements(spec: load.drySpec, symbols: drySymbols),
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

            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child:
                  widget.action ??
                  (_recorded
                      // Not undoable from here on purpose. The event log is
                      // append-only, and a button that appeared to delete history
                      // would misrepresent what the system does.
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Recorded',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        )
                      : FilledButton.tonalIcon(
                          onPressed: () async {
                            await ref
                                .read(wearRecorderProvider)
                                .recordWash(load);
                            if (mounted) setState(() => _recorded = true);
                          },
                          icon: const Icon(Icons.check),
                          label: const Text('I washed this'),
                        )),
            ),
          ],
        ),
      ),
    );
  }
}

/// What to select on the machine.
class _Settings extends StatelessWidget {
  const _Settings({required this.setting, required this.symbols});

  final WasherSetting setting;
  final List<CareSymbolKind> symbols;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Block(
      title: 'Wash',
      symbols: symbols,
      children: [
        _Row(label: 'Program', value: setting.programName),
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
  const _DrySettings({required this.setting, required this.symbols});

  final DryerSetting setting;
  final List<CareSymbolKind> symbols;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Block(
      title: 'Dry',
      symbols: symbols,
      children: [
        _Row(label: 'Program', value: setting.programName),
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
  const _Requirements({required this.spec, required this.symbols});

  final WashSpec spec;
  final List<CareSymbolKind> symbols;

  @override
  Widget build(BuildContext context) {
    return _Block(
      title: 'Wash',
      symbols: symbols,
      children: [
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

/// A load that washes as one and dries as two.
///
/// Named by what happens to each part rather than by a spec, because the user
/// is standing at a machine deciding what goes in it. "These four in the
/// dryer, these two on the airer" is the instruction; the heat setting is
/// detail underneath it.
class _DryingParts extends StatelessWidget {
  const _DryingParts({required this.load, required this.symbols});

  final LaundryLoad load;
  final List<CareSymbolKind> symbols;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _Block(
      title: 'Dry',
      symbols: symbols,
      children: [
        Text(
          'Washed together, dried apart.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        for (final group in load.dryingGroups)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      group.isTumbleDried
                          ? Icons.local_laundry_service_outlined
                          : Icons.air,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        group.isTumbleDried
                            ? 'In the dryer'
                                  '${group.dryerSetting == null ? '' : ' — ${group.dryerSetting!.programName}'}'
                            : 'Hang these up',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // The garments themselves, for the same reason the load lists
                // them: this is read with a basket in front of you.
                for (final item in group.items)
                  Padding(
                    padding: const EdgeInsets.only(left: 24, bottom: 6),
                    child: Row(
                      children: [
                        ItemThumbnail(item: item, size: 32),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.displayName,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DryRequirements extends StatelessWidget {
  const _DryRequirements({required this.spec, required this.symbols});

  final DrySpec spec;
  final List<CareSymbolKind> symbols;

  @override
  Widget build(BuildContext context) {
    return _Block(
      title: 'Dry',
      symbols: symbols,
      children: [
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
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
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

/// The width the label column of one block needs: that of its longest label,
/// measured at the current text size, so no label is ever broken mid-word and
/// the values still line up.
class _LabelWidth extends InheritedWidget {
  const _LabelWidth({required this.width, required super.child});

  final double width;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LabelWidth>()?.width ?? 104;

  @override
  bool updateShouldNotify(_LabelWidth old) => old.width != width;
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  static TextStyle? labelStyle(ThemeData theme) => theme.textTheme.bodyMedium
      ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w800,
    );
    final column = _LabelWidth.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // When the labels take more than half the card, as they do at large
          // text, each sits above its value and can have the whole width.
          if (column > constraints.maxWidth * 0.5) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle(theme)),
                Text(value, style: valueStyle),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: column,
                child: Text(label, style: labelStyle(theme)),
              ),
              Expanded(child: Text(value, style: valueStyle)),
            ],
          );
        },
      ),
    );
  }
}

/// One instruction block of the card, Wash or Dry: a soft tile with the stage
/// dot and title on the left, the care symbols there is art for on the right,
/// and the words underneath. The symbols never stand in for the words.
class _Block extends StatelessWidget {
  const _Block({
    required this.title,
    required this.symbols,
    required this.children,
  });

  final String title;
  final List<CareSymbolKind> symbols;
  final List<Widget> children;

  /// The label column: the widest label's width at this text size, a little
  /// air, and never narrower than the 104 the design draws.
  double _labelColumn(BuildContext context) {
    final style = _Row.labelStyle(Theme.of(context));
    var widest = 0.0;
    for (final row in children.whereType<_Row>()) {
      final painter = TextPainter(
        text: TextSpan(text: row.label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    return math.max(104, widest.ceilToDouble() + 8);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stages = context.stageColors;
    final dot = title == 'Wash' ? stages.wash : stages.dry;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.rinse.well,
        borderRadius: context.rinse.tileBorderRadius,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                for (final kind in symbols) ...[
                  const SizedBox(width: 6),
                  CareSymbol(
                    kind: kind,
                    size: 26,
                    color: theme.colorScheme.onSurface,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            _LabelWidth(
              width: _labelColumn(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
