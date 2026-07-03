import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The "Connection error" card — pulled out of SplashScreen so it can be
/// reused by both the splash screen and the global [ConnectivityOverlay],
/// guaranteeing they always look identical.
class ConnectionErrorCard extends StatelessWidget {
  const ConnectionErrorCard({
    super.key,
    required this.isRetrying,
    required this.onRetry,
    this.title = 'Connection error',
    this.message =
        'AURALIA needs internet to sync your account, playlists, and Spotify tracks.',
  });

  final bool isRetrying;
  final VoidCallback onRetry;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.20),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.wifi_off_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              height: 1.45,
              color: Colors.white.withValues(alpha: 0.76),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: isRetrying ? null : onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.42),
                foregroundColor: const Color(0xFF4A154B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: isRetrying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF4A154B),
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(
                isRetrying ? 'Checking...' : 'Try again',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
