/// The Sell tab: the person's listings, as drafts, listed and sold.
library;

import 'package:flutter/material.dart';

class SellScreen extends StatelessWidget {
  const SellScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Sell')));
}
