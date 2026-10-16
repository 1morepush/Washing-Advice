/// How the app looks, in Settings.
///
/// One question with four answers, and the first of them is what the app did
/// before there was a question: Match phone, the default, so opening Settings
/// and leaving it alone changes nothing. The other three are for somebody who
/// has decided the phone's idea of light or dark is wrong for them, which in a
/// utility room at night is easy to have decided.
///
/// AMOLED is its own choice and not a switch on Dark, because it is not Dark
/// with a tweak: it takes the screen to true black, which is a different
/// bargain — see `AppTheme.amoled` — and worth naming where somebody can see
/// what they are choosing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/browser_chrome.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';

class AppearanceSection extends ConsumerWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = ref.watch(appearanceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A group rather than four tiles each told what is selected: it is one
        // question, and the framework supplies the single selection, the arrow
        // keys and the semantics that go with that.
        RadioGroup<Appearance>(
          groupValue: chosen,
          onChanged: (choice) => _choose(ref, choice),
          child: Column(
            children: [
              for (final option in Appearance.values)
                _Choice(option: option, selected: option == chosen),
            ],
          ),
        ),
      ],
    );
  }

  /// Stores it, shows it, and tells the browser — in that order. The choice is
  /// the one thing that has to survive, and the colour of the page behind the
  /// app is the least of them.
  Future<void> _choose(WidgetRef ref, Appearance? choice) async {
    // Null is what a radio reports when it is un-ticked, and these cannot be.
    if (choice == null) return;

    // Taken before the wait, so a screen left during it cannot strand the
    // write halfway between the store and the app.
    final store = ref.read(settingsStoreProvider);
    final appearance = ref.read(appearanceProvider.notifier);

    await store.setAppearance(choice);
    appearance.state = choice;
    paintBrowserChrome(choice);
  }
}

String _title(Appearance choice) => switch (choice) {
  Appearance.system => 'Match phone',
  Appearance.light => 'Light',
  Appearance.dark => 'Dark',
  Appearance.amoled => 'AMOLED',
};

/// Only said where the name does not already say it.
String? _subtitle(Appearance choice) => switch (choice) {
  Appearance.system => 'Light or dark, as your phone is set',
  Appearance.amoled => 'True black. Easier on OLED screens and in a dark room',
  Appearance.light || Appearance.dark => null,
};

/// What the group's header says the current look is.
String appearanceValue(Appearance choice) => _title(choice);

/// The explanation behind the group's info button.
const appearanceInfo =
    'Match phone is the default, so nothing changes until you choose. Light and '
    'Dark are fixed whatever the phone is set to. AMOLED is true black: easier '
    'on OLED screens and in a dark room.';

/// One look. The chosen one is a tinted pill with a bold name (and, on true
/// black, where a lighter fill has nothing to lean on, an accent edge), so the
/// answer is plain at a glance in every mode and not only in the radio's dot.
class _Choice extends StatelessWidget {
  const _Choice({required this.option, required this.selected});

  final Appearance option;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rinse = context.rinse;
    final accent = theme.colorScheme.primary;
    final onBlack = rinse.cardEdge != BorderSide.none;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RadioListTile<Appearance>(
        value: option,
        selected: selected,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        selectedTileColor: onBlack ? null : accent.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: rinse.tileBorderRadius,
          side: selected && onBlack
              ? BorderSide(color: accent, width: 1.5)
              : BorderSide.none,
        ),
        title: Text(
          _title(option),
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
        subtitle: switch (_subtitle(option)) {
          final String text => Text(text),
          null => null,
        },
      ),
    );
  }
}
