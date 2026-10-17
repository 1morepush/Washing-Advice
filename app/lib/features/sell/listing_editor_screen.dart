/// Writing, pricing and tracking one listing.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../widgets/back_navigation.dart';

class ListingEditorScreen extends StatelessWidget {
  const ListingEditorScreen({required this.id, super.key});

  /// The listing being edited.
  final ListingId id;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: backLeading(context, '/sell'),
      title: const Text('Listing'),
    ),
  );
}
