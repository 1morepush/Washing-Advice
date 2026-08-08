/// Entering a washer or dryer by its exact brand and model, driven through
/// the real [MachineSection] widget.
///
/// The server call itself is proven correct in `ai_gateway_test.dart`; what
/// matters here is the other half — that a real tap sequence on the actual
/// widget tree ends with the right thing persisted and the right thing shown,
/// and that a refusal or a network failure leaves the entry form usable
/// rather than stuck.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:washing_advice/core/providers.dart';
import 'package:washing_advice/core/settings.dart';
import 'package:washing_advice/data/api/ai_gateway.dart';
import 'package:washing_advice/features/settings/machine_section.dart';

void main() {
  late SettingsStore settings;
  late ProviderContainer container;

  Future<void> pump(
    WidgetTester tester, {
    required MockClientHandler handler,
  }) async {
    SharedPreferences.setMockInitialValues({});
    settings = SettingsStore(await SharedPreferences.getInstance());

    container = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(settings),
        aiGatewayProvider.overrideWithValue(
          AiGateway(
            baseUrl: Uri.parse('https://washing-advice.test/'),
            client: MockClient(handler),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1000, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MachineSection(kind: MachineKind.washer),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<http.Response> respondWithProfile(http.Request request) async {
    final body = jsonDecode(request.body) as Map<String, Object?>;
    return http.Response(
      // The full shape the real server sends (captured from a live run
      // against the fake provider) — a fixture missing a field the real
      // response always includes would pass here and break for real.
      jsonEncode({
        'result': {
          'id': 'ai.washer.x',
          'brand': body['brand'],
          'model': body['model'],
          'capacityKg': 9.0,
          'programs': [
            {
              'id': 'p0',
              'displayName': 'Cotton',
              'kind': 'cotton',
              'availableTempsC': [0, 30, 40],
              'defaultTempC': 40,
              'agitation': 'normal',
              'spinSpeedsRpm': [0, 600, 800],
              'suitableFor': ['normal'],
              'maxLoadFraction': 1.0,
              'typicalDurationMinutes': 120,
            },
          ],
          'options': <String>[],
          'isVerifiedModel': false,
        },
      }),
      200,
    );
  }

  Future<http.Response> respondNotIdentified(http.Request request) async =>
      http.Response(
        '{"error": "machine_not_identified", '
        '"detail": "no reliable knowledge of this exact make and model", '
        '"hint": "Try just the brand instead."}',
        422,
      );

  testWidgets('picking a seeded brand persists it', (tester) async {
    await pump(tester, handler: (_) async => http.Response('', 500));

    await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bosch').last);
    await tester.pumpAndSettle();

    expect(settings.washerBrand, 'Bosch');
    expect(container.read(washerProvider)?.brand, 'Bosch');
  });

  testWidgets("the entry form is hidden until asked for", (tester) async {
    await pump(tester, handler: (_) async => http.Response('', 500));

    expect(find.text('Brand'), findsNothing);

    await tester.tap(find.text("Don't see it? Enter the exact model"));
    await tester.pumpAndSettle();

    expect(find.text('Brand'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
  });

  testWidgets('identifying a real model shows it, and the picker is replaced', (
    tester,
  ) async {
    await pump(tester, handler: respondWithProfile);

    await tester.tap(find.text("Don't see it? Enter the exact model"));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Brand'), 'Samsung');
    await tester.enterText(
      find.widgetWithText(TextField, 'Model'),
      'WF45T6000AW',
    );
    await tester.tap(find.text('Identify'));
    await tester.pumpAndSettle();

    expect(find.text('Samsung WF45T6000AW'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String?>), findsNothing);
    expect(
      settings.customWasher?.toJson(),
      container.read(customWasherProvider)?.toJson(),
    );
    expect(settings.customWasher?.brand, 'Samsung');
  });

  testWidgets('a machine the model does not recognise leaves the form usable', (
    tester,
  ) async {
    await pump(tester, handler: respondNotIdentified);

    await tester.tap(find.text("Don't see it? Enter the exact model"));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Brand'), 'Nonesuch');
    await tester.enterText(find.widgetWithText(TextField, 'Model'), 'XY9000');
    await tester.tap(find.text('Identify'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no reliable knowledge'), findsOneWidget);
    // The form is still there to try again, not replaced by a card for a
    // profile that was never actually built.
    expect(find.widgetWithText(TextField, 'Brand'), findsOneWidget);
    expect(settings.customWasher, isNull);
  });

  testWidgets('cancelling the entry form asks nothing of the server', (
    tester,
  ) async {
    var called = false;
    await pump(
      tester,
      handler: (request) async {
        called = true;
        return respondWithProfile(request);
      },
    );

    await tester.tap(find.text("Don't see it? Enter the exact model"));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Brand'), 'Samsung');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('Brand'), findsNothing);
  });

  testWidgets('removing a custom profile falls back to the picker', (
    tester,
  ) async {
    await pump(tester, handler: respondWithProfile);
    await tester.tap(find.text("Don't see it? Enter the exact model"));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Brand'), 'Samsung');
    await tester.enterText(
      find.widgetWithText(TextField, 'Model'),
      'WF45T6000AW',
    );
    await tester.tap(find.text('Identify'));
    await tester.pumpAndSettle();
    expect(find.text('Samsung WF45T6000AW'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Samsung WF45T6000AW'), findsNothing);
    expect(find.byType(DropdownButtonFormField<String?>), findsOneWidget);
    expect(settings.customWasher, isNull);
  });
}
