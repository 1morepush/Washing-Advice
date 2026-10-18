/// Links out of the editor, and the three that are always offered.
///
/// A price the person cannot check is a price they should not trust, and the
/// live search will not always be there: it needs a key on the server, the key
/// has a monthly allowance, and a search service can be down. So beside
/// whatever the search found there are always three links that open the same
/// searches in the person's own browser or the Depop app, where they can look
/// for themselves. They are built by the core, from the Depop phrase, so that
/// an ampersand in "H&M" is encoded once, in one tested place.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../core/providers.dart';
import 'fields.dart';

/// Opens [uri] outside the app, and says so if nothing on the phone could.
///
/// A link that will not open is not an error to throw: the opener answers
/// false, and this tells the person in the words of the screen they tapped it
/// on.
Future<void> openLink(BuildContext context, WidgetRef ref, Uri uri) async {
  final opened = await ref.read(linkOpenerProvider).open(uri);
  if (opened || !context.mounted) return;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(content: Text("That link couldn't be opened.")),
    );
}

/// The three searches to run by hand, for the Depop phrase [query].
class CheckItYourself extends ConsumerWidget {
  const CheckItYourself({required this.query, super.key});

  /// What the person is searching Depop for, as it is in the box now.
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phrase = query.trim();
    final searchable = phrase.isNotEmpty;

    Widget link({
      required Key key,
      required String title,
      required String why,
      required Uri Function(String) address,
    }) => ListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.open_in_new),
      title: Text(title),
      subtitle: Text(why),
      enabled: searchable,
      onTap: searchable ? () => openLink(context, ref, address(phrase)) : null,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SubHeading('Check it yourself'),
        const SizedBox(height: 4),
        QuietText(
          searchable
              ? "A price you can't check is a price not to trust. These open "
                    'the same search in your browser or the Depop app.'
              : 'Write a title or a search phrase above, and these open that '
                    'search.',
        ),
        const SizedBox(height: 4),
        link(
          key: const ValueKey('link-depop'),
          title: 'Depop search',
          why: 'What is for sale now, and what sellers are asking.',
          address: depopSearchLink,
        ),
        link(
          key: const ValueKey('link-ebay'),
          title: 'eBay sold listings',
          why:
              "eBay's sold listings show what things actually sold for, not "
              'what sellers hope.',
          address: ebaySoldLink,
        ),
        link(
          key: const ValueKey('link-google'),
          title: 'Google Shopping',
          why: 'What it costs new, across shops.',
          address: googleShoppingLink,
        ),
      ],
    );
  }
}
