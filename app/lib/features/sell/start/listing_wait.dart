/// The wait while the server reads a garment's photographs.
///
/// A free-tier server sleeps when it is idle, so the first request after a quiet
/// spell spends tens of seconds waking it before any reading starts. A spinner on
/// its own makes that look like a hang, and invites someone to kill the app
/// mid-request; after the same eight seconds the scan screens wait, this says what
/// is going on. The wording and the mechanism are the scan screens'.
///
/// Both ways of starting a listing that call the server wait here: photographs
/// just taken, and a garment from the wardrobe.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/api/ai_gateway.dart' show wakingAfter;

class ListingWait extends StatefulWidget {
  const ListingWait({required this.title, this.detail, super.key});

  final String title;

  /// Under the title: what is being read, and for what.
  final String? detail;

  @override
  State<ListingWait> createState() => _ListingWaitState();
}

class _ListingWaitState extends State<ListingWait> {
  bool _slow = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(wakingAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    // A request that comes back quickly disposes this while the timer is
    // pending; left running it would call setState on a State that is gone.
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quiet = theme.colorScheme.onSurfaceVariant;

    // Scrolls, because with a large text size on a small phone the title, the
    // detail and the sleeping-server line together are taller than the screen.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              widget.title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (widget.detail case final String detail) ...[
              const SizedBox(height: 8),
              Text(
                detail,
                style: theme.textTheme.bodyMedium?.copyWith(color: quiet),
                textAlign: TextAlign.center,
              ),
            ],
            if (_slow) ...[
              const SizedBox(height: 12),
              Text(
                'The server sleeps when it is not in use, so the first scan in '
                'a while takes longer while it wakes up.',
                style: theme.textTheme.bodyMedium?.copyWith(color: quiet),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
