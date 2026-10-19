/// Getting from a task screen to a listing, and from a garment to its listing.
///
/// **No route here does work when it is entered.** A route that asks a server
/// for something and then replaces itself is a trap on the web and in a home
/// screen app: the browser's Back returns to it, it runs again, finds what it
/// made, and replaces itself again, and the person goes round. So the work is
/// done by the screen the person is already on, behind a dialog, and the listing
/// is pushed once when it is ready.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../listing_controller.dart';
import 'listing_wait.dart';

/// Where a finished task leaves the person: on Sell, with [location] on top.
///
/// A task screen (New listing, the garment picker) that has done its job is
/// popped, so history Back from [location] is Sell and not a screen that has
/// nothing left to do. Opened directly, with nothing beneath it to pop to, Sell
/// is put beneath it instead.
///
/// `pushReplacement` is not used because on the web it adds a history entry
/// rather than replacing one, which leaves the finished screen one Back away.
void leaveTaskFor(BuildContext context, String location) {
  unawaited(
    _leaveTask(GoRouter.of(context), Navigator.of(context).canPop(), location),
  );
}

Future<void> _leaveTask(GoRouter router, bool canPop, String location) async {
  if (canPop) {
    router.pop();
    // A frame, so the address bar has been told about Sell before the listing
    // is pushed. Pushed in the same breath, the browser is told only about the
    // listing, and its history keeps the screen that was just left.
    await WidgetsBinding.instance.endOfFrame;
  } else {
    router.go('/sell');
    await WidgetsBinding.instance.endOfFrame;
  }
  unawaited(router.push<void>(location));
}

/// Opens the listing for the garment [id], making it first if there is none.
///
/// Shows a dialog while the controller works, which says why it is slow once it
/// is, then pushes the editor once. [fromTask] is whether the caller is a task
/// screen (the picker) that should be left behind, as [leaveTaskFor] does.
/// What is worth saying about how it went is said on a message that outlives the
/// caller; a garment that is not there, or a phone that could not save, is said
/// the same way and leaves the person where they were.
Future<void> startListingForGarment(
  BuildContext context,
  ListingController controller,
  ItemId id, {
  bool fromTask = false,
}) async {
  // Everything the end needs is taken before the first await: the caller may be
  // gone by then, and the dialog, the message and the router are not.
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final canPop = Navigator.of(context).canPop();

  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: const ListingWait(
              title: 'Starting your listing…',
              detail:
                  'Reading its photos, and filling in the rest from your '
                  'wardrobe.',
            ),
          ),
        ),
      ),
    ),
  );

  try {
    final made = await controller.openOrCreateForGarment(id);
    navigator.pop();

    final said = _saidAbout(made);
    if (said != null) messenger.showSnackBar(SnackBar(content: Text(said)));

    final location = '/listing/${made.listing.id.value}';
    if (fromTask) {
      unawaited(_leaveTask(router, canPop, location));
    } else {
      unawaited(router.push<void>(location));
    }
  } on GarmentNotFound catch (error) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  } on Exception catch (error) {
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text('The listing could not be started. $error')),
    );
  }
}

/// What the person should be told about the listing they are being given.
String? _saidAbout(({Listing listing, bool reused, bool describeFailed}) made) {
  if (made.reused) {
    return 'Opened the listing already started for this garment.';
  }
  if (made.describeFailed) {
    return 'Could not read the photos, so this was filled in from your '
        'wardrobe.';
  }
  return null;
}
