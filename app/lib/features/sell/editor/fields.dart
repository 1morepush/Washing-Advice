/// The pieces every section of the listing editor is made of.
///
/// A card with a heading, a text box, and a number box. They exist because the
/// editor's boxes have one job the framework's do not: staying where they are.
/// The listing behind a box changes whenever it is saved, and a box that was
/// rewritten from the listing every time would move the cursor, throw away a
/// word half typed, or turn "3.5" into "3.50" under somebody's finger.
///
/// So a box here owns its text. It is filled once, from the listing as it was
/// loaded, and from then on only the person changes it. The one exception is
/// the listing being changed by something other than typing in that box — the
/// price set from "Use $30.00", a search phrase that follows the title until
/// somebody edits it — and the box tells that apart by remembering what it last
/// told the listing: a value it did not say is not an echo, and is shown.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/rinse_kit.dart';

/// One card of the editor: a heading, a line of explanation if it needs one,
/// and what the card is for.
///
/// Spaced and padded like the sections of the garment page, so the two read
/// as the same kind of screen.
class EditorSection extends StatelessWidget {
  const EditorSection({
    required this.title,
    required this.children,
    this.intro,
    super.key,
  });

  final String title;

  /// A sentence under the heading saying what the section is for.
  final String? intro;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: RinseCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Its own node, so a screen reader finds a heading and not one
            // card read out as a single line.
            Semantics(
              container: true,
              header: true,
              child: Text(title, style: groupHeadingStyle(context)),
            ),
            if (intro case final String intro) ...[
              const SizedBox(height: 4),
              Text(
                intro,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A heading inside a card, for one part of what the card is about.
class SubHeading extends StatelessWidget {
  const SubHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    header: true,
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

/// A line of small, quiet text under a field or a heading.
class QuietText extends StatelessWidget {
  const QuietText(this.text, {this.color, super.key});

  final String text;

  /// Replaces the quiet colour, for a line that is a problem.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: color ?? theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// A text box for a word or a few, filled from [value] once.
///
/// [onChanged] hears every edit, as it is typed. [value] is what the listing
/// holds for this box; a [value] other than what the box last said (see the
/// library comment) is a change from somewhere else and replaces the text, with
/// the cursor at its end.
///
/// What is said is the text exactly as typed, spaces and all. Trimming it here
/// would make the listing's value differ from the box's after every space, and
/// the box would take that for a change from elsewhere and eat the space.
class EditorTextField extends StatefulWidget {
  const EditorTextField({
    required this.value,
    required this.onChanged,
    required this.label,
    this.hint,
    this.helper,
    this.minLines,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onSubmitted,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  /// What an empty box suggests, shown once it is focused.
  final String? hint;

  /// A line under the box, for what it is for or what to do about it.
  final String? helper;

  final int? minLines;
  final int? maxLines;
  final TextCapitalization textCapitalization;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;

  @override
  State<EditorTextField> createState() => _EditorTextFieldState();
}

class _EditorTextFieldState extends State<EditorTextField> {
  late final TextEditingController _controller;

  /// What this box last told the listing, which is what the listing will hold
  /// next, so a [EditorTextField.value] equal to it is the box's own echo.
  ///
  /// Set in [initState] and not by a `late` initializer: that would run on
  /// first use, which can be the first rebuild, by when [widget] already holds
  /// the new value and the old one is gone.
  late String _said;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _said = widget.value;
  }

  @override
  void didUpdateWidget(EditorTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == _said) return;

    _said = widget.value;
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _said = text;
    widget.onChanged(text);
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    minLines: widget.minLines,
    maxLines: widget.maxLines,
    textCapitalization: widget.textCapitalization,
    keyboardType: widget.keyboardType,
    textInputAction: widget.textInputAction,
    inputFormatters: widget.inputFormatters,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      hintMaxLines: 3,
      helperText: widget.helper,
      helperMaxLines: 4,
      // The label stays above the text however long a hint is, so a long
      // hint under large text does not sit on top of it.
      floatingLabelBehavior: FloatingLabelBehavior.always,
    ),
    onChanged: _changed,
    onSubmitted: widget.onSubmitted,
  );
}

/// A box for an amount — dollars, inches — read from what is typed.
///
/// [parse] says what the text means, or null when it means nothing (see
/// `amount_input.dart`). Nothing is not an error while it is being typed: "0"
/// on the way to "0.75" is not an amount, and neither is "3.555", and in
/// neither case does the box say so or change what the listing holds. It
/// ignores the text, leaves it as typed, and says so under the box once the
/// person has gone elsewhere (see [invalidMessage]).
///
/// Emptying the box says null, which the listing takes as "no value".
///
/// As for [EditorTextField], the box is filled from [value] once and a
/// [value] it did not itself say is a change from elsewhere.
class ParsedField<T extends Object> extends StatefulWidget {
  const ParsedField({
    required this.value,
    required this.parse,
    required this.format,
    required this.onChanged,
    required this.label,
    this.invalidMessage = 'That is not a number I can use.',
    this.helper,
    this.prefixText,
    this.suffixText,
    this.textInputAction,
    this.onSubmitted,
    super.key,
  });

  final T? value;

  /// What [value] is for text: the box shows [format] of it.
  final T? Function(String text) parse;
  final String Function(T value) format;

  /// Told the amount as it is typed, or null when the box is emptied.
  final ValueChanged<T?> onChanged;

  final String label;
  final String invalidMessage;
  final String? helper;
  final String? prefixText;
  final String? suffixText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<ParsedField<T>> createState() => _ParsedFieldState<T>();
}

class _ParsedFieldState<T extends Object> extends State<ParsedField<T>> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();

  /// What this box last told the listing; see [_EditorTextFieldState._said].
  late T? _said;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _shown(widget.value));
    _said = widget.value;
    // The message waits until the person has moved on, so that a number on its
    // way to being valid is not told off on the way.
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  String _shown(T? value) => value == null ? '' : widget.format(value);

  @override
  void didUpdateWidget(ParsedField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == _said) return;

    _said = widget.value;
    _invalid = false;
    _controller.value = TextEditingValue(
      text: _shown(widget.value),
      selection: TextSelection.collapsed(offset: _shown(widget.value).length),
    );
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String text) {
    if (text.trim().isEmpty) {
      setState(() => _invalid = false);
      _said = null;
      widget.onChanged(null);
      return;
    }

    final amount = widget.parse(text);
    setState(() => _invalid = amount == null);
    if (amount == null) return;

    _said = amount;
    widget.onChanged(amount);
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    focusNode: _focus,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textInputAction: widget.textInputAction,
    // Digits and the marks an amount is written with. Everything else a
    // keyboard or a paste might bring is dropped before it is read.
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,$ ]')),
      LengthLimitingTextInputFormatter(12),
    ],
    decoration: InputDecoration(
      labelText: widget.label,
      prefixText: widget.prefixText,
      suffixText: widget.suffixText,
      helperText: widget.helper,
      helperMaxLines: 4,
      errorText: _invalid && !_focus.hasFocus ? widget.invalidMessage : null,
      errorMaxLines: 3,
      floatingLabelBehavior: FloatingLabelBehavior.always,
    ),
    onChanged: _changed,
    onSubmitted: widget.onSubmitted,
  );
}
