/// One garment in the picker: what it is, and how much it has been worn.
///
/// The row the wardrobe's list uses for a garment, with a different second line.
/// The wardrobe's says what it is made of; this says how often it has been worn
/// and when last, because that is why it is in this list and in this place in it.
/// The tile itself is not `ItemTile`, which has no room for a line of its own,
/// but it draws the garment with the same thumbnail and sets it in the same row.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import '../../../core/theme.dart';
import '../../../widgets/item_thumbnail.dart';
import '../list/listing_when.dart';

class GarmentChoiceTile extends StatelessWidget {
  const GarmentChoiceTile({
    required this.item,
    required this.now,
    required this.onTap,
    super.key,
  });

  final WardrobeItem item;

  /// What the time is, for how long ago it was last worn.
  final DateTime now;

  final VoidCallback onTap;

  /// `Sweater · worn 12 times`, or `never worn`.
  static String wornLine(WardrobeItem item) {
    final worn = item.usage.timesWorn;
    final times = switch (worn) {
      0 => 'never worn',
      1 => 'worn once',
      _ => 'worn $worn times',
    };
    return '${item.type.value.label} · $times';
  }

  /// `Last worn 130 days ago`, or null when it has never been, or was not dated.
  String? lastWornLine() {
    final last = item.usage.lastWornAt;
    return last == null ? null : 'Last worn ${timeAgo(now.difference(last))}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final last = lastWornLine();

    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: context.rinse.tileBorderRadius,
      ),
      leading: ItemThumbnail(item: item),
      title: Text(
        item.displayName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(wornLine(item), style: quiet),
          if (last != null) Text(last, style: quiet),
        ],
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
