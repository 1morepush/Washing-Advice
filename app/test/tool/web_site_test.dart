/// The web site assembly (`tool/web_site.dart`), run on temporary directories
/// with small fake builds. No Flutter build is needed to know that the layout,
/// the pruning, the base hrefs, the way back and `versions.json` are right.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/core/data_format.dart';
import 'package:washing_advice/core/version_switch.dart' as app;
import 'package:washing_advice/features/settings/patch_notes.dart';

import '../../tool/web_site.dart' hide main;

/// What Flutter's template yields, cut down to what the tool reads.
String _index(String base) =>
    '''
<!DOCTYPE html>
<html>
<head>
  <base href="$base">
  <title>Washing Advice</title>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
''';

BuildInfo _info(String version, {int wardrobe = 5}) => BuildInfo(
  version: version,
  name: 'Name of $version',
  date: '2026-11-13',
  dataFormat: {'wardrobe': wardrobe, 'images': 1},
);

void main() {
  late Directory tmp;
  late Directory web;

  Directory fakeBuild(String version) {
    final dir = Directory('${tmp.path}/build-$version')..createSync();
    File(
      '${dir.path}/index.html',
    ).writeAsStringSync(_index('/Washing-Advice/'));
    File('${dir.path}/main.dart.js').writeAsStringSync('// app $version');
    File(
      '${dir.path}/flutter_service_worker.js',
    ).writeAsStringSync("// a caching worker, $version\nself.caches;");
    return dir;
  }

  String publishVersion(
    String version, {
    int keep = 5,
    bool lift = false,
    int wardrobe = 5,
  }) => publish(
    build: fakeBuild(version),
    store: Directory('${tmp.path}/store'),
    out: Directory('${tmp.path}/site'),
    base: '/Washing-Advice/',
    info: _info(version, wardrobe: wardrobe),
    keep: keep,
    liftHold: lift,
    webDir: web.path,
    barFile: 'tool/rollback_bar.html',
  );

  String rollBack([String? version]) => rollback(
    store: Directory('${tmp.path}/store'),
    out: Directory('${tmp.path}/site'),
    base: '/Washing-Advice/',
    version: version,
    webDir: web.path,
    barFile: 'tool/rollback_bar.html',
  );

  String site(String path) => File('${tmp.path}/site/$path').readAsStringSync();
  bool has(String path) =>
      File('${tmp.path}/site/$path').existsSync() ||
      Directory('${tmp.path}/site/$path').existsSync();
  Map<String, Object?> versionsJson() =>
      jsonDecode(site('versions.json')) as Map<String, Object?>;
  List<String> listed() => [
    for (final v in versionsJson()['versions']! as List)
      (v as Map)['version']! as String,
  ];

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('web_site_test');
    // The real web/ files, so the pin script and 404 page are the shipped ones.
    web = Directory('web');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('the sources', () {
    test('build info is what the app itself says it is', () {
      final info = readBuildInfo();
      expect(info.version, patchNotes.first.version);
      expect(info.name, patchNotes.first.name);
      expect(
        DateTime.parse('${info.date}T00:00:00Z'),
        patchNotes.first.date,
        reason: 'the date comes from the newest patch note',
      );
      // The tool reads these out of the source text; the app compiles them.
      // If the two ever disagree, the picker would compare the wrong numbers.
      expect(info.dataFormat, currentDataFormat.parts);
    });

    test('versions order by number, not by text', () {
      expect(compareVersions('0.9.0', '0.10.0'), lessThan(0));
      expect(compareVersions('1.0.0', '0.99.99'), greaterThan(0));
      expect(compareVersions('0.38.0', '0.38.0'), 0);
      expect(compareVersions('0.38.0', '0.38.1'), lessThan(0));
    });

    test('the app and the tool order versions the same way', () {
      const samples = ['0.9.0', '0.10.0', '0.38.1', '1.0.0', '0.38.0'];
      for (final a in samples) {
        for (final b in samples) {
          expect(
            compareVersions(a, b).sign,
            // The app's own comparison, in the picker.
            app.compareVersions(a, b).sign,
            reason: '$a vs $b',
          );
        }
      }
    });
  });

  group('the layout', () {
    test('the first run has only the current build, at the root', () {
      final report = publishVersion('0.38.0');

      expect(site('index.html'), contains('<base href="/Washing-Advice/">'));
      expect(has('v'), isFalse);
      expect(listed(), isEmpty);
      expect(versionsJson()['root'], containsPair('version', '0.38.0'));
      expect(report, contains('none yet'));
    });

    test('earlier versions sit under v/ with their own base href', () {
      publishVersion('0.37.0');
      publishVersion('0.38.0');

      expect(listed(), ['0.37.0']);
      expect(site('index.html'), contains('<base href="/Washing-Advice/">'));
      expect(
        site('v/0.37.0/app.html'),
        contains('<base href="/Washing-Advice/v/0.37.0/">'),
      );
      expect(
        site('v/0.37.0/index.html'),
        contains('<base href="/Washing-Advice/v/0.37.0/">'),
      );
      expect(site('v/0.37.0/main.dart.js'), '// app 0.37.0');
      expect(site('main.dart.js'), '// app 0.38.0');
    });

    test('versions.json names each version with its number, name, date and '
        'data format', () {
      publishVersion('0.36.0', wardrobe: 4);
      publishVersion('0.37.0');
      publishVersion('0.38.0');

      final entries = (versionsJson()['versions']! as List).cast<Map>();
      expect(
        entries.map((e) => e['version']),
        containsAll(['0.36.0', '0.37.0']),
      );
      final old = entries.firstWhere((e) => e['version'] == '0.36.0');
      expect(old['name'], 'Name of 0.36.0');
      expect(old['date'], '2026-11-13');
      expect(old['path'], 'v/0.36.0/');
      expect(old['dataFormat'], {'wardrobe': 4, 'images': 1});

      // And the app reads exactly what the tool wrote.
      final parsed = app.SiteVersions.parse(versionsJson());
      expect(parsed.earlier.map((v) => v.version), ['0.37.0', '0.36.0']);
      expect(parsed.earlier.last.dataFormat['wardrobe'], 4);
    });

    test(
      'the way back is in each earlier version, once, and not at the root',
      () {
        publishVersion('0.37.0');
        publishVersion('0.38.0');

        final shell = site('v/0.37.0/index.html');
        expect(RegExp(barMarker).allMatches(shell), hasLength(1));
        expect(shell, contains('You are using <strong>0.37.0</strong>'));
        expect(shell, contains('Back to latest'));
        expect(shell, contains('src="app.html"'));
        expect(shell, isNot(contains('flutter_bootstrap.js')));
        // The page the frame loads is the real one, untouched but for its base.
        expect(site('v/0.37.0/app.html'), contains('flutter_bootstrap.js'));
        expect(site('v/0.37.0/app.html'), isNot(contains(barMarker)));
        expect(site('index.html'), isNot(contains(barMarker)));
      },
    );

    test('running it again over the same store changes nothing', () {
      publishVersion('0.37.0');
      publishVersion('0.38.0');
      final before = site('v/0.37.0/index.html');
      publishVersion('0.38.0');
      expect(site('v/0.37.0/index.html'), before);
      expect(RegExp(barMarker).allMatches(before), hasLength(1));
    });

    test('an earlier version\'s service worker removes itself', () {
      publishVersion('0.37.0');
      publishVersion('0.38.0');
      expect(site('v/0.37.0/flutter_service_worker.js'), selfRemovingWorker);
      expect(site('flutter_service_worker.js'), contains('a caching worker'));
    });

    test('keeps the newest N earlier versions and drops the rest', () {
      for (final v in ['0.30.0', '0.31.0', '0.32.0', '0.33.0', '0.34.0']) {
        publishVersion(v, keep: 3);
      }
      final report = publishVersion('0.35.0', keep: 3);

      expect(listed(), ['0.34.0', '0.33.0', '0.32.0']);
      expect(has('v/0.31.0'), isFalse);
      expect(Directory('${tmp.path}/store/0.31.0').existsSync(), isFalse);
      expect(Directory('${tmp.path}/store/0.35.0').existsSync(), isTrue);
      expect(report, contains('Dropped from the store'));
    });

    test('prunes by number, so 0.9.0 does not outlive 0.10.0', () {
      publishVersion('0.9.0', keep: 1);
      publishVersion('0.10.0', keep: 1);
      publishVersion('0.11.0', keep: 1);
      expect(listed(), ['0.10.0']);
    });

    test('a version whose page cannot take the bar is left out, not shipped '
        'without a way back', () {
      final store = Directory('${tmp.path}/store');
      publishVersion('0.37.0');
      File('${store.path}/0.37.0/index.html').writeAsStringSync(
        _index('/Washing-Advice/').replaceAll(
          '<script src="flutter_bootstrap.js" async></script>',
          '<script src="other.js"></script>',
        ),
      );
      final report = publishVersion('0.38.0');
      expect(listed(), isEmpty);
      expect(has('v/0.37.0'), isFalse);
      expect(report, contains('Not offered'));
    });

    test('the not-found page is published, and clears a pin', () {
      publishVersion('0.38.0');
      expect(site('404.html'), contains(app.pinnedVersionKey));
    });

    test('the pin script, its key and its markers agree with the app', () {
      final html = File('web/index.html').readAsStringSync();
      expect(html, contains(shimStart));
      expect(html, contains(shimEnd));
      expect(html, contains("'${app.pinnedVersionKey}'"));
      expect(
        File('tool/rollback_bar.html').readAsStringSync(),
        contains("'${app.pinnedVersionKey}'"),
      );
      expect(
        File('web/404.html').readAsStringSync(),
        contains("'${app.pinnedVersionKey}'"),
      );
    });
  });

  group('rolling back', () {
    test(
      'puts the chosen version at the root and keeps the others under v/',
      () {
        publishVersion('0.36.0');
        publishVersion('0.37.0');
        publishVersion('0.38.0');

        final report = rollBack('0.37.0');

        expect(site('main.dart.js'), '// app 0.37.0');
        expect(site('index.html'), contains('<base href="/Washing-Advice/">'));
        expect(listed(), containsAll(['0.36.0', '0.38.0']));
        expect(listed(), isNot(contains('0.37.0')));
        expect(versionsJson()['root'], containsPair('version', '0.37.0'));
        expect(report, contains('Rolled back from 0.38.0 to 0.37.0'));
      },
    );

    test('defaults to the version before the one at the root', () {
      publishVersion('0.36.0');
      publishVersion('0.37.0');
      publishVersion('0.38.0');
      rollBack();
      expect(site('main.dart.js'), '// app 0.37.0');
    });

    test(
      'a root from before the pin script gets it, so pins and ?latest=1 work',
      () {
        publishVersion('0.37.0');
        publishVersion('0.38.0');
        expect(
          File('${tmp.path}/store/0.37.0/index.html').readAsStringSync(),
          isNot(contains(shimStart)),
        );
        rollBack('0.37.0');
        final html = site('index.html');
        expect(html, contains(shimStart));
        expect(RegExp(shimStart).allMatches(html), hasLength(1));
        expect(html.indexOf(shimStart), greaterThan(html.indexOf('<base')));
      },
    );

    test('refuses a version that is not in the store, and says what is', () {
      publishVersion('0.37.0');
      publishVersion('0.38.0');
      expect(
        () => rollBack('0.12.0'),
        throwsA(
          isA<SiteError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('0.12.0 is not in the build store'),
              contains('0.38.0, 0.37.0'),
            ),
          ),
        ),
      );
      // Nothing changed.
      expect(site('main.dart.js'), '// app 0.38.0');
    });

    test('refuses what is not a version, and the version already live', () {
      publishVersion('0.37.0');
      publishVersion('0.38.0');
      expect(() => rollBack('latest'), throwsA(isA<SiteError>()));
      expect(() => rollBack('0.38.0'), throwsA(isA<SiteError>()));
    });

    test('says so plainly when nothing has ever been stored', () {
      expect(
        rollBack,
        throwsA(
          isA<SiteError>().having(
            (e) => e.message,
            'message',
            contains('nothing to roll back'),
          ),
        ),
      );
    });

    test('has nothing to default to on the very first release', () {
      publishVersion('0.38.0');
      expect(
        rollBack,
        throwsA(
          isA<SiteError>().having(
            (e) => e.message,
            'message',
            contains('No version older than 0.38.0'),
          ),
        ),
      );
    });
  });

  group('the hold', () {
    void rolledBack() {
      publishVersion('0.37.0');
      publishVersion('0.38.0');
      rollBack('0.37.0');
    }

    test('an unrelated push that ships the same version leaves it alone', () {
      rolledBack();
      final report = publishVersion('0.38.0');

      expect(site('main.dart.js'), '// app 0.37.0');
      expect(report, contains('Rollback in effect'));
      expect(listed(), ['0.38.0']);
    });

    test('a release newer than the one rolled back from ends it', () {
      rolledBack();
      final report = publishVersion('0.38.1');

      expect(site('main.dart.js'), '// app 0.38.1');
      expect(report, contains('hold on 0.37.0 ended'));
      expect(listed(), containsAll(['0.37.0', '0.38.0']));
      // And the next ordinary push is ordinary.
      publishVersion('0.38.1');
      expect(site('main.dart.js'), '// app 0.38.1');
    });

    test('can be lifted by hand', () {
      rolledBack();
      final report = publishVersion('0.38.0', lift: true);
      expect(site('main.dart.js'), '// app 0.38.0');
      expect(report, contains('lifted'));
    });

    test('rolling back again keeps the release it is waiting for', () {
      publishVersion('0.36.0');
      publishVersion('0.37.0');
      publishVersion('0.38.0');
      rollBack('0.37.0');
      rollBack('0.36.0');

      expect(site('main.dart.js'), '// app 0.36.0');
      // 0.38.0, not 0.37.0, is what a new release has to beat.
      publishVersion('0.37.5');
      expect(site('main.dart.js'), '// app 0.36.0');
      publishVersion('0.38.1');
      expect(site('main.dart.js'), '// app 0.38.1');
    });
  });
}
