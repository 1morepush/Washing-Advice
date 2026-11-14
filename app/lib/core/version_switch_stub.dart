/// Non-web builds have no published site beside them to move between.
library;

import 'version_switch_base.dart';

VersionSwitcher createVersionSwitcher() => const NoVersionSwitcher();

/// Nothing to record where there is no browser storage to record it in.
void recordDataFormat() {}
