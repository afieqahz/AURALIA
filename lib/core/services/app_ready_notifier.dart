import 'package:flutter/foundation.dart';

/// Tracks whether the splash-screen boot sequence has finished and the app
/// has navigated to its first real screen (Auth or MainLayout).
///
/// The global [ConnectivityOverlay] uses this so it only starts reacting to
/// connectivity changes once the app is actually "in" — the splash screen
/// already has its own dedicated offline UI while it boots, so we don't want
/// two overlays fighting each other during that phase.
class AppReadyNotifier extends ValueNotifier<bool> {
  AppReadyNotifier._() : super(false);

  static final AppReadyNotifier instance = AppReadyNotifier._();
}
