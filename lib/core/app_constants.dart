// Backends are health-checked in order; the first that responds is used.
// - API_BASE_URL (via --dart-define) always wins when provided.
// - In debug builds we also try the local dev backend. 10.0.2.2 is the Android
//   emulator's alias for the host machine's localhost; for a physical test
//   device on the same network, pass your PC's LAN IP via --dart-define instead.
// - Release builds skip the local URL entirely (no startup delay for real users).
final apiBaseUrls = <String>[
  const String.fromEnvironment('API_BASE_URL'),
  // Works on a physical device via `adb reverse tcp:4000 tcp:4000`, and on the
  // emulator too. Tried before 10.0.2.2 (which is emulator-only).
  // Re-enabling these needs `import 'package:flutter/foundation.dart';` back.
  // if (kDebugMode) 'http://localhost:4000/api',
  // if (kDebugMode) 'http://10.0.2.2:4000/api',
  // Self-hosted VPS backend (docker-compose `backend` service, published on
  // port 4000). Plain HTTP against a bare IP, so Android needs
  // usesCleartextTraffic and iOS needs the ATS exception in Info.plist — both
  // are already in place. Swap this for https://<domain>/api once the VPS has a
  // domain + TLS, and the platform exceptions can then be dropped.
  'http://151.243.40.211:4000/api',
];
