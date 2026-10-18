/// What time it is, for the screens that say how long ago a listing went up.
///
/// A provider so that a test can fix it. Whether a listing has sat for fourteen
/// days is a question about the clock, and a test that built one "fourteen days
/// ago" from the real clock would be asking it a moment later, never at the
/// boundary it means to pin.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

final listingClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
