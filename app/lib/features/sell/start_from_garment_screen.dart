/// Opening the listing for a garment, or making one from what is known of it.
///
/// Reached by "Sell this" on a garment's page and by picking from the wardrobe.
/// It does one thing, once, and gets out of the way: ask the controller for the
/// garment's listing — the unsold one it already has, or a new one made from the
/// garment and a reading of its photographs — and replace itself with the editor
/// on it, so that Back from the editor is where the person came from.
///
/// What is worth saying about how that went is said in a message on the editor
/// and not on a screen of its own, because there is nothing for the person to
/// decide: the photographs could not be read, so the draft was filled in from the
/// wardrobe alone, which is still a draft they can edit; or there was one
/// already, and this is it. Only a garment that is not there stops here.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../widgets/back_navigation.dart';
import '../../widgets/rinse_kit.dart';
import '../../widgets/state_view.dart';
import 'list/new_listing_sheet.dart' show newFromWardrobeRoute;
import 'listing_controller.dart';
import 'start/listing_wait.dart';

class StartFromGarmentScreen extends ConsumerStatefulWidget {
  const StartFromGarmentScreen({required this.id, super.key});

  /// The garment being sold.
  final ItemId id;

  @override
  ConsumerState<StartFromGarmentScreen> createState() =>
      _StartFromGarmentScreenState();
}

class _StartFromGarmentScreenState
    extends ConsumerState<StartFromGarmentScreen> {
  /// Why the listing was not opened, once it was not.
  ({String message, bool missing})? _problem;

  @override
  void initState() {
    super.initState();
    // Once, when the screen is made: a rebuild for a rotation or a text size
    // must not ask the server a second time.
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final made = await ref
          .read(listingControllerProvider)
          .openOrCreateForGarment(widget.id);
      if (!mounted) return;

      final said = _saidAbout(made);
      if (said != null) {
        // Said before the screen is replaced and not after: the messenger
        // belongs to the app, so the message outlives this screen and is there
        // when the editor is.
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(said)));
      }
      context.pushReplacement('/listing/${made.listing.id.value}');
    } on GarmentNotFound catch (error) {
      _stop(error.message, missing: true);
    } on Exception catch (error) {
      _stop('The listing could not be started. $error', missing: false);
    }
  }

  /// What the person should be told about the listing they are being given.
  String? _saidAbout(
    ({Listing listing, bool reused, bool describeFailed}) made,
  ) {
    if (made.reused) {
      return 'Opened the listing already started for this garment.';
    }
    if (made.describeFailed) {
      return 'Could not read the photos, so this was filled in from your '
          'wardrobe.';
    }
    return null;
  }

  void _stop(String message, {required bool missing}) {
    if (!mounted) return;
    setState(() => _problem = (message: message, missing: missing));
  }

  void _tryAgain() {
    setState(() => _problem = null);
    unawaited(_start());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: backLeading(context, newFromWardrobeRoute),
      title: const AppBarTitle('Sell this'),
    ),
    body: switch (_problem) {
      null => const ListingWait(
        title: 'Starting your listing…',
        detail:
            'Reading its photos, and filling in the rest from your wardrobe.',
      ),
      (:final message, missing: true) => _Missing(message: message),
      (:final message, missing: false) => FailureView(
        message: message,
        actionLabel: 'Try again',
        onAction: _tryAgain,
      ),
    },
  );
}

/// The garment is not in the wardrobe: deleted, or an address for one that
/// never was.
///
/// The way out is the Back arrow, as it is on the garment page's own "no longer
/// exists", and the words are the controller's, which are the ones the stain
/// screen already uses for the same thing.
class _Missing extends StatelessWidget {
  const _Missing({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const IconBadge(Icons.checkroom_outlined),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    ),
  );
}
