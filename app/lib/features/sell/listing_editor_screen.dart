/// Writing, pricing and tracking one listing.
///
/// This is the screen the person spends their time on, and it is laid out as
/// Depop's "Sell an item" form is, because they fill that form by copying from
/// here: the photographs, the description with Depop's two counters, the
/// details Depop asks for, the price, and where the listing has got to. Depop
/// has no API, so nothing here posts anything. What it does is make the form
/// quick to fill and the price something to argue with.
///
/// ## There is no Save button
///
/// Everything typed is stored a moment after it is typed, and at once on the
/// way out by any route: the Back arrow, the system gesture, a link that
/// replaces the screen, the app going to the background. The listing being
/// edited is a working copy held by a [ListingEditSession], and the boxes are
/// built once from it and then edited, not rebuilt from the database each time
/// it is saved — a box that was would move the cursor under a typing finger.
/// The stored listing is watched only to know that it exists.
///
/// The sections are one file each, under `editor/`, in the order of the form.
/// This file is what they have in common: finding the listing, keeping the
/// session, leaving, and deleting.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../core/providers.dart';
import '../../widgets/back_navigation.dart';
import '../../widgets/notice.dart';
import '../../widgets/state_view.dart';
import '../../widgets/status_message.dart';
import 'editor/description_section.dart';
import 'editor/edit_session.dart';
import 'editor/fields.dart' show inlineTextButton;
import 'editor/info_section.dart';
import 'editor/photos_section.dart';
import 'editor/price_section.dart';
import 'editor/shipping_section.dart';
import 'editor/status_section.dart';
import 'listing_controller.dart';

class ListingEditorScreen extends ConsumerStatefulWidget {
  const ListingEditorScreen({required this.id, super.key});

  /// The listing being edited.
  final ListingId id;

  @override
  ConsumerState<ListingEditorScreen> createState() =>
      _ListingEditorScreenState();
}

class _ListingEditorScreenState extends ConsumerState<ListingEditorScreen>
    with WidgetsBindingObserver {
  /// The working copy, made when the stored listing first arrives.
  ListingEditSession? _session;

  /// Whether the listing is being deleted by this screen, which is when it
  /// disappearing from the store is expected and not news.
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(ListingEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _session?.dispose();
      _session = null;
      _leaving = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session?.dispose();
    super.dispose();
  }

  /// A phone that goes to the background may never come back: the system is
  /// free to end the app there. Whatever was typed is stored before it does.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _flush();
  }

  void _flush() => unawaited(_session?.flush());

  Future<void> _delete(ListingEditSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ConfirmDelete(listing: session.listing),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _leaving = true);
    try {
      await session.delete();
      if (!mounted) return;
      context.go('/sell');
    } on Exception {
      if (!mounted) return;
      setState(() => _leaving = false);
      _say("The listing couldn't be deleted. Try again.");
    }
  }

  void _say(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(listingProvider(widget.id));

    return LeaveScope(
      onLeave: _flush,
      child: Scaffold(
        appBar: AppBar(
          leading: backLeading(context, '/sell', onLeave: _flush),
          title: const Text('Listing'),
        ),
        body: stored.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => StatusMessage.failure(
            title: 'Could not open this listing',
            error: error,
            detail:
                'Something went wrong reading your listings. They are still '
                'on this phone — try again.',
          ),
          data: (listing) {
            if (listing == null) {
              return _leaving
                  ? const Center(child: CircularProgressIndicator())
                  : const _NotFound();
            }
            final session = _session ??= ListingEditSession(
              listing: listing,
              controller: ref.read(listingControllerProvider),
            );
            return _Editor(session: session, onDelete: () => _delete(session));
          },
        ),
      ),
    );
  }
}

/// The form: every section, drawn from the working copy.
class _Editor extends StatelessWidget {
  const _Editor({required this.session, required this.onDelete});

  final ListingEditSession session;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      // A scroll view and not a lazy list: every box in it keeps its text and
      // its cursor however far it is scrolled away, and there are a few dozen
      // widgets here, not thousands.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 32),
      child: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final listing = session.listing;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Always a child, shrunk to nothing when all is well, so that
              // the sections below keep their place in the tree — and their
              // text — when it comes and goes.
              _SaveFailed(failed: session.saveFailed),
              PhotosSection(
                key: const ValueKey('photos'),
                listing: listing,
                session: session,
              ),
              DescriptionSection(
                key: const ValueKey('description'),
                listing: listing,
              ),
              InfoSection(
                key: const ValueKey('info'),
                listing: listing,
                session: session,
              ),
              PriceSection(
                key: const ValueKey('price-section'),
                listing: listing,
                session: session,
              ),
              ShippingSection(
                key: const ValueKey('shipping'),
                listing: listing,
              ),
              StatusSection(
                key: const ValueKey('status'),
                listing: listing,
                session: session,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('delete'),
                    onPressed: onDelete,
                    style: inlineTextButton.copyWith(
                      foregroundColor: WidgetStatePropertyAll(
                        Theme.of(context).colorScheme.error,
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete listing'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// Said when what was typed could not be stored, which is otherwise silent.
class _SaveFailed extends StatelessWidget {
  const _SaveFailed({required this.failed});

  final bool failed;

  @override
  Widget build(BuildContext context) => failed
      ? const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Notice(
            icon: Icons.sync_problem_outlined,
            warning: true,
            text:
                "Your last change couldn't be saved yet. It will be tried "
                'again, and when you leave.',
          ),
        )
      : const SizedBox.shrink();
}

/// A link to a listing that is not there: deleted, or never was.
class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) => EmptyView(
    icon: Icons.search_off_outlined,
    title: 'This listing no longer exists',
    message:
        'It may have been deleted. The listings you still have are in the '
        'Sell tab.',
    action: FilledButton(
      onPressed: () => context.go('/sell'),
      child: const Text('Back to Sell'),
    ),
  );
}

/// Asks, before a listing is deleted for good.
class _ConfirmDelete extends StatelessWidget {
  const _ConfirmDelete({required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = listing.title.trim();
    final name = title.isEmpty ? 'This listing' : '"$title"';
    // A listing made from a garment shows the garment's own photographs, and
    // deleting the listing never deletes those.
    final garment = listing.itemId == null
        ? ''
        : ' The garment and its own photos stay in your wardrobe.';

    return AlertDialog(
      scrollable: true,
      title: const Text('Delete this listing?'),
      content: Text(
        '$name and the photos taken for it will be gone for good. This '
        "can't be undone.$garment",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.errorContainer,
            foregroundColor: scheme.onErrorContainer,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
