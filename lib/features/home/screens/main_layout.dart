import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:auralia_app/core/models/playlist.dart' show AuraliaTrack;
import 'package:auralia_app/core/services/auralia_state.dart';
import 'package:auralia_app/core/services/auralia_scope.dart';
import 'package:auralia_app/core/services/spotify_playback_service.dart';
import 'package:auralia_app/features/auth/screens/auth_screen.dart';
import 'package:auralia_app/features/mood_tracking/screens/home_dashboard_screen.dart';
import 'package:auralia_app/features/music_player/screens/music_player_screen.dart';
import 'package:auralia_app/features/mood_tracking/screens/analytics_screen.dart';
import 'package:auralia_app/features/profile/screens/profile_screen.dart';

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  final SpotifyPlaybackService _spotifyPlaybackService =
      SpotifyPlaybackService();
  int _currentIndex = 0;
  bool _showPlayer = false;
  bool _hasShownSpotifyPrompt = false;
  bool _isMiniPlayerBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showSpotifyConnectPrompt();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AuraliaScope.of(context);
    final screens = [
      HomeDashboardScreen(
        onOpenPlayer: () => setState(() => _showPlayer = true),
        onOpenProfile: () => setState(() {
          _showPlayer = false;
          _currentIndex = 2;
        }),
        onLogout: _confirmLogout,
      ),
      const AnalyticsScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF9F6FA),
      body: SafeArea(
        child: Stack(
          children: [
            Offstage(
              offstage: _showPlayer,
              child: TickerMode(
                enabled: !_showPlayer,
                child: IndexedStack(index: _currentIndex, children: screens),
              ),
            ),
            Offstage(
              offstage: !_showPlayer,
              child: TickerMode(
                enabled: _showPlayer,
                child: MusicPlayerScreen(
                  onBackHome: () => setState(() {
                    _showPlayer = false;
                    _currentIndex = 0;
                  }),
                ),
              ),
            ),
            if (!_showPlayer && state.hasActivePlayback)
              Positioned(
                left: 16,
                right: 16,
                bottom: 12,
                child: _MiniPlayerBar(
                  track: state.activeTrack,
                  isPlaying: state.isPlaybackPlaying,
                  isBusy: _isMiniPlayerBusy,
                  onTap: () {
                    state.openActivePlaybackPlaylist();
                    setState(() => _showPlayer = true);
                  },
                  onTogglePlayback: () => _toggleMiniPlayerPlayback(state),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A154B).withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            if (index == 1) {
              state.refreshMoodHistory().catchError((_) {});
            }
            setState(() {
              _showPlayer = false;
              _currentIndex = index;
            });
          },
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF5A2C62),
          unselectedItemColor: Colors.black26,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          selectedLabelStyle: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_filled, size: 26),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.insights_rounded, size: 26),
              label: 'Analytics',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_rounded, size: 26),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSpotifyConnectPrompt() async {
    if (_hasShownSpotifyPrompt ||
        _spotifyPlaybackService.isConnected ||
        !_spotifyPlaybackService.isConfigured) {
      return;
    }

    _hasShownSpotifyPrompt = true;
    final rootContext = context;

    await showDialog<void>(
      context: rootContext,
      builder: (dialogContext) {
        var isConnecting = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Connect Spotify',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF38143E),
                ),
              ),
              content: Text(
                'AURALIA uses Spotify Premium to play full tracks in the app.',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.black54,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isConnecting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    'Later',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF5A2C62),
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: isConnecting
                      ? null
                      : () async {
                          setDialogState(() => isConnecting = true);
                          final connected = await _spotifyPlaybackService
                              .connect();
                          if (!rootContext.mounted) {
                            return;
                          }
                          Navigator.of(dialogContext).pop();
                          ScaffoldMessenger.of(rootContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                connected
                                    ? 'Spotify connected.'
                                    : _spotifyPlaybackService.lastError ??
                                          'Open Spotify first, then try again.',
                              ),
                              backgroundColor: connected
                                  ? const Color(0xFF4A154B)
                                  : Colors.redAccent,
                            ),
                          );
                        },
                  icon: isConnecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.music_note_rounded),
                  label: Text(
                    isConnecting ? 'Connecting' : 'Connect',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF5A2C62),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _toggleMiniPlayerPlayback(AuraliaState state) async {
    if (_isMiniPlayerBusy || state.activeTrack == null) {
      return;
    }

    setState(() => _isMiniPlayerBusy = true);
    final shouldPause = state.isPlaybackPlaying;
    final success = shouldPause
        ? await _spotifyPlaybackService.pause()
        : await _spotifyPlaybackService.resume();

    if (!mounted) {
      return;
    }

    setState(() => _isMiniPlayerBusy = false);

    if (success) {
      state.updatePlaybackState(
        activeTrackIndex: state.activeTrackIndex,
        isPlaying: !shouldPause,
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _spotifyPlaybackService.lastError ??
              'Unable to control Spotify playback right now.',
        ),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Log out?',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: const Color(0xFF38143E),
          ),
        ),
        content: Text(
          'You will need to sign in again to access your saved mood history and playlists.',
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8C3343),
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (shouldLogout != true || !mounted) {
      return;
    }

    final state = AuraliaScope.of(context);
    await _spotifyPlaybackService.disconnect();
    await state.signOut();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }
}

class _MiniPlayerBar extends StatelessWidget {
  const _MiniPlayerBar({
    required this.track,
    required this.isPlaying,
    required this.isBusy,
    required this.onTap,
    required this.onTogglePlayback,
  });

  final AuraliaTrack? track;
  final bool isPlaying;
  final bool isBusy;
  final VoidCallback onTap;
  final VoidCallback onTogglePlayback;

  @override
  Widget build(BuildContext context) {
    final activeTrack = track;
    if (activeTrack == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF7B3677).withValues(alpha: 0.22),
                    Colors.white.withValues(alpha: 0.68),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFFB984B7).withValues(alpha: 0.42),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4A154B).withValues(alpha: 0.16),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 46,
                      height: 46,
                      child: activeTrack.imageUrl == null
                          ? Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFFAC7099),
                                    Color(0xFF5A2C62),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(
                                Icons.music_note_rounded,
                                color: Colors.white,
                              ),
                            )
                          : Image.network(
                              activeTrack.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: const Color(0xFF5A2C62),
                                child: const Icon(
                                  Icons.music_note_rounded,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          activeTrack.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF38143E),
                          ),
                        ),
                        Text(
                          activeTrack.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: const Color(0xFF6E5870),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: IconButton(
                      onPressed: isBusy ? null : onTogglePlayback,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF5A2C62),
                        disabledBackgroundColor: const Color(0xFFB894BA),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white,
                      ),
                      icon: isBusy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 24,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
