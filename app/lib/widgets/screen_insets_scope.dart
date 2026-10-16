/// Tells everything below it how much of the screen's edge to keep clear.
///
/// Material's own widgets — the navigation bar, a `SafeArea`, a floating
/// button, a bottom sheet — already keep clear of whatever `MediaQuery` says
/// the phone has taken. On the web it says nothing, so one place says it for
/// them, and every one of those is right without being touched.
///
/// Only ever adds: where the platform has already reported more, that wins.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/screen_insets.dart';

class ScreenInsetsScope extends StatefulWidget {
  const ScreenInsetsScope({
    required this.child,
    this.read = readScreenInsets,
    super.key,
  });

  final Widget child;

  /// Where the insets come from; the page's own reading unless a test says.
  final ScreenInsets Function() read;

  @override
  State<ScreenInsetsScope> createState() => _ScreenInsetsScopeState();
}

class _ScreenInsetsScopeState extends State<ScreenInsetsScope>
    with WidgetsBindingObserver {
  late ScreenInsets _insets = widget.read();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(ScreenInsetsScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.read != widget.read) _insets = widget.read();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Turning the phone sideways changes both the insets and which rule applies.
  @override
  void didChangeMetrics() {
    final latest = widget.read();
    if (latest != _insets) setState(() => _insets = latest);
  }

  @override
  Widget build(BuildContext context) {
    if (_insets == ScreenInsets.zero) return widget.child;

    final media = MediaQuery.of(context);
    // The home indicator is under the keyboard while it is up; reserving room
    // for it there would leave a gap between the keys and what is typed.
    final keyboardUp = media.viewInsets.bottom > 0;

    EdgeInsets merge(EdgeInsets own) => EdgeInsets.fromLTRB(
      math.max(own.left, _insets.left),
      math.max(own.top, _insets.top),
      math.max(own.right, _insets.right),
      keyboardUp ? own.bottom : math.max(own.bottom, _insets.bottom),
    );

    return MediaQuery(
      data: media.copyWith(
        padding: merge(media.padding),
        viewPadding: merge(media.viewPadding),
      ),
      child: widget.child,
    );
  }
}
