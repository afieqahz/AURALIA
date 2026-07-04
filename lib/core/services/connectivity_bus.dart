import 'package:flutter/foundation.dart';

/// Tiny event bus connecting the network layer (AuraliaState) with the
/// global [ConnectivityOverlay] and any screen that needs to react to
/// connectivity changes — without them needing direct references to each
/// other.
class ConnectivityBus {
  ConnectivityBus._();

  static final ConnectivityBus instance = ConnectivityBus._();

  /// Bumped every time the app goes from offline back to online (whether
  /// detected automatically or via the overlay's "Try again" button).
  /// Screens with a pending action (like "regenerate this playlist") should
  /// listen here and retry once, silently, when this fires.
  final ValueNotifier<int> reconnected = ValueNotifier<int>(0);

  /// Bumped whenever something in the app (e.g. a failed API call) looks
  /// like it might be a connectivity problem, so the overlay can
  /// double-check immediately instead of waiting for its next poll.
  final ValueNotifier<int> possibleDisconnect = ValueNotifier<int>(0);

  void notifyReconnected() => reconnected.value++;

  void notifyPossibleDisconnect() => possibleDisconnect.value++;
}
