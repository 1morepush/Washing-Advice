/// The editor's boxes stay where they are.
///
/// The listing behind a box is saved while it is typed in, and comes back round
/// to the box as a new value each time. A box that took every one of those for
/// a change would move the cursor, drop a trailing space, or rewrite "3.5" as
/// "3.50" while a finger was still on the way to "3.55". These hold the boxes
/// to showing the listing only when something other than their own typing
/// changed it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/core/theme.dart';
import 'package:washing_advice/features/sell/editor/amount_input.dart';
import 'package:washing_advice/features/sell/editor/fields.dart';

void main() {
  Widget harness(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );

  EditableText editable(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText));

  group('a text box', () {
    late String value;
    late StateSetter rebuild;
    late List<String> said;

    Future<void> pump(WidgetTester tester, {String initial = 'hello'}) async {
      value = initial;
      said = [];
      await tester.pumpWidget(
        harness(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return EditorTextField(
                value: value,
                label: 'Title',
                onChanged: (text) => setState(() {
                  value = text;
                  said.add(text);
                }),
              );
            },
          ),
        ),
      );
    }

    testWidgets('starts with what the listing holds', (tester) async {
      await pump(tester, initial: 'Nike crewneck');

      expect(find.text('Nike crewneck'), findsOneWidget);
      expect(said, isEmpty);
    });

    testWidgets('says what is typed, as it is typed', (tester) async {
      await pump(tester, initial: '');

      await tester.enterText(find.byType(TextField), 'Nike');
      await tester.enterText(find.byType(TextField), 'Nike vintage');

      expect(said, ['Nike', 'Nike vintage']);
    });

    testWidgets('keeps the cursor where it is as the listing echoes it', (
      tester,
    ) async {
      await pump(tester);
      await tester.showKeyboard(find.byType(TextField));

      // A letter typed in the middle of the word, as a keyboard sends it.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'heXllo',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pump();

      expect(value, 'heXllo');
      expect(editable(tester).controller.text, 'heXllo');
      expect(editable(tester).controller.selection.baseOffset, 3);
    });

    testWidgets('keeps a space typed at the end', (tester) async {
      // The listing is told the text exactly as typed. Trimmed, the echo would
      // not match, and the box would take it for a change from elsewhere.
      await pump(tester, initial: 'Nike');
      await tester.showKeyboard(find.byType(TextField));

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Nike ',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();

      expect(editable(tester).controller.text, 'Nike ');
    });

    testWidgets('shows a value that came from somewhere else', (tester) async {
      await pump(tester);

      rebuild(() => value = 'changed elsewhere');
      await tester.pump();

      expect(editable(tester).controller.text, 'changed elsewhere');
      expect(editable(tester).controller.selection.baseOffset, 17);
      // Showing it is not saying it: nothing was typed.
      expect(said, isEmpty);
    });

    testWidgets('shows a value from elsewhere that undoes what was typed', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'typed');

      rebuild(() => value = 'hello');
      await tester.pump();

      expect(editable(tester).controller.text, 'hello');
    });

    testWidgets('is the same box through a rebuild', (tester) async {
      await pump(tester);
      final before = editable(tester).controller;

      rebuild(() {});
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'more');
      await tester.pump();

      expect(editable(tester).controller, same(before));
    });
  });

  group('an amount box', () {
    late int? value;
    late StateSetter rebuild;
    late List<int?> said;

    Future<void> pump(WidgetTester tester, {int? initial = 3000}) async {
      value = initial;
      said = [];
      await tester.pumpWidget(
        harness(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return ParsedField<int>(
                value: value,
                parse: parseUsdInput,
                format: usdInputText,
                label: 'Your price',
                prefixText: r'$',
                invalidMessage: 'Use an amount like 32 or 32.50.',
                onChanged: (cents) => setState(() {
                  value = cents;
                  said.add(cents);
                }),
              );
            },
          ),
        ),
      );
    }

    testWidgets('starts with the amount, written as typed', (tester) async {
      await pump(tester, initial: 3050);

      expect(editable(tester).controller.text, '30.50');
    });

    testWidgets('starts empty when there is no amount', (tester) async {
      await pump(tester, initial: null);

      expect(editable(tester).controller.text, isEmpty);
    });

    testWidgets('says the amount as it is typed', (tester) async {
      await pump(tester, initial: null);

      await tester.enterText(find.byType(TextField), '28');
      await tester.enterText(find.byType(TextField), '28.5');

      expect(said, [2800, 2850]);
    });

    testWidgets('does not rewrite "3.5" as "3.50" while it is typed', (
      tester,
    ) async {
      await pump(tester, initial: null);

      await tester.enterText(find.byType(TextField), '3.5');
      await tester.pump();

      expect(value, 350);
      expect(editable(tester).controller.text, '3.5');
    });

    testWidgets('can be typed from nothing through a zero', (tester) async {
      // "0" is not a price, and "0.75" is. The box must not put the old price
      // back between them.
      await pump(tester);

      await tester.enterText(find.byType(TextField), '0');
      await tester.pump();
      expect(editable(tester).controller.text, '0');

      await tester.enterText(find.byType(TextField), '0.7');
      await tester.enterText(find.byType(TextField), '0.75');
      await tester.pump();

      expect(editable(tester).controller.text, '0.75');
      expect(value, 75);
    });

    testWidgets('ignores an amount it cannot read, and keeps the last', (
      tester,
    ) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), '0');
      await tester.pump();

      expect(said, isEmpty);
      expect(value, 3000);
    });

    testWidgets('waits to complain until the person has moved on', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '0');
      await tester.pump();

      expect(find.text('Use an amount like 32 or 32.50.'), findsNothing);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(find.text('Use an amount like 32 or 32.50.'), findsOneWidget);
    });

    testWidgets('stops complaining once it can be read', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), '0');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.text('Use an amount like 32 or 32.50.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '5');
      await tester.pump();

      expect(find.text('Use an amount like 32 or 32.50.'), findsNothing);
    });

    testWidgets('says nothing when it is emptied', (tester) async {
      await pump(tester);

      await tester.enterText(find.byType(TextField), '');

      expect(said, [null]);
      expect(value, isNull);
    });

    testWidgets('drops what an amount is not written with', (tester) async {
      await pump(tester, initial: null);

      await tester.enterText(find.byType(TextField), r'$ 1,2a3b');

      expect(editable(tester).controller.text, r'$ 1,23');
    });

    testWidgets('shows an amount that was set from elsewhere', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), '0');

      rebuild(() => value = 2850);
      await tester.pump();

      expect(editable(tester).controller.text, '28.50');
      expect(find.text('Use an amount like 32 or 32.50.'), findsNothing);
    });
  });

  group('inches', () {
    testWidgets('are read as typed and shown without trailing zeros', (
      tester,
    ) async {
      double? value = 27.5;
      await tester.pumpWidget(
        harness(
          StatefulBuilder(
            builder: (context, setState) => ParsedField<double>(
              value: value,
              parse: parseInchesInput,
              format: inchesInputText,
              label: 'Length',
              suffixText: 'in',
              onChanged: (inches) => setState(() => value = inches),
            ),
          ),
        ),
      );
      expect(editable(tester).controller.text, '27.5');

      await tester.enterText(find.byType(TextField), '28.25');
      await tester.pump();

      expect(value, 28.25);
    });
  });

  group('a section', () {
    testWidgets('has a heading, a line about it, and its parts', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        harness(
          const EditorSection(
            title: 'Shipping',
            intro: 'What it costs to send.',
            children: [Text('A part')],
          ),
        ),
      );

      expect(find.text('Shipping'), findsOneWidget);
      expect(find.text('What it costs to send.'), findsOneWidget);
      expect(find.text('A part'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Shipping')),
        isSemantics(label: 'Shipping', isHeader: true),
      );
      semantics.dispose();
    });
  });
}
