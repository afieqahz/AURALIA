import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:auralia_app/core/services/app_ready_notifier.dart';
import 'package:auralia_app/core/services/connectivity_bus.dart';
import 'package:auralia_app/core/services/connectivity_watcher.dart';
import 'package:auralia_app/shared/widgets/connection_error_card.dart';

/// Wraps the whole app (via `MaterialApp.builder`) and shows a blurred,
/// blocking "Connection error" overlay — identical to the splash screen's —
/// the moment the device loses internet access anywhere past the splash
/// screen.
///
/// While the overlay is showing, the page underneath is blurred and cannot
/// be tapped, scrolled, or backed-out of. Nothing about the underlying
/// screen or navigation stack is touched, so once the user taps "Try again"
/// and the connection is confirmed, the overlay just disappears and they're
/// back exactly where they were (whatever page/state they had open).
class ConnectivityOverlay extends StatefulWidget {
  const ConnectivityOverlay({super.key, this.child});

  final Widget? child;

  @override
  State<ConnectivityOverlay> createState() => _ConnectivityOverlayState();
}

class _ConnectivityOverlayState extends State<ConnectivityOverlay>
    with WidgetsBindingObserver {
  bool _isOffline = false;
  bool _isRetrying = false;
  Timer? _pollTimer;

  // How often to silently re-check in the background while online.
  static const _pollInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppReadyNotifier.instance.addListener(_onAppReadyChanged);
    ConnectivityBus.instance.possibleDisconnect.addListener(_checkConnection);
    if (AppReadyNotifier.instance.value) {
      _startPolling();
    }
  }

  void _onAppReadyChanged() {
    if (AppReadyNotifier.instance.value) {
      _startPolling();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _checkConnection();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _checkConnection());
  }

  Future<void> _checkConnection() async {
    // Don't fight with a manual "Try again" tap that's already in flight,
    // and don't do anything until splash has handed off.
    if (!AppReadyNotifier.instance.value || _isRetrying) {
      return;
    }
    final hasInternet = await ConnectivityWatcher.hasInternetConnection();
    if (!mounted) return;
    final shouldBeOffline = !hasInternet;
    if (shouldBeOffline == _isOffline) {
      return;
    }
    final wasOffline = _isOffline;
    setState(() => _isOffline = shouldBeOffline);
    if (wasOffline && !shouldBeOffline) {
      ConnectivityBus.instance.notifyReconnected();
    }
  }

  Future<void> _retry() async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);
    final hasInternet = await ConnectivityWatcher.hasInternetConnection();
    if (!mounted) return;
    final wasOffline = _isOffline;
    setState(() {
      _isRetrying = false;
      _isOffline = !hasInternet;
    });
    if (wasOffline && hasInternet) {
      ConnectivityBus.instance.notifyReconnected();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check immediately when the user comes back to the app (e.g. after
    // flipping Wi-Fi/airplane mode from the notification shade).
    if (state == AppLifecycleState.resumed) {
      _checkConnection();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    AppReadyNotifier.instance.removeListener(_onAppReadyChanged);
    ConnectivityBus.instance.possibleDisconnect.removeListener(
      _checkConnection,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Blocks the Android back button while the barrier is up, so the
      // user can't navigate away from underneath it.
      canPop: !_isOffline,
      child: Stack(
        children: [
          if (widget.child != null) widget.child!,
          if (_isOffline)
            _OfflineBarrier(
              key: const ValueKey('offline-barrier'),
              isRetrying: _isRetrying,
              onRetry: _retry,
            ),
        ],
      ),
    );
  }
}

class _OfflineBarrier extends StatelessWidget {
  const _OfflineBarrier({
    super.key,
    required this.isRetrying,
    required this.onRetry,
  });

  final bool isRetrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    // This Positioned.fill is a direct child of the Stack built above,
    // which is required — Positioned only works as an immediate Stack
    // child, which is what caused the card not to show before.
    return Positioned.fill(
      child: Stack(
        children: [
          // Blurs and dims whatever page is currently underneath.
          //
          // Wrapped in its own RepaintBoundary so the BackdropFilter's
          // saveLayer stays isolated to this layer instead of bleeding into
          // the card's text below — on some GPUs, text sharing a
          // compositing pass with an active BackdropFilter blur renders
          // with a stray colored fringe under the glyphs.
          Positioned.fill(
            child: RepaintBoundary(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
          // Swallows every tap/scroll so nothing underneath is reachable.
          const Positioned.fill(
            child: AbsorbPointer(child: SizedBox.expand()),
          ),
          RepaintBoundary(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: ConnectionErrorCard(
                  isRetrying: isRetrying,
                  onRetry: onRetry,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
