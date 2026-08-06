/// The outfits the user has kept.
///
/// Distinct from the suggestions beside them: a suggestion is the app's
/// proposal and is regenerated every time the screen is opened, while these
/// are the user's own decisions and must look and behave like something they
/// own — nameable, renameable, deletable, and not silently reshuffled.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../widgets/item_thumbnail.dart';
import 'outfit_controller.dart';

class SavedOutfitsTab extends ConsumerWidget {
  const SavedOutfitsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedOutfitsProvider);

    return saved.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (outfits) => outfits.isEmpty
          ? const _Empty()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: outfits.length,
              itemBuilder: (_, index) => _SavedCard(outfit: outfits[index]),
            ),
    );
  }
}

class _SavedCard extends ConsumerWidget {
  const _SavedCard({required this.outfit});

  final Outfit outfit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items = ref.watch(outfitItemsProvider(outfit.id));
    final controller = ref.read(outfitControllerProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(outfit.name, style: theme.textTheme.titleMedium),
                      Text(
                        _subtitleFor(outfit),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (choice) async {
                    if (choice == 'delete') {
                      await controller.delete(outfit.id);
                      return;
                    }
                    if (!context.mounted) return;
                    final name = await _askForName(
                      context,
                      title: 'Rename outfit',
                      initial: outfit.name,
                    );
                    if (name != null) await controller.rename(outfit, name);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 84,
              child: items.when(
                loading: () => const SizedBox.shrink(),
                error: (error, _) => Text('$error'),
                data: (list) => ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final item = list[index];
                    return InkWell(
                      onTap: () => context.go('/item/${item.id.value}'),
                      borderRadius: BorderRadius.circular(12),
                      child: Tooltip(
                        message: item.displayName,
                        child: ItemThumbnail(item: item, size: 80),
                      ),
                    );
                  },
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await controller.wear(outfit);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Recorded ${outfit.name} as worn.')),
                  );
                },
                icon: const Icon(Icons.checkroom_outlined, size: 18),
                label: const Text('Wearing this'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The occasion, and how often this combination has actually been chosen.
///
/// Worth showing because it is the one number a per-item history cannot
/// produce: the log knows the tee and the jeans were worn on the same day, not
/// that they were worn together *as this outfit*.
String _subtitleFor(Outfit outfit) {
  final worn = outfit.usage.timesWorn;
  if (worn == 0) return '${outfit.occasion.label} · not worn yet';
  return '${outfit.occasion.label} · worn $worn ${worn == 1 ? 'time' : 'times'}';
}

/// Asks for a name, returning null when the user backs out.
///
/// Shared by saving and renaming so the two cannot drift apart in wording or
/// in what counts as an empty answer.
Future<String?> askForOutfitName(
  BuildContext context, {
  required String title,
  String initial = '',
}) => _askForName(context, title: title, initial: initial);

Future<String?> _askForName(
  BuildContext context, {
  required String title,
  String initial = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => _NameDialog(title: title, initial: initial),
);

/// The dialog owns its controller.
///
/// It was a plain function first, disposing the controller as soon as
/// `showDialog` returned. That is one frame too early: the dialog is still
/// running its exit animation and the `TextField` is still reading from the
/// controller, so the dispose threw "used after being disposed" and took the
/// render tree down with it. Tying the lifetime to a `State` is the only
/// version that cannot get this wrong.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Name',
        hintText: 'Saturday, work Mondays, the good jeans…',
      ),
      onSubmitted: (value) => Navigator.of(context).pop(value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Save'),
      ),
    ],
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('Nothing saved yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Save a suggestion you like and it will be waiting here — with '
              'a count of how often you actually wear it, which is the one '
              'thing a per-garment history cannot tell you.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
