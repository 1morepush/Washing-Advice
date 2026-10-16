/// The real implementation: ask the page what it knows, and decide.
///
/// The measuring is done the only way CSS allows — by giving a hidden element
/// padding of `env(safe-area-inset-*)` and reading back what it computed to.
/// What to do with the numbers is `resolveScreenInsets`, which is tested.
///
/// Best-effort, like `paintBrowserChrome`: a page that will not let this look
/// is a page that gets no extra room, which is how it was before.
library;

import 'package:web/web.dart' as web;

import 'screen_insets_policy.dart';

ScreenInsets readScreenInsets() {
  try {
    final window = web.window;
    return resolveScreenInsets(
      measured: _measure(),
      installed: window.matchMedia('(display-mode: standalone)').matches,
      onIphone: window.navigator.userAgent.contains('iPhone'),
      portrait: window.innerHeight > window.innerWidth,
      screenWidth: window.screen.width.toDouble(),
      screenHeight: window.screen.height.toDouble(),
    );
  } catch (_) {
    return ScreenInsets.zero;
  }
}

ScreenInsets _measure() {
  final probe = web.document.createElement('div') as web.HTMLElement;
  probe.style.cssText =
      'position:fixed;left:0;top:0;width:0;height:0;visibility:hidden;'
      'pointer-events:none;'
      'padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) '
      'env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)';
  web.document.body!.appendChild(probe);
  try {
    final style = web.window.getComputedStyle(probe);
    return ScreenInsets(
      top: _px(style.paddingTop),
      right: _px(style.paddingRight),
      bottom: _px(style.paddingBottom),
      left: _px(style.paddingLeft),
    );
  } finally {
    probe.remove();
  }
}

double _px(String value) =>
    double.tryParse(value.replaceAll('px', '').trim()) ?? 0;
