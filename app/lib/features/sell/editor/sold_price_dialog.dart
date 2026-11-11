/// Asking what it sold for, when it sold.
///
/// Often it sold for what it was listed at, and the box says so; a buyer's
/// offer is the other common case, and the reason this asks at all. The price
/// it sold for is what the sale is worth — it is the figure the Sold list
/// totals — so a sale recorded at the asking price when it went for less
/// overstates what the person made.
///
/// The box starts at the asking price, and what is left after Depop's fees is
/// shown as the number is typed, so the person sees the sale's worth before
/// they confirm it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../list/listing_money.dart';
import 'amount_input.dart';
import 'net_sentence.dart';

/// Asks what a listing sold for. Null if the person backs out; otherwise the
/// price typed in cents, which is null if the box was left empty, in which
/// case the sale takes the asking price.
Future<({int? cents})?> showSoldPriceDialog(
  BuildContext context, {
  required int? asking,
  int? shippingDiscountCents,
}) => showDialog<({int? cents})>(
  context: context,
  builder: (_) => _SoldPriceDialog(
    asking: asking,
    shippingDiscountCents: shippingDiscountCents,
  ),
);

class _SoldPriceDialog extends StatefulWidget {
  const _SoldPriceDialog({required this.asking, this.shippingDiscountCents});

  final int? asking;

  /// The shipping discount on the listing, which comes off what is shown.
  final int? shippingDiscountCents;

  @override
  State<_SoldPriceDialog> createState() => _SoldPriceDialogState();
}

class _SoldPriceDialogState extends State<_SoldPriceDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.asking == null ? '' : usdInputText(widget.asking!),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _blank => _controller.text.trim().isEmpty;

  /// What was typed, when it is a price.
  int? get _typed => _blank ? null : parseUsdInput(_controller.text);

  bool get _valid => _blank || _typed != null;

  /// The price the sale will be recorded at: what was typed, else the asking
  /// price, as the core does.
  int? get _effective => _typed ?? (_blank ? widget.asking : null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final price = _effective;

    return AlertDialog(
      scrollable: true,
      title: const Text('What did it sell for?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,$ ]')),
              LengthLimitingTextInputFormatter(12),
            ],
            decoration: InputDecoration(
              labelText: 'Sold for',
              prefixText: r'$',
              helperText: "Change it if a buyer's offer was lower.",
              helperMaxLines: 3,
              errorText: _valid ? null : 'Use an amount like 32 or 32.50.',
              errorMaxLines: 3,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text(
            price == null
                ? 'Type what it sold for to see what you get.'
                : netSentence(
                    'get',
                    saleNetOf(
                      price,
                      shippingDiscountCents: widget.shippingDiscountCents,
                    ),
                  ),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.of(context).pop((cents: _typed))
              : null,
          child: const Text('Mark as sold'),
        ),
      ],
    );
  }
}
