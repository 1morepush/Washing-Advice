/// Choosing a garment from the wardrobe to sell.
library;

import 'package:flutter/material.dart';

import '../../widgets/back_navigation.dart';

class PickGarmentScreen extends StatelessWidget {
  const PickGarmentScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: backLeading(context, '/sell'),
      title: const Text('Choose a garment'),
    ),
  );
}
