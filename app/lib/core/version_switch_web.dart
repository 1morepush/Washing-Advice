/// The browser's half of moving between published versions.
///
/// Every version is served from the same origin, so they share one local
/// storage, one IndexedDB (or OPFS) and one Cache Storage: the wardrobe, the
/// pictures and the settings are the same whichever version is open. That is
/// what makes switching a matter of navigation, and also why [recordDataFormat]
/// exists: the data does not know which build wrote it.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'data_format.dart';
import 'version_switch_base.dart';

/// Where the site starts: the page's base without a trailing `v/<version>/`.
///
/// A build that is itself being served from `v/` (a later version, once there
/// is one) still finds the site's `versions.json` and root next to it.
Uri get _siteRoot {
  final base = Uri.parse(web.document.baseURI);
  final path = base.path.replaceFirst(RegExp(r'v/[^/]+/?(index\.html)?$'), '');
  return base.replace(path: path, query: '', fragment: '');
}

VersionSwitcher createVersionSwitcher() => const _WebVersionSwitcher();

/// Writes what this build lays data out as, keeping the larger of that and
/// what is already recorded, so the list of earlier versions can tell a build
/// the data has outgrown from one it has not.
///
/// Called before anything opens a database: the record may say a little more
/// than was written (an open that then failed), never less, and the list errs
/// towards offering fewer versions.
void recordDataFormat() {
  try {
    final stored = _readStored();
    final merged = stored == null
        ? currentDataFormat
        : currentDataFormat.mergedWith(stored);
    web.window.localStorage.setItem(dataFormatKey, jsonEncode(merged.toJson()));
  } catch (_) {
    // Storage can refuse a page outright. The list then falls back on this
    // build's own format as the floor, which is the cautious reading.
  }
}

DataFormat? _readStored() {
  try {
    final text = web.window.localStorage.getItem(dataFormatKey);
    return text == null ? null : DataFormat.fromJson(jsonDecode(text));
  } catch (_) {
    return null;
  }
}

final class _WebVersionSwitcher implements VersionSwitcher {
  const _WebVersionSwitcher();

  @override
  bool get available => true;

  @override
  Future<SiteVersions> fetchVersions() async {
    // A timestamp on the address and not a header: a browser cache or a CDN
    // that holds an old copy would list versions that have since been
    // dropped, and a pin to one lands on the page that says it is gone.
    final url = _siteRoot
        .resolve('versions.json')
        .replace(
          queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'},
        );
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw http.ClientException('versions.json: ${response.statusCode}', url);
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, Object?>) {
      throw const FormatException('versions.json is not an object.');
    }
    return SiteVersions.parse(json);
  }

  @override
  DataFormat? get storedFormat => _readStored();

  @override
  Future<void> switchTo(String version) async {
    web.window.localStorage.setItem(pinnedVersionKey, version);
    web.window.location.assign(_siteRoot.resolve('v/$version/').toString());
  }
}
