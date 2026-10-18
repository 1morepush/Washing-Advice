/// The two ways a listing starts, offered where the person asks for a new one.
///
/// A sheet that names both in words, as the Wardrobe's Add button does for its
/// three: they are different jobs ("I have this in my hand" and "I have this in
/// a drawer") and the same verb, so the sheet says which is which.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Where "Take photos" goes.
const newFromPhotosRoute = '/sell/new';

/// Where "Choose from my wardrobe" goes.
const newFromWardrobeRoute = '/sell/from-wardrobe';

/// Asks how to start, and goes there.
Future<void> chooseHowToStartListing(BuildContext context) async {
  final route = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    // The content is as tall as it is, and at large text on a short phone that
    // can be more than the sheet's default share of the screen. Scrolling is
    // what keeps the second choice reachable then.
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photos'),
              subtitle: const Text(
                'Photograph it, and the listing is written from the photos.',
              ),
              onTap: () => Navigator.pop(sheet, newFromPhotosRoute),
            ),
            ListTile(
              leading: const Icon(Icons.checkroom_outlined),
              title: const Text('Choose from my wardrobe'),
              subtitle: const Text(
                'Start from a garment you already own, least worn first.',
              ),
              onTap: () => Navigator.pop(sheet, newFromWardrobeRoute),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );

  if (route != null && context.mounted) context.push(route);
}
