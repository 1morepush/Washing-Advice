/// Scanning a care label.
///
/// The review step here answers a different question from the garment scan's.
/// There the question was "is this reading right?"; here it is "**what did the
/// label change?**" — because the user already has care instructions, and the
/// only thing worth their attention is where the manufacturer disagreed with
/// what the app had been telling them.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../widgets/back_navigation.dart';
import '../../widgets/collected_photos.dart';
import '../../widgets/state_view.dart';
import 'care_tag_controller.dart';
import 'care_tag_review.dart';

class CareTagScreen extends ConsumerWidget {
  const CareTagScreen({required this.id, super.key});

  final ItemId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(careTagControllerProvider(id));
    final controller = ref.read(careTagControllerProvider(id).notifier);

    void back() {
      controller.reset();
      context.backOr('/item/${id.value}');
    }

    return LeaveScope(
      onLeave: controller.reset,
      child: Scaffold(
        appBar: AppBar(
          leading: backLeading(
            context,
            '/item/${id.value}',
            onLeave: controller.reset,
          ),
          title: const Text('Scan the care label'),
        ),
        body: switch (state) {
          CareTagIdle() => _Capture(controller: controller),
          CareTagCollecting(:final images) => _Collected(
            images: images,
            controller: controller,
          ),
          CareTagReading() => const _Reading(),
          CareTagReviewing() => CareTagReview(
            state: state,
            controller: controller,
          ),
          CareTagSaved() => SuccessView(
            title: 'Care instructions updated',
            actions: [FilledButton(onPressed: back, child: const Text('Done'))],
          ),
          CareTagFailed(:final message, :final isRetryable) => FailureView(
            message: message,
            actionLabel: isRetryable ? 'Try again' : 'Back',
            onAction: controller.reset,
          ),
        },
      ),
    );
  }
}

class _Capture extends StatelessWidget {
  const _Capture({required this.controller});

  final CareTagController controller;

  @override
  Widget build(BuildContext context) => IntroView(
    icon: Icons.document_scanner_outlined,
    title: 'Photograph the care label',
    message:
        'Flatten it out and fill the frame with the symbols. This is the '
        "manufacturer's own instruction, so it will override anything "
        'the app worked out from the fabric.\n\n'
        'Printed on both sides? You can add the other side before it is '
        'read. Any language is fine — the symbols are the same '
        'everywhere.',
    actions: [
      FilledButton.icon(
        onPressed: controller.capture,
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('Take a photo'),
      ),
    ],
  );
}

class _Reading extends StatelessWidget {
  const _Reading();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          'Reading the label…',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );
}

class _Collected extends StatelessWidget {
  const _Collected({required this.images, required this.controller});

  final List<ScanImage> images;
  final CareTagController controller;

  @override
  Widget build(BuildContext context) => CollectedPhotos(
    heading: images.length == 1
        ? 'One photo of the label'
        : '${images.length} photos of the label',
    body:
        'They are read together as one label, so put each side or tag '
        'in its own photo. Nothing has been read yet.',
    tiles: [
      for (final (index, image) in images.indexed)
        _Shot(index: index + 1, image: image),
    ],
    addLabel: 'Add another side',
    onAdd: controller.capture,
    onUndo: controller.discardLast,
    primaryLabel: images.length == 1
        ? 'Read this label'
        : 'Read these ${images.length} together',
    primaryIcon: Icons.document_scanner_outlined,
    onPrimary: controller.readCollected,
  );
}

/// One collected photograph, numbered in the order it was taken.
class _Shot extends StatelessWidget {
  const _Shot({required this.index, required this.image});

  final int index;
  final ScanImage image;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            Uint8List.fromList(image.bytes),
            width: 108,
            height: 108,
            fit: BoxFit.cover,
            // A thumbnail that will not decode must not take the screen with
            // it — the photograph is still perfectly good to the server.
            errorBuilder: (_, _, _) => Container(
              width: 108,
              height: 108,
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.image_not_supported_outlined),
            ),
          ),
        ),
        Positioned(
          top: 4,
          left: 4,
          child: CircleAvatar(
            radius: 11,
            backgroundColor: theme.colorScheme.primary,
            child: Text(
              '$index',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
