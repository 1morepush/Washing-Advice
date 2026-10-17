/// Opening a link outside the app.
///
/// What is held here is what the port promises and a recording fake cannot: that
/// the real opener hands the address to the system and not to a view of its own,
/// and that a launch which fails is `false` and not an exception. The platform
/// is replaced at the channel the launcher talks to, so nothing is launched.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/core/link_opener.dart';
import 'package:washing_advice/core/providers.dart';

import '../support/recording_link_opener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final asked = <MethodCall>[];

  /// Answers every call the launcher makes with [answer].
  void platformAnswers(Future<Object?> Function(MethodCall call) answer) {
    asked.clear();
    messenger.setMockMethodCallHandler(channel, (call) {
      asked.add(call);
      return answer(call);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  }

  final depop = Uri.parse('https://www.depop.com/search/?q=nike+crewneck');

  group('the platform opener', () {
    test('asks the system to open the address', () async {
      platformAnswers((_) async => true);

      final opened = await const UrlLauncherLinkOpener().open(depop);

      expect(opened, isTrue);
      final launch = asked.singleWhere((call) => call.method == 'launch');
      final arguments = launch.arguments as Map<Object?, Object?>;
      expect(arguments['url'], depop.toString());
    });

    test('and not in a view of its own', () async {
      // The external mode, which is what lets the system choose the app. Both
      // flags are the launcher's way of saying "inside this app".
      platformAnswers((_) async => true);

      await const UrlLauncherLinkOpener().open(depop);

      final launch = asked.singleWhere((call) => call.method == 'launch');
      final arguments = launch.arguments as Map<Object?, Object?>;
      expect(arguments['useSafariVC'], isFalse);
      expect(arguments['useWebView'], isFalse);
    });

    test('says false when nothing on the device could open it', () async {
      platformAnswers((_) async => false);

      expect(await const UrlLauncherLinkOpener().open(depop), isFalse);
    });

    test('says false when the platform fails, instead of throwing', () async {
      platformAnswers((_) async {
        throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
      });

      expect(await const UrlLauncherLinkOpener().open(depop), isFalse);
    });

    test('says false when there is no platform to ask', () async {
      // A build without the plugin, or a test that never mocked it.
      messenger.setMockMethodCallHandler(channel, null);

      expect(await const UrlLauncherLinkOpener().open(depop), isFalse);
    });
  });

  group('the provider', () {
    test('is the platform opener until a test says otherwise', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(linkOpenerProvider), isA<UrlLauncherLinkOpener>());
    });

    test('can be replaced by one that records, and launches nothing', () async {
      platformAnswers((_) async => true);
      final recording = RecordingLinkOpener();
      final container = ProviderContainer(
        overrides: [linkOpenerProvider.overrideWithValue(recording)],
      );
      addTearDown(container.dispose);

      final opened = await container.read(linkOpenerProvider).open(depop);

      expect(opened, isTrue);
      expect(recording.opened, [depop]);
      expect(recording.last, depop);
      expect(asked, isEmpty, reason: 'nothing should reach the platform');
    });

    test('a recording opener can be made to fail', () async {
      final recording = RecordingLinkOpener(succeeds: false);

      expect(await recording.open(depop), isFalse);
      // Still recorded: it was asked, and could not.
      expect(recording.opened, [depop]);
    });
  });
}
