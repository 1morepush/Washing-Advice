/// The sentence that says what a sale leaves the seller.
///
/// Said in three places in the editor (the asking price, the sale price being
/// recorded, the finished sale), and it must be the same sentence in each, so
/// it is written once. The figures are the core's: [sale] comes from
/// `DepopFees.saleNet`, through `saleNetOf`.
library;

import 'package:wardrobe_core/wardrobe_core.dart';

/// `You get $24.56 after Depop's fees (3.3% + $0.45) and $4.00 shipping
/// discount`; without a discount, the same without its last words.
///
/// [verb] is `get` for a sale that may happen and `got` for one that did.
String netSentence(String verb, SaleNet sale) {
  const fees = DepopFees.us;
  final discount = sale.hasDiscount
      ? ' and ${formatUsd(sale.shippingDiscountCents)} shipping discount'
      : '';
  return 'You $verb ${formatUsd(sale.netCents)} after Depop\'s fees '
      '(${fees.label})$discount';
}

/// The warning for a discount that, with the fees, is more than the sale, or
/// null when it is not.
///
/// Said as what will happen to the seller: they get nothing, and by how much
/// they would be out of pocket on top of it.
String? shortfallWarning(SaleNet sale) => sale.hasShortfall
    ? "Your shipping discount and Depop's fees come to more than the price. "
          "You'd get nothing and be ${formatUsd(sale.shortfallCents)} out of "
          'pocket.'
    : null;
