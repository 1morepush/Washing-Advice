/// Opening the listing for a garment, or making one from what is known of it.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../widgets/back_navigation.dart';

class StartFromGarmentScreen extends StatelessWidget {
  const StartFromGarmentScreen({required this.id, super.key});

  /// The garment being sold.
  final ItemId id;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: backLeading(context, '/sell/from-wardrobe'),
      title: const Text('Sell this'),
    ),
  );
}
