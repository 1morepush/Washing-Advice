/// Measurements, in inches, taken flat.
///
/// Buyers on Depop cannot try anything on, and the size on the tag is the
/// least of what they want to know: a medium from one brand is a large from
/// another. So the measurements a seller takes with a tape on a table — across
/// the chest from armpit to armpit, and the length — are always asked for, and
/// waist and inseam as well for anything worn on the legs.
///
/// A box that holds something that is not a measurement ignores it and leaves
/// the listing as it was (see `ParsedField`), so a half-typed "21." never
/// becomes a garment 0 inches long.
library;

import 'package:flutter/material.dart';
import 'package:wardrobe_core/wardrobe_core.dart';

import 'amount_input.dart';
import 'edit_session.dart';
import 'fields.dart';

class MeasurementFields extends StatelessWidget {
  const MeasurementFields({
    required this.listing,
    required this.session,
    super.key,
  });

  final Listing listing;
  final ListingEditSession session;

  /// The measurement as the box should hold it: a value the core would not
  /// count as measured is a box with nothing in it.
  static double? _held(double? inches) =>
      inches != null && inches.isFinite && inches > 0 ? inches : null;

  Widget _field({
    required String label,
    required double? value,
    required Measurements Function(Measurements, double?) change,
    required Key key,
  }) => ParsedField<double>(
    key: key,
    label: label,
    suffixText: 'in',
    value: _held(value),
    parse: parseInchesInput,
    format: inchesInputText,
    invalidMessage: 'Use a number, like 21.5.',
    onChanged: (inches) => session.edit(
      (listing) =>
          listing.copyWith(measurements: change(listing.measurements, inches)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final m = listing.measurements;
    // Anything worn on the legs, and anything that already has a waist or an
    // inseam: those two are never hidden while they hold a value that goes in
    // the description.
    final bottoms =
        listing.itemType.category == ItemCategory.bottom ||
        _held(m.waistIn) != null ||
        _held(m.inseamIn) != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SubHeading('Measurements'),
        const SizedBox(height: 4),
        const QuietText(
          'In inches, laid flat. Buyers cannot try it on, so they ask.',
        ),
        const SizedBox(height: 12),
        _field(
          key: const ValueKey('pit-to-pit'),
          label: 'Pit to pit',
          value: m.pitToPitIn,
          change: (m, inches) =>
              m.copyWith(pitToPitIn: inches, clearPitToPit: inches == null),
        ),
        const SizedBox(height: 12),
        _field(
          key: const ValueKey('length'),
          label: 'Length',
          value: m.lengthIn,
          change: (m, inches) =>
              m.copyWith(lengthIn: inches, clearLength: inches == null),
        ),
        if (bottoms) ...[
          const SizedBox(height: 12),
          _field(
            key: const ValueKey('waist'),
            label: 'Waist',
            value: m.waistIn,
            change: (m, inches) =>
                m.copyWith(waistIn: inches, clearWaist: inches == null),
          ),
          const SizedBox(height: 12),
          _field(
            key: const ValueKey('inseam'),
            label: 'Inseam',
            value: m.inseamIn,
            change: (m, inches) =>
                m.copyWith(inseamIn: inches, clearInseam: inches == null),
          ),
        ],
      ],
    );
  }
}
