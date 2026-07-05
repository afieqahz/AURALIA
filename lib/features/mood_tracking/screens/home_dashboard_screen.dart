import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:auralia_app/core/models/playlist.dart';
import 'package:auralia_app/core/services/auralia_scope.dart';
import 'package:auralia_app/core/widgets/floating_bubbles.dart';
import 'package:auralia_app/features/mood_tracking/screens/auralia_chat_screen.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({
    super.key,
    this.onOpenPlayer,
    this.onOpenProfile,
    this.onLogout,
  });

  final VoidCallback? onOpenPlayer;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onLogout;

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  static const _playlistImages = [
    'https://images.unsplash.com/photo-1506157786151-b8491531f063?w=600&q=80',
    'https://images.unsplash.com/photo-1487180142328-054b783fc471?w=600&q=80',
    'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=600&q=80',
    'https://images.unsplash.com/photo-1511379938547-c1f69419868d?w=600&q=80',
  ];

  @override
  Widget build(BuildContext context) {
    final state = AuraliaScope.of(context);
    final favorites = state.favoritePlaylists;
    final activeTrack = state.activeTrack;
    final recommended = state.recommendedPlaylists.take(8).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 150),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                    Text(
                      state.currentUser?.name ?? 'Afiqah',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF38143E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              PopupMenuButton<_AvatarMenuAction>(
                tooltip: 'Account',
                color: Colors.white,
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                offset: const Offset(0, 52),
                onSelected: (action) {
                  switch (action) {
                    case _AvatarMenuAction.profile:
                      widget.onOpenProfile?.call();
                      break;
                    case _AvatarMenuAction.logout:
                      widget.onLogout?.call();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _AvatarMenuAction.profile,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.person_rounded,
                          color: Color(0xFF5A2C62),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Profile',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF38143E),
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: _AvatarMenuAction.logout,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.logout_rounded,
                          color: Color(0xFF8C3343),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Log out',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF8C3343),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFE2D1DF),
                  child: Text(
                    _initialFor(state.currentUser?.name),
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF5A2C62),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          _AuraliaHeroCard(
            onTap: _openAuraliaChat,
          ),
          const SizedBox(height: 18),
          _HomePulseStrip(
            savedCount: favorites.length,
            moodEntryCount: state.moodEntryCount,
          ),
          if (state.hasActivePlayback && activeTrack != null) ...[
            const SizedBox(height: 28),
            const _SectionHeader(title: 'Continue Listening'),
            const SizedBox(height: 14),
            _ContinueListeningCard(
              track: activeTrack,
              playlist: state.playbackPlaylist!,
              isPlaying: state.isPlaybackPlaying,
              onTap: () {
                state.openActivePlaybackPlaylist();
                widget.onOpenPlayer?.call();
              },
            ),
          ],
          const SizedBox(height: 30),
          _SectionHeader(
            title: 'Your Favourite',
            actionLabel: favorites.isEmpty ? null : '${favorites.length} saved',
          ),
          const SizedBox(height: 6),
          Text(
            favorites.isEmpty
                ? 'Save mixes you want to return to later.'
                : 'Your saved mood mixes, ready when you need them.',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.black45,
            ),
          ),
          const SizedBox(height: 15),
          if (favorites.isEmpty)
            _EmptyFavoritesCard(
              onCreate: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AuraliaChatScreen(onOpenPlayer: widget.onOpenPlayer),
                  ),
                );
              },
            )
          else
            SizedBox(
              height: 232,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: favorites.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final playlist = favorites[index];
                  final playlistImageUrl =
                      _firstPlaylistImage(playlist) ??
                      _playlistImages[index % _playlistImages.length];
                  return _FavoritePlaylistCard(
                    playlist: playlist,
                    imageUrl: playlistImageUrl,
                    onTap: () {
                      state.selectPlaylist(playlist);
                      widget.onOpenPlayer?.call();
                    },
                    onRemove: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final removed = await state.removePlaylistFromFavorites(
                        playlist,
                      );
                      if (!context.mounted) {
                        return;
                      }
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            removed
                                ? 'Removed from favourites.'
                                : state.errorMessage ??
                                      'Unable to remove playlist.',
                          ),
                          backgroundColor: removed
                              ? const Color(0xFF4A154B)
                              : Colors.redAccent,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          if (favorites.length == 1) ...[
            const SizedBox(height: 8),
            Text(
              'A nice start. Save more mixes to build your personal mood shelf.',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45),
            ),
          ],
          if (recommended.isNotEmpty) ...[
            const SizedBox(height: 30),
            const _SectionHeader(title: 'Recommended for you'),
            const SizedBox(height: 6),
            Text(
              'Fresh routes based on your recent mood activity.',
              style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 174,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recommended.length,
                separatorBuilder: (_, _) => const SizedBox(width: 13),
                itemBuilder: (context, index) {
                  final playlist = recommended[index];
                  final imageUrl =
                      _firstPlaylistImage(playlist) ??
                      _playlistImages[index % _playlistImages.length];
                  return _RecommendedPlaylistCard(
                    playlist: playlist,
                    imageUrl: imageUrl,
                    onTap: () {
                      state.selectPlaylist(playlist);
                      state.playCurrentPlaylist();
                      widget.onOpenPlayer?.call();
                    },
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openAuraliaChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AuraliaChatScreen(onOpenPlayer: widget.onOpenPlayer),
      ),
    );
  }

  String? _firstPlaylistImage(AuraliaPlaylist playlist) {
    for (final track in playlist.tracks) {
      final imageUrl = track.imageUrl;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        return imageUrl;
      }
    }
    return null;
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning';
    }
    if (hour < 18) {
      return 'Good afternoon';
    }
    return 'Good evening';
  }

  String _initialFor(String? name) {
    final trimmed = name?.trim() ?? '';
    return trimmed.isEmpty ? 'A' : trimmed.substring(0, 1).toUpperCase();
  }
}

enum _AvatarMenuAction { profile, logout }

class _AuraliaHeroCard extends StatefulWidget {
  const _AuraliaHeroCard({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AuraliaHeroCard> createState() => _AuraliaHeroCardState();
}

class _AuraliaHeroCardState extends State<_AuraliaHeroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: double.infinity,
        height: 190,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF230731), Color(0xFF5A1E66), Color(0xFF7B3677)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A154B).withValues(alpha: 0.24),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Stack(
          children: [
            const FloatingBubbles(count: 16, opacity: 0.16),
            Positioned(
              left: 22,
              top: 18,
              right: 118,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AURALIA',
                        style: GoogleFonts.poppins(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Your mood, shaped into music.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          height: 1.25,
                          color: Colors.white.withValues(alpha: 0.76),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _HeroMiniEqualizer(controller: _pulseController),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              right: 16,
              top: 20,
              child: SizedBox(
                width: 116,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final glow = 0.18 + (_pulseController.value * 0.16);
                        final scale = 1 + (_pulseController.value * 0.035);
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 92,
                            height: 92,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFF09EE6).withValues(
                                    alpha: glow,
                                  ),
                                  blurRadius: 24,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: child,
                          ),
                        );
                      },
                      child: Image.asset(
                        'assets/auralia_logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.spatial_audio_rounded,
                            size: 48,
                            color: Color(0xFFF09EE6),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Start',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 17,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroMiniEqualizer extends StatelessWidget {
  const _HeroMiniEqualizer({required this.controller});

  final Animation<double> controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return SizedBox(
          height: 30,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(8, (index) {
                final pulse = (controller.value + (index * 0.17)) % 1;
                final height = 8 + (pulse < 0.5 ? pulse : 1 - pulse) * 28;
                return Container(
                  width: 4,
                  height: height,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.36 + pulse * 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actionLabel});

  final String title;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
        if (actionLabel != null)
          Text(
            actionLabel!,
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45),
          ),
      ],
    );
  }
}

class _HomePulseStrip extends StatelessWidget {
  const _HomePulseStrip({
    required this.savedCount,
    required this.moodEntryCount,
  });

  final int savedCount;
  final int moodEntryCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PulseTile(
            icon: Icons.favorite_rounded,
            value: '$savedCount',
            label: 'Favourites',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PulseTile(
            icon: Icons.auto_graph_rounded,
            value: '$moodEntryCount',
            label: 'Mood logs',
          ),
        ),
      ],
    );
  }
}

class _PulseTile extends StatelessWidget {
  const _PulseTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEADFEA)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A154B).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF6E2D72), size: 18),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF38143E),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(fontSize: 9.5, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}

class _ContinueListeningCard extends StatelessWidget {
  const _ContinueListeningCard({
    required this.track,
    required this.playlist,
    required this.isPlaying,
    required this.onTap,
  });

  final AuraliaTrack track;
  final AuraliaPlaylist playlist;
  final bool isPlaying;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF7B3677).withValues(alpha: 0.20),
                  Colors.white.withValues(alpha: 0.70),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFB984B7).withValues(alpha: 0.42),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4A154B).withValues(alpha: 0.12),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                _ArtworkBox(imageUrl: track.imageUrl, size: 64, radius: 16),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: const Color(0xFF6E5870),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF38143E),
                        ),
                      ),
                      Text(
                        track.artist,
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
                const SizedBox(width: 10),
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF6E2D72),
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyFavoritesCard extends StatelessWidget {
  const _EmptyFavoritesCard({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFE2D1DF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.favorite_border_rounded,
              color: Color(0xFF5A2C62),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Saved playlists will appear here.',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.black54),
            ),
          ),
          TextButton(
            onPressed: onCreate,
            child: Text(
              'Create',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoritePlaylistCard extends StatelessWidget {
  const _FavoritePlaylistCard({
    required this.playlist,
    required this.imageUrl,
    required this.onTap,
    required this.onRemove,
  });

  final AuraliaPlaylist playlist;
  final String imageUrl;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 164,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _ArtworkFill(imageUrl: imageUrl),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.58),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: onRemove,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF5A2C62),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 11,
                    right: 11,
                    bottom: 10,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${playlist.tracks.length} tracks',
                            style: GoogleFonts.poppins(
                              fontSize: 9.5,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendedPlaylistCard extends StatelessWidget {
  const _RecommendedPlaylistCard({
    required this.playlist,
    required this.imageUrl,
    required this.onTap,
  });

  final AuraliaPlaylist playlist;
  final String imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 218,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF7B3677).withValues(alpha: 0.18),
                  Colors.white.withValues(alpha: 0.72),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFB984B7).withValues(alpha: 0.40),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4A154B).withValues(alpha: 0.12),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ArtworkBox(imageUrl: imageUrl, size: 56, radius: 14),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Suggested mix',
                            style: GoogleFonts.poppins(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF6E2D72),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            playlist.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF38143E),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: const BoxDecoration(
                        color: Color(0xFF5A2C62),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  playlist.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 10.5,
                    height: 1.3,
                    color: const Color(0xFF6E5870),
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: Color(0xFF5A2C62),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${playlist.tracks.length} tracks',
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF5A2C62),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Tap to play',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: const Color(0xFF8A718E),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArtworkBox extends StatelessWidget {
  const _ArtworkBox({
    required this.imageUrl,
    required this.size,
    this.radius = 20,
  });

  final String? imageUrl;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || url.isEmpty
            ? _ArtworkFallback(radius: radius)
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) =>
                    _ArtworkFallback(radius: radius),
              ),
      ),
    );
  }
}

class _ArtworkFill extends StatelessWidget {
  const _ArtworkFill({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: url == null || url.isEmpty
          ? const _ArtworkFallback(radius: 20)
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (ctx, err, stack) =>
                  const _ArtworkFallback(radius: 20),
            ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFC58BB9), Color(0xFF5A2C62)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 34),
    );
  }
}
