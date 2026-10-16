/// The page that shows photographs taken so far, before anything is sent.
///
/// A garment and a care label are both photographed in as many shots as it
/// takes — front and back, one side of the label and then the other — and both
/// stop at the same place before reading: the shots laid out, a way to add one
/// or take the last one back, and the button that actually sends them. The
/// shape was written twice; this is it once, with the words left to the screen.
library;

import 'package:flutter/material.dart';

import '../features/scan/scan_parts.dart' show ScanHeading;

class CollectedPhotos extends StatelessWidget {
  const CollectedPhotos({
    required this.heading,
    required this.body,
    required this.tiles,
    required this.addLabel,
    required this.onAdd,
    required this.onUndo,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.extra,
    super.key,
  });

  /// "3 photos".
  final String heading;

  /// What the photos are for and that nothing has been sent yet.
  final String body;

  /// A further line under [body], set apart from it.
  final Widget? extra;

  final List<Widget> tiles;

  final String addLabel;
  final VoidCallback onAdd;

  /// Takes the last photograph back, for the shot that came out blurred —
  /// which is most of them. Without it a retake means starting over.
  final VoidCallback onUndo;

  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ScanHeading(heading, body: body),
              if (extra case final Widget extra) ...[
                const SizedBox(height: 8),
                extra,
              ],
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 12, children: tiles),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: onAdd,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: Text(addLabel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: onUndo,
                      icon: const Icon(Icons.undo),
                      tooltip: 'Remove the last photo',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onPrimary,
                    icon: Icon(primaryIcon),
                    label: Text(primaryLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
