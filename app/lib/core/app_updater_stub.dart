/// Non-web builds have no service worker or Cache Storage to clear.
library;

const canForceAppUpdate = false;

Future<void> forceAppUpdate() async {}
