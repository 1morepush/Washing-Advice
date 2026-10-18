/// Reading what a person types into a price box or a measurement box.
///
/// The boxes are for people holding a phone, so what arrives is whatever their
/// keyboard offers: a dollar sign pasted from a listing, a thousands comma, and
/// on a phone set to a language that writes decimals with a comma, a comma
/// where the point should be. None of that is an error. What is an error is a
/// number that cannot be what was meant — nothing, zero, more than there is —
/// and those read as null, which the field takes to mean "ignore it", not "put
/// zero". A typed price that silently became $0.00 would be worse than one
/// that did not register.
///
/// Money is whole US cents throughout, as in the core. It is parsed from the
/// digits and never through a double, so $32.57 is 3257 and not 3256.99999.
library;

import 'package:wardrobe_core/wardrobe_core.dart' show formatInches;

/// The dearest price a person can type, in cents: $100,000, the ceiling the
/// price contract itself carries. Beyond it is a slip of the finger.
const int maxTypedPriceCents = 10000000;

/// The longest measurement a person can type, in inches. Beyond it is a slip.
const double maxTypedInches = 300;

/// Dollars typed by hand, as cents; null when they are not an amount.
///
/// Accepts `32`, `32.5`, `32.50`, `$32`, `1,234.50` and `12,50` (a decimal
/// comma). A comma is a thousands separator when a point is present or when
/// three digits follow it, and a decimal point otherwise: `1,234` is a
/// thousand two hundred and thirty-four dollars and `12,5` is twelve fifty.
///
/// Not an amount: nothing, zero, a third decimal place (`3.555`, which is not
/// a price whichever way it is rounded), or more than [maxTypedPriceCents].
int? parseUsdInput(String text) {
  var cleaned = text.replaceAll(r'$', '').replaceAll(RegExp(r'\s'), '');
  if (cleaned.isEmpty) return null;

  if (cleaned.contains('.')) {
    cleaned = cleaned.replaceAll(',', '');
  } else if (cleaned.contains(',')) {
    final parts = cleaned.split(',');
    final decimal = parts.length == 2 && parts.last.length <= 2;
    cleaned = decimal ? parts.join('.') : parts.join();
  }

  final match = RegExp(r'^(\d*)(?:\.(\d{0,2}))?$').firstMatch(cleaned);
  if (match == null) return null;

  final whole = match.group(1)!;
  final fraction = match.group(2) ?? '';
  if (whole.isEmpty && fraction.isEmpty) return null;
  // Eight digits is already past the ceiling, and stops a pasted run of
  // digits from being read at all.
  if (whole.length > 8) return null;

  final cents =
      (whole.isEmpty ? 0 : int.parse(whole)) * 100 +
      int.parse(fraction.padRight(2, '0'));
  return cents > 0 && cents <= maxTypedPriceCents ? cents : null;
}

/// [cents] as the text of a price box: `30`, or `30.50` when there are cents.
///
/// No dollar sign and no grouping, because the box shows its own sign and
/// what is in it is going to be edited.
String usdInputText(int cents) {
  final dollars = cents ~/ 100;
  final remainder = cents % 100;
  return remainder == 0
      ? '$dollars'
      : '$dollars.${remainder.toString().padLeft(2, '0')}';
}

/// Inches typed by hand; null when they are not a measurement.
///
/// Accepts `21`, `21.5`, `.5` and `21,5`. Not a measurement: nothing, zero,
/// negative, not a number, or more than [maxTypedInches].
double? parseInchesInput(String text) {
  final cleaned = text.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d*\.?\d*$').hasMatch(cleaned)) return null;

  final inches = double.tryParse(cleaned);
  if (inches == null || !inches.isFinite) return null;
  return inches > 0 && inches <= maxTypedInches ? inches : null;
}

/// [inches] as the text of a measurement box, without trailing zeros: `21`,
/// `27.5`, `27.25`. The same way the description writes it.
String inchesInputText(double inches) => formatInches(inches);
