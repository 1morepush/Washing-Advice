/// The reminder's Android status-bar icon.
///
/// Three things that only work together and live in three places: the name
/// the code asks for, the drawable by that name, and the rule that stops a
/// release build stripping it. None of them fails loudly on its own — a
/// missing icon is a notification that silently never appears.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:washing_advice/data/notifications/local_nudges.dart';

void main() {
  const res = 'android/app/src/main/res';

  test('the icon the code names is a drawable that exists', () {
    final icon = File('$res/drawable/${LocalNudges.androidIcon}.xml');

    expect(icon.existsSync(), isTrue);
    // A silhouette: Android uses only the alpha channel, so anything but a
    // single white shape comes out as a square.
    expect(icon.readAsStringSync(), contains('#FFFFFFFF'));
  });

  test('and a release build is told to keep it', () {
    final keep = File('$res/raw/keep.xml').readAsStringSync();

    expect(keep, contains('@drawable/${LocalNudges.androidIcon}'));
  });

  test('it is not the launcher icon', () {
    expect(LocalNudges.androidIcon, isNot(contains('mipmap')));
  });
}
