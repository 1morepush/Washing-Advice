// Assembles the web site that GitHub Pages serves: the current build at the
// root, and the last few releases each under `v/<version>/`.
//
// Pages deploys one artifact that replaces the whole site, so a release that is
// merely *built* is gone from the web the moment the next one deploys. This is
// what keeps them: finished builds live in a store (a directory here; the
// `web-builds` branch in the workflows, see `.github/workflows/web-deploy.yml`),
// and every deploy lays the site out again from that store.
//
// Pure Dart on `dart:io`, with no package imports, so a workflow can run it
// with `dart tool/web_site.dart` without resolving the app's dependencies, and
// so a test can drive it against a temporary directory. Run from `app/`.
//
//   dart tool/web_site.dart build-info  [--out build/web/build-info.json]
//   dart tool/web_site.dart publish     --build build/web --store S --out O
//                                       --base /Washing-Advice/
//                                       [--keep 5] [--lift-hold]
//   dart tool/web_site.dart rollback    --store S --out O --base /Washing-Advice/
//                                       [--version 0.37.0]
//
// Everything printed is Markdown, for the workflow's job summary.
library;

import 'dart:convert';
import 'dart:io';

/// How many earlier releases the store keeps besides the current one.
const defaultKeep = 5;

/// Written into every page this tool changes, so running it again over output
/// it already produced changes nothing. (It never does: each run starts from
/// the store's pristine copies. The marker is for the tests and for a person
/// reading the published HTML.)
const barMarker = 'washing-advice-rollback-bar';
const shimStart = '<!-- wa-pin-shim:start -->';
const shimEnd = '<!-- wa-pin-shim:end -->';

/// What Flutter's template puts last in `<body>`: the line that starts the app.
const _bootstrapTag = '<script src="flutter_bootstrap.js" async></script>';

/// Thrown for anything the person running this needs to be told in words.
class SiteError implements Exception {
  SiteError(this.message);
  final String message;
  @override
  String toString() => message;
}

// --- Versions ---------------------------------------------------------------

/// `0.38.0` as numbers, or null when it is not one.
List<int>? parseVersion(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(version);
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

/// Orders `0.9.0` before `0.10.0`, which comparing the strings would not.
int compareVersions(String a, String b) {
  final left = parseVersion(a), right = parseVersion(b);
  if (left == null || right == null) {
    throw SiteError('"$a" and "$b" are not both versions like 1.2.3.');
  }
  for (var i = 0; i < 3; i++) {
    if (left[i] != right[i]) return left[i].compareTo(right[i]);
  }
  return 0;
}

// --- What a build is --------------------------------------------------------

/// One build's identity and the layout of the data it reads and writes.
class BuildInfo {
  BuildInfo({
    required this.version,
    required this.name,
    required this.date,
    required this.dataFormat,
  });

  factory BuildInfo.fromJson(Map<String, Object?> json) => BuildInfo(
    version: json['version']! as String,
    name: json['name']! as String,
    date: json['date']! as String,
    dataFormat: {
      for (final entry in (json['dataFormat']! as Map<String, Object?>).entries)
        entry.key: entry.value! as int,
    },
  );

  final String version;
  final String name;

  /// `2026-11-13`.
  final String date;

  /// Each stored thing that has a layout, and the number this build writes it
  /// at. A build can read what is stored only if every number here is at least
  /// the stored one. See `lib/core/data_format.dart`, which does that sum in
  /// the app, and `settings_screen` for where it is shown.
  final Map<String, int> dataFormat;

  Map<String, Object?> toJson() => {
    'version': version,
    'name': name,
    'date': date,
    'dataFormat': dataFormat,
  };
}

/// Reads the version, its name and date, and the data format from the app's
/// own sources, so there is no second hand-kept list to drift.
///
/// Textual rather than imported: `patch_notes.dart` pulls in Flutter, which a
/// plain `dart` script cannot load. The newest release is the first `Release(`
/// in the file, which `test/features/patch_notes_test.dart` guarantees.
BuildInfo readBuildInfo({String appDir = '.'}) {
  String read(String path) {
    final file = File('$appDir/$path');
    if (!file.existsSync()) throw SiteError('Cannot find $path.');
    return file.readAsStringSync();
  }

  final notes = read('lib/features/settings/patch_notes.dart');
  final release = RegExp(
    r'''Release\(\s*version:\s*'([^']+)',\s*name:\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)"),\s*date:\s*DateTime\.utc\((\d+),\s*(\d+),\s*(\d+)\)''',
  ).firstMatch(notes);
  if (release == null) {
    throw SiteError('Cannot find the newest release in patch_notes.dart.');
  }
  final version = release.group(1)!;
  final rawName = release.group(2) ?? release.group(3)!;
  final name = rawName.replaceAllMapped(
    RegExp(r'\\(.)'),
    (match) => match.group(1)!,
  );
  final date =
      '${release.group(4)!.padLeft(4, '0')}-'
      '${release.group(5)!.padLeft(2, '0')}-'
      '${release.group(6)!.padLeft(2, '0')}';

  final pubspec = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)',
    multiLine: true,
  ).firstMatch(read('pubspec.yaml'));
  if (pubspec?.group(1) != version) {
    throw SiteError(
      'pubspec.yaml says ${pubspec?.group(1)} but the newest patch note is '
      '$version.',
    );
  }

  int schema(String path) {
    final match = RegExp(
      r'currentSchemaVersion\s*=\s*(\d+)',
    ).firstMatch(read(path));
    if (match == null) throw SiteError('No currentSchemaVersion in $path.');
    return int.parse(match.group(1)!);
  }

  return BuildInfo(
    version: version,
    name: name,
    date: date,
    dataFormat: {
      'wardrobe': schema('lib/data/drift/database.dart'),
      'images': schema('lib/data/images/image_database.dart'),
    },
  );
}

// --- The store --------------------------------------------------------------

/// What the store remembers besides the builds.
class StoreState {
  StoreState({this.root, this.hold});

  factory StoreState.read(Directory store) {
    final file = File('${store.path}/state.json');
    if (!file.existsSync()) return StoreState();
    final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final hold = json['hold'] as Map<String, Object?>?;
    return StoreState(
      root: json['root'] as String?,
      hold: hold == null
          ? null
          : Hold(
              from: hold['from']! as String,
              to: hold['to']! as String,
              at: hold['at']! as String,
            ),
    );
  }

  /// The version at the site root as last deployed.
  String? root;

  /// Set by the rollback workflow; cleared by a newer release.
  Hold? hold;

  void write(Directory store) {
    File('${store.path}/state.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'root': root, 'hold': hold?.toJson()})}\n',
    );
  }
}

/// A rollback in force: the root holds [to] until a release newer than [from].
class Hold {
  Hold({required this.from, required this.to, required this.at});
  final String from;
  final String to;
  final String at;
  Map<String, Object?> toJson() => {'from': from, 'to': to, 'at': at};
}

/// The versions in [store], newest first, each with its build info.
List<BuildInfo> storedBuilds(Directory store) {
  final builds = <BuildInfo>[];
  if (!store.existsSync()) return builds;
  for (final entry in store.listSync()) {
    if (entry is! Directory) continue;
    final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (parseVersion(name) == null) continue;
    final info = File('${entry.path}/build-info.json');
    if (!info.existsSync()) continue;
    builds.add(
      BuildInfo.fromJson(
        jsonDecode(info.readAsStringSync()) as Map<String, Object?>,
      ),
    );
  }
  builds.sort((a, b) => compareVersions(b.version, a.version));
  return builds;
}

/// Puts [build] into [store] as `<version>/`, replacing any build of the same
/// version, then drops everything older than the newest `keep + 1` versions.
/// Returns the versions it pruned.
///
/// The build keeps the `--base-href` it was made with. Where it will be served
/// is decided when the site is laid out, which is what lets one stored build
/// serve either as an earlier version under `v/` or as the root.
List<String> updateStore({
  required Directory store,
  required Directory build,
  required BuildInfo info,
  int keep = defaultKeep,
}) {
  store.createSync(recursive: true);
  final target = Directory('${store.path}/${info.version}');
  if (target.existsSync()) target.deleteSync(recursive: true);
  copyTree(build, target);
  File(
    '${target.path}/build-info.json',
  ).writeAsStringSync('${jsonEncode(info.toJson())}\n');

  final pruned = <String>[];
  final builds = storedBuilds(store);
  for (final stale in builds.skip(keep + 1)) {
    Directory('${store.path}/${stale.version}').deleteSync(recursive: true);
    pruned.add(stale.version);
  }
  return pruned;
}

// --- Laying the site out ----------------------------------------------------

/// What laying the site out did, for the summary.
class SiteResult {
  SiteResult({
    required this.root,
    required this.earlier,
    required this.skipped,
  });
  final String root;
  final List<BuildInfo> earlier;
  final Map<String, String> skipped;
}

/// Writes the whole site into [out]: [rootVersion] at the root, every other
/// stored version under `v/<version>/`, `versions.json` and `404.html`.
///
/// [base] is the path the site is served from, `/Washing-Advice/`.
/// [webDir] is the app's `web/` source folder, which holds the one copy of the
/// pin script and of the not-found page; [barFile] is the bar's markup.
SiteResult assembleSite({
  required Directory store,
  required String rootVersion,
  required Directory out,
  required String base,
  String webDir = 'web',
  String barFile = 'tool/rollback_bar.html',
}) {
  if (!base.startsWith('/') || !base.endsWith('/')) {
    throw SiteError('--base must start and end with a slash, not "$base".');
  }
  final builds = storedBuilds(store);
  final rootBuild = builds.where((b) => b.version == rootVersion).firstOrNull;
  if (rootBuild == null) {
    throw SiteError('Version $rootVersion is not in the store.');
  }
  if (out.existsSync()) out.deleteSync(recursive: true);

  // The root: the stored build, based at the site root, with the pin script
  // guaranteed present. A current build already has it, from `web/index.html`.
  // A rolled-back one predates it and gets it here, so the escape hatch and
  // the pin work whichever build the root is.
  copyTree(Directory('${store.path}/$rootVersion'), out);
  final rootIndex = File('${out.path}/index.html');
  var rootHtml = _rebase(rootIndex.readAsStringSync(), base);
  if (!rootHtml.contains(shimStart)) {
    rootHtml = _injectShim(rootHtml, _readShim(webDir));
  }
  rootIndex.writeAsStringSync(rootHtml);
  final notFound = File('$webDir/404.html');
  if (notFound.existsSync()) notFound.copySync('${out.path}/404.html');

  final bar = File(barFile).readAsStringSync();
  final earlier = <BuildInfo>[];
  final skipped = <String, String>{};
  for (final build in builds) {
    if (build.version == rootVersion) continue;
    final dir = Directory('${out.path}/v/${build.version}');
    copyTree(Directory('${store.path}/${build.version}'), dir);
    try {
      _prepareEarlier(dir, '${base}v/${build.version}/', build.version, bar);
      earlier.add(build);
    } on SiteError catch (error) {
      // A version that cannot be given its way back is not offered: a person
      // who opened it could not leave, which is worse than not having it.
      dir.deleteSync(recursive: true);
      skipped[build.version] = error.message;
    }
  }

  File('${out.path}/versions.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'schema': 1,
      'root': rootBuild.toJson(),
      'versions': [
        for (final build in earlier) {...build.toJson(), 'path': 'v/${build.version}/'},
      ],
    })}\n',
  );
  return SiteResult(root: rootVersion, earlier: earlier, skipped: skipped);
}

/// Makes a stored build safe to serve from `v/<version>/`.
///
/// * Its `<base href>` is its own path, so every asset it asks for resolves
///   inside it.
/// * Its service worker is replaced with one that removes itself. Service
///   workers are scoped by path, and the root's scope contains every `v/`
///   path; an old build's caching worker would answer for the wrong version.
///   Flutter's own worker became exactly this stub in the pinned version, so
///   for current builds this changes nothing.
/// * `index.html` becomes a frame around the real page with the way back in
///   it. Flutter's view sizes itself to the window and paints over anything
///   else in the page, so a bar in the page itself would either hide the app
///   bar or the navigation bar; a frame lets the app have what is left.
///   The page itself moves to `app.html`.
void _prepareEarlier(Directory dir, String base, String version, String bar) {
  final index = File('${dir.path}/index.html');
  if (!index.existsSync()) throw SiteError('The build has no index.html.');
  final html = _rebase(index.readAsStringSync(), base);
  if (!html.contains(_bootstrapTag)) {
    throw SiteError(
      'index.html no longer ends with the standard Flutter bootstrap tag, so '
      'the way back cannot be placed.',
    );
  }
  File('${dir.path}/app.html').writeAsStringSync(html);
  index.writeAsStringSync(
    html.replaceFirst(
      _bootstrapTag,
      bar
          .replaceAll('{{version}}', version)
          .replaceAll('{{marker}}', barMarker),
    ),
  );

  final worker = File('${dir.path}/flutter_service_worker.js');
  if (worker.existsSync()) worker.writeAsStringSync(selfRemovingWorker);
}

/// A service worker that installs, then unregisters itself. Never answers a
/// request, never reloads a page.
const selfRemovingWorker = '''
'use strict';

// Earlier versions are served from plain HTTP caching. See web_site.dart.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil(self.registration.unregister());
});
''';

String _rebase(String html, String base) {
  final tag = RegExp(r'<base href="[^"]*">');
  if (tag.allMatches(html).length != 1) {
    throw SiteError('index.html does not have exactly one <base href>.');
  }
  return html.replaceFirst(tag, '<base href="$base">');
}

String _readShim(String webDir) {
  final file = File('$webDir/index.html');
  if (!file.existsSync()) throw SiteError('Cannot find $webDir/index.html.');
  final source = file.readAsStringSync();
  final start = source.indexOf(shimStart);
  final end = source.indexOf(shimEnd);
  if (start < 0 || end < start) {
    throw SiteError(
      '$webDir/index.html has no pin script between its markers.',
    );
  }
  return source.substring(start, end + shimEnd.length);
}

/// Puts the pin script first in `<head>`, after the `<base>` the page needs it
/// to have, so it runs before anything is fetched or painted.
String _injectShim(String html, String shim) {
  final base = RegExp(r'<base href="[^"]*">').firstMatch(html)!;
  return html.replaceRange(base.end, base.end, '\n  $shim');
}

// --- Commands ---------------------------------------------------------------

/// The newest version older than [version] in [builds], or null.
String? previousOf(List<BuildInfo> builds, String version) => builds
    .map((b) => b.version)
    .where((v) => compareVersions(v, version) < 0)
    .firstOrNull;

/// `publish`: store the fresh build, decide what the root is, lay the site out.
String publish({
  required Directory build,
  required Directory store,
  required Directory out,
  required String base,
  required BuildInfo info,
  int keep = defaultKeep,
  bool liftHold = false,
  String webDir = 'web',
  String barFile = 'tool/rollback_bar.html',
}) {
  final report = StringBuffer();
  final pruned = updateStore(
    store: store,
    build: build,
    info: info,
    keep: keep,
  );
  final state = StoreState.read(store);

  var root = info.version;
  final hold = state.hold;
  if (hold != null) {
    final stored = storedBuilds(store).map((b) => b.version).toSet();
    if (liftHold) {
      state.hold = null;
      report.writeln('- The rollback hold was lifted by request.');
    } else if (compareVersions(info.version, hold.from) > 0) {
      state.hold = null;
      report.writeln(
        '- The rollback hold on ${hold.to} ended: ${info.version} is newer '
        'than ${hold.from}, the release it replaced.',
      );
    } else if (!stored.contains(hold.to)) {
      state.hold = null;
      report.writeln(
        '- The rollback hold ended because ${hold.to} is no longer stored.',
      );
    } else {
      root = hold.to;
      report.writeln(
        '- **Rollback in effect.** The site root stays on ${hold.to} (rolled '
        'back from ${hold.from} at ${hold.at}). It holds until a release '
        'newer than ${hold.from} is merged, or until this workflow is run '
        'by hand with "Lift the rollback hold" ticked. This push shipped '
        '${info.version}, which is not newer, so it is under /v/ only.',
      );
    }
  }
  state.root = root;
  state.write(store);

  final result = assembleSite(
    store: store,
    rootVersion: root,
    out: out,
    base: base,
    webDir: webDir,
    barFile: barFile,
  );
  return _summary(result, pruned, report.toString());
}

/// `rollback`: put a stored version at the root and hold it there.
String rollback({
  required Directory store,
  required Directory out,
  required String base,
  String? version,
  String webDir = 'web',
  String barFile = 'tool/rollback_bar.html',
}) {
  final state = StoreState.read(store);
  final builds = storedBuilds(store);
  final available = builds.map((b) => b.version).toList();
  final current = state.root;
  if (current == null || builds.isEmpty) {
    throw SiteError(
      'There is nothing to roll back: no release has been deployed through '
      'the build store yet. The first earlier version appears after the next '
      'release is merged.',
    );
  }

  final target = (version == null || version.trim().isEmpty)
      ? previousOf(builds, current)
      : version.trim();
  if (target == null) {
    throw SiteError(
      'No version older than $current is stored. Stored: '
      '${available.join(', ')}.',
    );
  }
  if (parseVersion(target) == null) {
    throw SiteError('"$target" is not a version like 0.37.0.');
  }
  if (!available.contains(target)) {
    throw SiteError(
      'Version $target is not in the build store, so it cannot be restored. '
      'Stored: ${available.join(', ')}.',
    );
  }
  if (target == current) {
    throw SiteError('$target is already the version at the site root.');
  }

  state.hold = Hold(
    from: state.hold?.from ?? current,
    to: target,
    at: DateTime.now().toUtc().toIso8601String(),
  );
  state.root = target;

  final result = assembleSite(
    store: store,
    rootVersion: target,
    out: out,
    base: base,
    webDir: webDir,
    barFile: barFile,
  );
  state.write(store);
  return _summary(
    result,
    const [],
    '- **Rolled back from $current to $target.** The root holds until a '
    'release newer than ${state.hold!.from} is merged. Pushes to main that '
    'do not raise the version leave it alone.\n',
  );
}

String _summary(SiteResult result, List<String> pruned, String notes) {
  final out = StringBuffer()
    ..writeln('### Web site layout')
    ..writeln()
    ..writeln('- Site root: **${result.root}**')
    ..writeln(
      '- Earlier versions under `v/`: '
      '${result.earlier.isEmpty ? 'none yet (the first appears after the next release)' : result.earlier.map((b) => b.version).join(', ')}',
    );
  if (pruned.isNotEmpty) {
    out.writeln('- Dropped from the store: ${pruned.join(', ')}');
  }
  for (final entry in result.skipped.entries) {
    out.writeln('- **Not offered:** ${entry.key}: ${entry.value}');
  }
  if (notes.isNotEmpty) out.write(notes);
  return out.toString();
}

// --- Plumbing ---------------------------------------------------------------

/// Copies [from] into [to], files and folders, creating [to].
void copyTree(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync(recursive: false, followLinks: false)) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (name == '.git') continue;
    if (entity is Directory) {
      copyTree(entity, Directory('${to.path}/$name'));
    } else if (entity is File) {
      entity.copySync('${to.path}/$name');
    }
  }
}

Map<String, String> _flags(List<String> args) {
  final flags = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) throw SiteError('Unexpected argument "$arg".');
    final next = i + 1 < args.length ? args[i + 1] : null;
    if (next == null || next.startsWith('--')) {
      flags[arg.substring(2)] = 'true';
    } else {
      flags[arg.substring(2)] = next;
      i++;
    }
  }
  return flags;
}

String _need(Map<String, String> flags, String name) =>
    flags[name] ?? (throw SiteError('Missing --$name.'));

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: web_site.dart build-info | publish | rollback');
    exitCode = 64;
    return;
  }
  try {
    final flags = _flags(args.skip(1).toList());
    switch (args.first) {
      case 'build-info':
        final info = readBuildInfo();
        final out = flags['out'];
        final json = '${jsonEncode(info.toJson())}\n';
        if (out == null) {
          stdout.write(json);
        } else {
          File(out).writeAsStringSync(json);
        }
      case 'publish':
        stdout.write(
          publish(
            build: Directory(_need(flags, 'build')),
            store: Directory(_need(flags, 'store')),
            out: Directory(_need(flags, 'out')),
            base: _need(flags, 'base'),
            info: readBuildInfo(),
            keep: int.tryParse(flags['keep'] ?? '') ?? defaultKeep,
            liftHold: flags['lift-hold'] == 'true',
          ),
        );
      case 'rollback':
        stdout.write(
          rollback(
            store: Directory(_need(flags, 'store')),
            out: Directory(_need(flags, 'out')),
            base: _need(flags, 'base'),
            version: flags['version'],
          ),
        );
      default:
        throw SiteError('Unknown command "${args.first}".');
    }
  } on SiteError catch (error) {
    stderr.writeln('error: $error');
    exitCode = 1;
  }
}
