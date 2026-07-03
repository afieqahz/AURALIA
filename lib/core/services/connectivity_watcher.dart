import 'dart:io';

/// Small shared helper for checking real internet reachability.
///
/// A DNS lookup against the backend host is used instead of just checking
/// for a Wi-Fi/mobile-data connection, since a device can be "connected" to
/// a network with no actual internet access. This is the same check that
/// used to live directly inside SplashScreen — pulled out here so both the
/// splash screen and the global [ConnectivityOverlay] use one source of
/// truth.
class ConnectivityWatcher {
  const ConnectivityWatcher._();

  static const String _probeHost = 'supabase.co';

  static Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup(
        _probeHost,
      ).timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on Object {
      return false;
    }
  }
}
