/// Starting a listing from photographs, or by writing it by hand.
library;

import 'package:flutter/material.dart';

import '../../widgets/back_navigation.dart';

class NewListingScreen extends StatelessWidget {
  const NewListingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: backLeading(context, '/sell'),
      title: const Text('New listing'),
    ),
  );
}
