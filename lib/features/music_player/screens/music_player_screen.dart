import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:auralia_app/core/config/app_config.dart';
import 'package:auralia_app/core/models/mood.dart';
import 'package:auralia_app/core/models/playlist.dart';
import 'package:auralia_app/core/services/auralia_state.dart';
import 'package:auralia_app/core/services/auralia_scope.dart';
import 'package:auralia_app/core/services/spotify_playback_service.dart';

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key, this.onBackHome});

  final VoidCallback? onBackHome;

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final SpotifyPlaybackService _spotifyPlaybackService =
      SpotifyPlaybackService();
  late final AnimationController _waveformController;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<SpotifyPlaybackSnapshot>? _spotifyStateSubscription;
  Timer? _spotifyProgressTimer;
  int _activeTrackIndex = 0;
  int _lastPlaybackRequestId = 0;
  int _lastPlaylistSelectionId = -1;
  bool _isViewingPlayback = false;
  bool _isPlaying = false;
  bool _isSpotifyPlayback = false;
  bool _isConnectingSpotify = false;
  String? _loadedPreviewUrl;
  String? _playbackMessage;
  final Set<String> _artworkLookupInFlight = {};
  Duration _spotifyPosition = Duration.zero;
  Duration _spotifyDuration = Duration.zero;
  String? _expectedSpotifyUri;
  bool _isAdvancingTrack = false;
  bool _hasSpotifyStateForTrack = false;
  bool _isShowingPostListeningCheckIn = false;
  bool _hasCompletedPlaylist = false;
  int _completedPlaybackRequestId = -1;

  bool get _shouldShowPlaybackMessage =>
      _playbackMessage != null && _playbackMessage!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _waveformController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _playerStateSubscription = _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) {
        return;
      }
      if (_isViewingPlayback && !_isSpotifyPlayback) {
        setState(() => _isPlaying = state.playing);
      }
      if (_isViewingPlayback &&
          state.processingState == ProcessingState.completed) {
        _playNext(fromCompletion: true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AuraliaScope.of(context);
    final playbackRequestId = state.playbackRequestId;
    final playlistSelectionId = state.playlistSelectionId;
    if (playlistSelectionId != _lastPlaylistSelectionId) {
      _lastPlaylistSelectionId = playlistSelectionId;
      _isViewingPlayback = state.isViewingPlaybackPlaylist;
      _activeTrackIndex = _isViewingPlayback ? state.activeTrackIndex : 0;
      _stopSpotifyTimer();
      _spotifyPosition = Duration.zero;
      _spotifyDuration = state.currentPlaylist.tracks.isEmpty
          ? Duration.zero
          : _durationForTrack(state.currentPlaylist.tracks.first);
      _isConnectingSpotify = false;
      _playbackMessage = null;
      _hasSpotifyStateForTrack = false;
      _hasCompletedPlaylist = false;
      if (_isViewingPlayback) {
        _isPlaying = state.isPlaybackPlaying;
        _isSpotifyPlayback =
            _spotifyPlaybackService.isConnected && _loadedPreviewUrl == null;
        if (_isSpotifyPlayback) {
          _subscribeToSpotifyState();
          _startSpotifyTimer();
        }
      } else {
        _isPlaying = false;
        _isSpotifyPlayback = false;
      }
    }
    if (_lastPlaybackRequestId == 0) {
      _activeTrackIndex = state.activeTrackIndex;
    }
    if (playbackRequestId != _lastPlaybackRequestId) {
      _lastPlaybackRequestId = playbackRequestId;
      if (!state.hasActivePlayback) {
        return;
      }
      _completedPlaybackRequestId = -1;
      _hasCompletedPlaylist = false;
      _activeTrackIndex = 0;
      _isViewingPlayback = true;
      _playActiveTrack();
    }
  }

  @override
  void dispose() {
    _waveformController.dispose();
    _spotifyProgressTimer?.cancel();
    _playerStateSubscription?.cancel();
    _spotifyStateSubscription?.cancel();
    _audioPlayer.dispose();
    _spotifyPlaybackService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AuraliaScope.of(context);
    final playlist = state.currentPlaylist;
    final activeTrack =
        playlist.tracks[_activeTrackIndex.clamp(0, playlist.tracks.length - 1)];
    final artworkUrl = activeTrack.imageUrl ?? _firstPlaylistArtwork(playlist);
    if (activeTrack.imageUrl == null || activeTrack.durationMs == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _ensureTrackDetails(activeTrack);
        }
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: widget.onBackHome,
                icon: const Icon(Icons.chevron_left_rounded, size: 30),
              ),
              Text(
                'Player',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF38143E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(child: _PlaylistNameLabel(name: playlist.name)),
              const SizedBox(width: 8),
              _SavePlaylistIconButton(
                isSaved: state.isCurrentPlaylistLiked,
                isBusy: state.isBusy,
                onPressed: () => _toggleSavePlaylist(state),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _NowPlayingArtworkCard(
            artworkUrl: artworkUrl,
            isPlaying: _isPlaying,
            controller: _waveformController,
          ),
          const SizedBox(height: 28),
          Text(
            activeTrack.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF38143E),
            ),
          ),
          Text(
            activeTrack.artist,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.black45),
          ),
          const SizedBox(height: 12),
          _PlaybackMoodPill(
            isPlaying: _isPlaying,
            isConnecting: _isConnectingSpotify,
            isSpotifyPlayback: _isSpotifyPlayback,
          ),
          if (_shouldShowPlaybackMessage) ...[
            const SizedBox(height: 12),
            _PlaybackFallbackPanel(
              message: _playbackMessage!,
              hasPreview: activeTrack.previewUrl?.isNotEmpty ?? false,
              hasSpotifyLink: _spotifyUrlForTrack(activeTrack) != null,
              onPlayPreview: _isConnectingSpotify
                  ? null
                  : () => _playPreviewFallback(activeTrack),
              onOpenSpotify: () => _openInSpotify(activeTrack),
            ),
          ],
          const SizedBox(height: 18),
          _PlayerWaveform(
            controller: _waveformController,
            isPlaying: _isPlaying,
          ),
          const SizedBox(height: 16),
          if (_isSpotifyPlayback)
            _SpotifyProgressBar(
              position: _spotifyPosition,
              duration: _spotifyDuration,
              onSeek: _seekSpotifyPlayback,
            )
          else
            _PreviewProgressBar(audioPlayer: _audioPlayer),
          const SizedBox(height: 8),
          _PlayerControlDeck(
            isPlaying: _isPlaying,
            isConnecting: _isConnectingSpotify,
            onPrevious: _playPrevious,
            onToggle: _isConnectingSpotify
                ? null
                : () => _togglePlayback(activeTrack),
            onNext: _playNext,
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Playlist Sequence',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...playlist.tracks.asMap().entries.map(
            (entry) => _TrackTile(
              track: entry.value,
              isActive: entry.key == _activeTrackIndex,
              onTap: () {
                setState(() => _activeTrackIndex = entry.key);
                _playActiveTrack();
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePlayback(AuraliaTrack track) async {
    if (_isPlaying) {
      if (_isSpotifyPlayback) {
        await _spotifyPlaybackService.pause();
        _stopSpotifyTimer();
      } else {
        await _audioPlayer.pause();
      }
      if (mounted) {
        setState(() => _isPlaying = false);
        AuraliaScope.of(context).updatePlaybackState(
          activeTrackIndex: _activeTrackIndex,
          isPlaying: false,
        );
      }
      return;
    }

    if (_hasCompletedPlaylist) {
      await _restartCompletedPlaylist();
      return;
    }

    if (_isSpotifyPlayback) {
      final resumed = await _spotifyPlaybackService.resume();
      if (resumed) {
        _startSpotifyTimer();
        if (mounted) {
          setState(() => _isPlaying = true);
          AuraliaScope.of(context).updatePlaybackState(
            activeTrackIndex: _activeTrackIndex,
            isPlaying: true,
          );
        }
        return;
      }
    }

    if (_loadedPreviewUrl == track.previewUrl && track.previewUrl != null) {
      await _audioPlayer.play();
      if (mounted) {
        AuraliaScope.of(context).updatePlaybackState(
          activeTrackIndex: _activeTrackIndex,
          isPlaying: true,
        );
      }
      return;
    }

    await _playActiveTrack();
  }

  Future<void> _toggleSavePlaylist(AuraliaState state) async {
    if (state.isBusy) {
      return;
    }

    final wasSaved = state.isCurrentPlaylistLiked;
    final saved = wasSaved
        ? await state.toggleCurrentPlaylistFavorite()
        : await state.saveCurrentPlaylist();
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? wasSaved
                    ? 'Removed from favourites.'
                    : 'Playlist saved.'
              : state.errorMessage ?? 'Unable to save playlist.',
        ),
        backgroundColor: saved ? const Color(0xFF4A154B) : Colors.redAccent,
      ),
    );
  }

  String? _firstPlaylistArtwork(AuraliaPlaylist playlist) {
    for (final track in playlist.tracks) {
      final imageUrl = track.imageUrl;
      if (imageUrl != null && imageUrl.isNotEmpty) {
        return imageUrl;
      }
    }
    return null;
  }

  Future<AuraliaTrack> _ensureTrackDetails(
    AuraliaTrack track, {
    bool force = false,
  }) async {
    final trackId = track.id;
    if (trackId == null ||
        trackId.isEmpty ||
        trackId.startsWith('fallback-') ||
        AppConfig.spotifyBackendUrl.isEmpty ||
        (!force && _artworkLookupInFlight.contains(trackId))) {
      return track;
    }

    _artworkLookupInFlight.add(trackId);
    try {
      final baseUri = Uri.parse(AppConfig.spotifyBackendUrl);
      final tracksPath = [
        baseUri.path.replaceAll(RegExp(r'/+$'), ''),
        'spotify',
        'tracks',
      ].where((part) => part.isNotEmpty).join('/');
      final response = await http
          .get(
            baseUri.replace(
              path: '/$tracksPath',
              queryParameters: {'ids': trackId},
            ),
          )
          .timeout(const Duration(seconds: 6));

      if (response.statusCode < 200 || response.statusCode >= 300 || !mounted) {
        return track;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final tracks = body['tracks'] as List<dynamic>? ?? [];
      Map<String, dynamic>? spotifyTrack;
      for (final item in tracks.whereType<Map<String, dynamic>>()) {
        spotifyTrack = item;
        break;
      }
      if (spotifyTrack == null) {
        return track;
      }

      final album = spotifyTrack['album'] as Map<String, dynamic>?;
      final images = album?['images'] as List<dynamic>? ?? [];
      final image = images.isEmpty ? null : images.first as Map<String, dynamic>;
      final externalUrls = spotifyTrack['external_urls'] as Map<String, dynamic>?;
      final durationMs = _toInt(spotifyTrack['duration_ms']);
      final enrichedTrack = AuraliaTrack(
        id: track.id,
        title: track.title,
        artist: track.artist,
        stage: track.stage,
        valence: track.valence,
        energy: track.energy,
        previewUrl: spotifyTrack['preview_url']?.toString() ?? track.previewUrl,
        imageUrl: image?['url']?.toString() ?? track.imageUrl,
        externalUrl: externalUrls?['spotify']?.toString() ?? track.externalUrl,
        durationMs: durationMs ?? track.durationMs,
      );

      AuraliaScope.of(context).updateCurrentTrackDetails(
        trackId: trackId,
        imageUrl: enrichedTrack.imageUrl,
        previewUrl: enrichedTrack.previewUrl,
        externalUrl: enrichedTrack.externalUrl,
        durationMs: enrichedTrack.durationMs,
      );
      if (durationMs != null && mounted) {
        setState(() {
          _spotifyDuration = Duration(milliseconds: durationMs);
          if (_spotifyPosition > _spotifyDuration) {
            _spotifyPosition = _spotifyDuration;
          }
        });
      }
      return enrichedTrack;
    } catch (_) {
      // Keep the gradient fallback if Spotify details are unavailable.
      return track;
    } finally {
      _artworkLookupInFlight.remove(trackId);
    }
  }

  Future<void> _playActiveTrack() async {
    final state = AuraliaScope.of(context);
    final playlist = state.currentPlaylist;
    if (playlist.tracks.isEmpty) {
      return;
    }
    _hasCompletedPlaylist = false;
    state.activateCurrentPlaylistForPlayback(
      activeTrackIndex: _activeTrackIndex,
    );
    _isViewingPlayback = true;
    var track =
        playlist.tracks[_activeTrackIndex.clamp(0, playlist.tracks.length - 1)];

    if (track.durationMs == null || track.imageUrl == null) {
      unawaited(_ensureTrackDetails(track, force: true));
    }

    setState(() {
      _isConnectingSpotify = true;
      _playbackMessage = _spotifyPlaybackService.isConnected
          ? null
          : 'Connecting Spotify...';
      _spotifyDuration = _durationForTrack(track);
      _spotifyPosition = Duration.zero;
      _hasSpotifyStateForTrack = false;
    });

    _expectedSpotifyUri = _spotifyPlaybackService.spotifyUriForTrack(track);
    final didStartSpotify = await _spotifyPlaybackService.playTrack(track);
    if (didStartSpotify) {
      await _audioPlayer.stop();
      if (mounted) {
        setState(() {
          _isConnectingSpotify = false;
          _isSpotifyPlayback = true;
          _isPlaying = true;
          _loadedPreviewUrl = null;
          _playbackMessage = null;
        });
        AuraliaScope.of(context).updatePlaybackState(
          activeTrackIndex: _activeTrackIndex,
          isPlaying: true,
        );
        _subscribeToSpotifyState();
        _startSpotifyTimer(reset: true);
      }
      return;
    }

    if (mounted) {
      setState(() => _isConnectingSpotify = false);
    }
    await _playPreviewFallback(track);
  }

  Future<void> _playPreviewFallback(AuraliaTrack track) async {
    final previewUrl = track.previewUrl;
    _stopSpotifyTimer();

    if (previewUrl == null || previewUrl.isEmpty) {
      await _audioPlayer.stop();
      if (mounted) {
        setState(() {
          _isSpotifyPlayback = false;
          _isPlaying = false;
          _loadedPreviewUrl = null;
          _playbackMessage =
              _nonPremiumFallbackMessage(hasPreview: false);
        });
        AuraliaScope.of(context).updatePlaybackState(
          activeTrackIndex: _activeTrackIndex,
          isPlaying: false,
        );
      }
      return;
    }

    try {
      await _audioPlayer.setUrl(previewUrl);
      _loadedPreviewUrl = previewUrl;
      if (mounted) {
        setState(() {
          _isSpotifyPlayback = false;
          _playbackMessage = _nonPremiumFallbackMessage(hasPreview: true);
        });
        AuraliaScope.of(context).updatePlaybackState(
          activeTrackIndex: _activeTrackIndex,
          isPlaying: true,
        );
      }
      await _audioPlayer.play();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSpotifyPlayback = false;
          _isPlaying = false;
          _loadedPreviewUrl = null;
          _playbackMessage =
              _nonPremiumFallbackMessage(hasPreview: false);
        });
        AuraliaScope.of(context).updatePlaybackState(
          activeTrackIndex: _activeTrackIndex,
          isPlaying: false,
        );
      }
    }
  }

  String _nonPremiumFallbackMessage({required bool hasPreview}) {
    final spotifyError = _spotifyPlaybackService.lastError ?? '';
    if (spotifyError.toLowerCase().contains('premium')) {
      return hasPreview
          ? 'Full playback needs Spotify Premium. Playing a preview instead.'
          : 'Full playback needs Spotify Premium. You can still save this playlist or open the song in Spotify.';
    }

    return hasPreview
        ? 'Spotify full playback is not available right now. Playing a preview instead.'
        : spotifyError.isNotEmpty
            ? spotifyError
            : 'Spotify full playback is not available right now.';
  }

  String? _spotifyUrlForTrack(AuraliaTrack track) {
    if (track.externalUrl != null && track.externalUrl!.isNotEmpty) {
      return track.externalUrl;
    }
    final id = track.id;
    if (id == null || id.isEmpty || id.startsWith('fallback-')) {
      return null;
    }
    return 'https://open.spotify.com/track/$id';
  }

  Future<void> _openInSpotify(AuraliaTrack track) async {
    final url = _spotifyUrlForTrack(track);
    if (url == null) {
      return;
    }

    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _seekSpotifyPlayback(Duration position) async {
    await _spotifyPlaybackService.seek(position);
    if (mounted) {
      setState(() => _spotifyPosition = position);
    }
  }

  void _subscribeToSpotifyState() {
    _spotifyStateSubscription?.cancel();
    _spotifyStateSubscription = _spotifyPlaybackService.playerStateStream.listen(
      _handleSpotifyState,
      onError: (Object error) {
        debugPrint('Spotify player-state stream failed: $error');
      },
    );
  }

  void _handleSpotifyState(SpotifyPlaybackSnapshot snapshot) {
    if (!mounted || !_isSpotifyPlayback) {
      return;
    }

    final currentUri = snapshot.trackUri;
    final expectedUri = _expectedSpotifyUri;
    if (expectedUri != null &&
        currentUri != null &&
        currentUri != expectedUri) {
      if (_hasSpotifyStateForTrack &&
          !_isConnectingSpotify &&
          !_isAdvancingTrack) {
        _playNext(fromCompletion: true);
      }
      return;
    }

    final duration = snapshot.duration.inMilliseconds > 0
        ? snapshot.duration
        : _spotifyDuration;
    final position = duration.inMilliseconds > 0 &&
            snapshot.position > duration
        ? duration
        : snapshot.position;

    setState(() {
      _spotifyPosition = position;
      _spotifyDuration = duration;
      _isPlaying = !snapshot.isPaused;
      _hasSpotifyStateForTrack = true;
    });

    final track = AuraliaScope.of(context).activeTrack;
    final trackId = track?.id;
    if (trackId != null &&
        duration.inMilliseconds > 0 &&
        track?.durationMs != duration.inMilliseconds) {
      AuraliaScope.of(context).updateCurrentTrackDetails(
        trackId: trackId,
        durationMs: duration.inMilliseconds,
      );
    }

    AuraliaScope.of(context).updatePlaybackState(
      activeTrackIndex: _activeTrackIndex,
      isPlaying: !snapshot.isPaused,
    );

    final remaining = duration - position;
    if (!snapshot.isPaused &&
        duration.inMilliseconds > 0 &&
        position.inMilliseconds > 0 &&
        remaining <= const Duration(milliseconds: 900)) {
      _playNext(fromCompletion: true);
    }
  }

  void _startSpotifyTimer({bool reset = false}) {
    _spotifyProgressTimer?.cancel();
    if (reset) {
      _spotifyPosition = Duration.zero;
    }
    _spotifyProgressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_isPlaying || !_isSpotifyPlayback) {
        return;
      }
      if (_spotifyDuration.inMilliseconds <= 0) {
        return;
      }
      final next = _spotifyPosition + const Duration(seconds: 1);
      final switchAt = _spotifyDuration - const Duration(milliseconds: 500);
      if (_hasSpotifyStateForTrack && next >= switchAt) {
        setState(() => _spotifyPosition = _spotifyDuration);
        _stopSpotifyTimer();
        _playNext(fromCompletion: true);
        return;
      }
      setState(() => _spotifyPosition = next);
    });
  }

  Duration _durationForTrack(AuraliaTrack track) {
    final duration = track.duration;
    if (duration != null && duration.inMilliseconds > 0) {
      return duration;
    }
    return Duration.zero;
  }

  int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  void _stopSpotifyTimer() {
    _spotifyProgressTimer?.cancel();
    _spotifyProgressTimer = null;
  }

  Future<void> _playPrevious() async {
    if (_isAdvancingTrack) {
      return;
    }
    _isAdvancingTrack = true;
    final playlist = AuraliaScope.of(context).currentPlaylist;
    if (playlist.tracks.isEmpty) {
      _isAdvancingTrack = false;
      return;
    }
    try {
      setState(() {
        _activeTrackIndex =
            (_activeTrackIndex - 1 + playlist.tracks.length) %
            playlist.tracks.length;
      });
      await _playActiveTrack();
    } finally {
      _isAdvancingTrack = false;
    }
  }

  Future<void> _playNext({bool fromCompletion = false}) async {
    if (_isAdvancingTrack) {
      return;
    }
    _isAdvancingTrack = true;
    final playlist = AuraliaScope.of(context).currentPlaylist;
    if (playlist.tracks.isEmpty) {
      _isAdvancingTrack = false;
      return;
    }
    if (fromCompletion &&
        _activeTrackIndex >= playlist.tracks.length - 1) {
      _isAdvancingTrack = false;
      await _finishPlaylistAndRequestCheckIn();
      return;
    }
    try {
      setState(() {
        _activeTrackIndex = (_activeTrackIndex + 1) % playlist.tracks.length;
      });
      await _playActiveTrack();
    } finally {
      _isAdvancingTrack = false;
    }
  }

  Future<void> _restartCompletedPlaylist() async {
    _stopSpotifyTimer();
    await _audioPlayer.stop();
    if (_isSpotifyPlayback) {
      await _spotifyPlaybackService.pause();
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _hasCompletedPlaylist = false;
      _completedPlaybackRequestId = -1;
      _activeTrackIndex = 0;
      _spotifyPosition = Duration.zero;
      _hasSpotifyStateForTrack = false;
      _expectedSpotifyUri = null;
      _loadedPreviewUrl = null;
    });
    await _playActiveTrack();
  }

  Future<void> _finishPlaylistAndRequestCheckIn() async {
    final state = AuraliaScope.of(context);
    final requestId = state.playbackRequestId;
    if (_isShowingPostListeningCheckIn ||
        _completedPlaybackRequestId == requestId) {
      return;
    }

    _completedPlaybackRequestId = requestId;
    _isShowingPostListeningCheckIn = true;
    _stopSpotifyTimer();
    if (_isSpotifyPlayback) {
      await _spotifyPlaybackService.pause();
    } else {
      await _audioPlayer.stop();
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _isPlaying = false;
      _hasCompletedPlaylist = true;
      _spotifyPosition = _spotifyDuration;
    });
    state.updatePlaybackState(
      activeTrackIndex: _activeTrackIndex,
      isPlaying: false,
    );

    final result = await showModalBottomSheet<_PostListeningResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (sheetContext) => const _PostListeningCheckInSheet(),
    );

    if (!mounted) {
      return;
    }
    _isShowingPostListeningCheckIn = false;
    if (result == null) {
      return;
    }

    final saved = await state.recordPostListeningCheckIn(
      mood: result.mood,
      helpfulness: result.helpfulness,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Thank you. Your post-listening mood was recorded.'
              : state.errorMessage ?? 'Unable to save your check-in.',
        ),
        backgroundColor: saved
            ? const Color(0xFF4A154B)
            : Colors.redAccent,
      ),
    );
  }
}

class _PostListeningResult {
  const _PostListeningResult({
    required this.mood,
    required this.helpfulness,
  });

  final AuraliaMood mood;
  final ListeningHelpfulness helpfulness;
}

class _PostListeningCheckInSheet extends StatefulWidget {
  const _PostListeningCheckInSheet();

  @override
  State<_PostListeningCheckInSheet> createState() =>
      _PostListeningCheckInSheetState();
}

class _PostListeningCheckInSheetState
    extends State<_PostListeningCheckInSheet> {
  AuraliaMood? _mood;
  ListeningHelpfulness? _helpfulness;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(22, 12, 22, 22 + bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xFFF9F6FA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'How do you feel now?',
              style: GoogleFonts.poppins(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF38143E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Your answer helps AURALIA understand how the playlist supported your mood.',
              style: GoogleFonts.poppins(
                fontSize: 12,
                height: 1.4,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: AuraliaMood.values
                  .map(
                    (mood) => ChoiceChip(
                      label: Text(mood.label),
                      avatar: Icon(
                        _moodIcon(mood),
                        size: 17,
                        color: _mood == mood
                            ? Colors.white
                            : const Color(0xFF5A2C62),
                      ),
                      selected: _mood == mood,
                      showCheckmark: false,
                      selectedColor: const Color(0xFF5A2C62),
                      backgroundColor: Colors.white,
                      labelStyle: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _mood == mood
                            ? Colors.white
                            : const Color(0xFF38143E),
                      ),
                      side: const BorderSide(color: Color(0xFFE0D5E2)),
                      onSelected: (_) => setState(() => _mood = mood),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 22),
            Text(
              'Did this playlist help?',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF38143E),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _HelpfulnessButton(
                  label: 'Yes',
                  selected: _helpfulness == ListeningHelpfulness.yes,
                  onTap: () => setState(
                    () => _helpfulness = ListeningHelpfulness.yes,
                  ),
                ),
                const SizedBox(width: 8),
                _HelpfulnessButton(
                  label: 'A little',
                  selected: _helpfulness == ListeningHelpfulness.aLittle,
                  onTap: () => setState(
                    () => _helpfulness = ListeningHelpfulness.aLittle,
                  ),
                ),
                const SizedBox(width: 8),
                _HelpfulnessButton(
                  label: 'No',
                  selected: _helpfulness == ListeningHelpfulness.no,
                  onTap: () => setState(
                    () => _helpfulness = ListeningHelpfulness.no,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _mood == null || _helpfulness == null
                    ? null
                    : () => Navigator.of(context).pop(
                        _PostListeningResult(
                          mood: _mood!,
                          helpfulness: _helpfulness!,
                        ),
                      ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF5A2C62),
                  disabledBackgroundColor: const Color(0xFFD8CDD9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Save check-in',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Not now',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.black45,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _moodIcon(AuraliaMood mood) {
    switch (mood) {
      case AuraliaMood.sad:
        return Icons.water_drop_rounded;
      case AuraliaMood.stressed:
        return Icons.bolt_rounded;
      case AuraliaMood.neutral:
        return Icons.remove_circle_outline_rounded;
      case AuraliaMood.happy:
        return Icons.wb_sunny_outlined;
      case AuraliaMood.motivated:
        return Icons.rocket_launch_rounded;
    }
  }
}

class _HelpfulnessButton extends StatelessWidget {
  const _HelpfulnessButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFE8D8EA) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF5A2C62)
                  : const Color(0xFFE0D5E2),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF38143E),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaybackFallbackPanel extends StatelessWidget {
  const _PlaybackFallbackPanel({
    required this.message,
    required this.hasPreview,
    required this.hasSpotifyLink,
    required this.onPlayPreview,
    required this.onOpenSpotify,
  });

  final String message;
  final bool hasPreview;
  final bool hasSpotifyLink;
  final VoidCallback? onPlayPreview;
  final VoidCallback onOpenSpotify;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF6ECF5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6D5E4)),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: const Color(0xFF5A2C62),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasPreview || hasSpotifyLink) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                if (hasPreview)
                  OutlinedButton.icon(
                    onPressed: onPlayPreview,
                    icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                    label: Text(
                      'Play Preview',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                  ),
                if (hasSpotifyLink)
                  FilledButton.icon(
                    onPressed: onOpenSpotify,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF5A2C62),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(
                      'Open in Spotify',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PlaylistNameLabel extends StatelessWidget {
  const _PlaylistNameLabel({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 292),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE8D8EA)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A154B).withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.queue_music_rounded,
            size: 15,
            color: Color(0xFF6E2D72),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF4A154B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavePlaylistIconButton extends StatelessWidget {
  const _SavePlaylistIconButton({
    required this.isSaved,
    required this.isBusy,
    required this.onPressed,
  });

  final bool isSaved;
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isSaved ? 'Saved' : 'Save playlist',
      child: SizedBox(
        width: 38,
        height: 38,
        child: IconButton(
          onPressed: isBusy ? null : onPressed,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.9),
            disabledBackgroundColor: const Color(0xFFF0E5F0),
            foregroundColor: const Color(0xFF5A2C62),
            disabledForegroundColor: const Color(0xFFB090B6),
            shape: const CircleBorder(),
            side: const BorderSide(color: Color(0xFFE8D8EA)),
            padding: EdgeInsets.zero,
          ),
          icon: Icon(
            isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _NowPlayingArtworkCard extends StatelessWidget {
  const _NowPlayingArtworkCard({
    required this.artworkUrl,
    required this.isPlaying,
    required this.controller,
  });

  final String? artworkUrl;
  final bool isPlaying;
  final Animation<double> controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final glow = isPlaying
            ? 0.22 + (math.sin(controller.value * math.pi * 2).abs() * 0.14)
            : 0.14;
        final screenWidth = MediaQuery.sizeOf(context).width;
        final artworkSize = math.min(screenWidth - 64, 292.0);
        return Center(
          child: Container(
            width: artworkSize,
            height: artworkSize,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.zero,
              color: const Color(0xFFF4E7F4),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF5A2C62).withValues(alpha: glow),
                  blurRadius: isPlaying ? 40 : 24,
                  spreadRadius: isPlaying ? 2 : 0,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.75),
                  blurRadius: 18,
                  offset: const Offset(-8, -8),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFFB66BA2),
                          Color(0xFF6E2D72),
                          Color(0xFF2A0736),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: artworkUrl == null
                      ? const Icon(
                          Icons.music_note_rounded,
                          size: 92,
                          color: Colors.white,
                        )
                      : Image.network(
                          artworkUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.music_note_rounded,
                            size: 92,
                            color: Colors.white,
                          ),
                        ),
                ),
                if (isPlaying)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlaybackMoodPill extends StatelessWidget {
  const _PlaybackMoodPill({
    required this.isPlaying,
    required this.isConnecting,
    required this.isSpotifyPlayback,
  });

  final bool isPlaying;
  final bool isConnecting;
  final bool isSpotifyPlayback;

  @override
  Widget build(BuildContext context) {
    final label = isConnecting
        ? 'Connecting your music'
        : isPlaying
        ? isSpotifyPlayback
              ? 'Full track playing'
              : 'Preview playing'
        : 'Ready when you are';
    final icon = isConnecting
        ? Icons.sync_rounded
        : isPlaying
        ? Icons.graphic_eq_rounded
        : Icons.nightlight_round;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE3D4E5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4A154B).withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFFF4EAF5),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 12, color: const Color(0xFF6E2D72)),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF5A2C62),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerControlDeck extends StatelessWidget {
  const _PlayerControlDeck({
    required this.isPlaying,
    required this.isConnecting,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
  });

  final bool isPlaying;
  final bool isConnecting;
  final VoidCallback onPrevious;
  final VoidCallback? onToggle;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundControlButton(
          icon: Icons.skip_previous_rounded,
          onTap: onPrevious,
          size: 44,
        ),
        const SizedBox(width: 20),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [
                Color(0xFF9B4AA3),
                Color(0xFF6E2D72),
                Color(0xFF3C103F),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF5A2C62).withValues(alpha: 0.36),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(-4, -5),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(
              isConnecting
                  ? Icons.more_horiz_rounded
                  : isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 34,
              color: Colors.white,
            ),
            onPressed: onToggle,
          ),
        ),
        const SizedBox(width: 20),
        _RoundControlButton(
          icon: Icons.skip_next_rounded,
          onTap: onNext,
          size: 44,
        ),
      ],
    );
  }
}

class _RoundControlButton extends StatelessWidget {
  const _RoundControlButton({
    required this.icon,
    required this.onTap,
    required this.size,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFEADDEA)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6E2D72).withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: const Color(0xFF5A2C62),
          size: 26,
        ),
      ),
    );
  }
}

class _PlayerWaveform extends StatelessWidget {
  const _PlayerWaveform({
    required this.controller,
    required this.isPlaying,
  });

  final Animation<double> controller;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(24, (index) {
              final idleHeights = [12.0, 18.0, 10.0, 22.0, 14.0, 26.0];
              final idleHeight = idleHeights[index % idleHeights.length];
              final phase =
                  (controller.value * math.pi * 2) + (index * 0.48);
              final soundLift = math.sin(phase).abs();
              final accentLift = math.cos(phase * 0.62).abs();
              final liveHeight = 8 + (soundLift * 24) + (accentLift * 8);
              final height = isPlaying ? liveHeight : idleHeight;

              return AnimatedContainer(
                duration: Duration(milliseconds: isPlaying ? 90 : 220),
                width: 4,
                height: height,
                decoration: BoxDecoration(
                  color: const Color(0xFF5A2C62).withValues(
                    alpha: isPlaying ? 0.72 : 0.42,
                  ),
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _PreviewProgressBar extends StatelessWidget {
  const _PreviewProgressBar({required this.audioPlayer});

  final AudioPlayer audioPlayer;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: audioPlayer.positionStream,
      initialData: Duration.zero,
      builder: (context, positionSnapshot) {
        final position = positionSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: audioPlayer.durationStream,
          initialData: audioPlayer.duration,
          builder: (context, durationSnapshot) {
            final duration = durationSnapshot.data ?? Duration.zero;
            return _ProgressSlider(
              position: position,
              duration: duration,
              onSeek: duration.inMilliseconds <= 0
                  ? null
                  : (value) => audioPlayer.seek(value),
            );
          },
        );
      },
    );
  }
}

class _SpotifyProgressBar extends StatelessWidget {
  const _SpotifyProgressBar({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    return _ProgressSlider(
      position: position,
      duration: duration,
      onSeek: onSeek,
    );
  }
}

class _ProgressSlider extends StatelessWidget {
  const _ProgressSlider({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration>? onSeek;

  @override
  Widget build(BuildContext context) {
    final maxSeconds = duration.inMilliseconds <= 0
        ? 1.0
        : duration.inMilliseconds.toDouble();
    final positionMs = position.inMilliseconds
        .clamp(0, maxSeconds.toInt())
        .toDouble();

    return Column(
      children: [
        Slider(
          value: positionMs,
          min: 0,
          max: maxSeconds,
          onChanged: onSeek == null
              ? null
              : (value) {
                  onSeek!(Duration(milliseconds: value.round()));
                },
          activeColor: const Color(0xFF5A2C62),
          inactiveColor: const Color(0xFFE2D1DF),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.black45,
                ),
              ),
              Text(
                duration.inMilliseconds <= 0
                    ? '--:--'
                    : _formatDuration(duration),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.black45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.isActive,
    required this.onTap,
  });

  final AuraliaTrack track;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [Color(0xFFF0DFF2), Color(0xFFFFFFFF)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: isActive ? null : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? const Color(0xFF8C4B8F) : const Color(0xFFF0E8F1),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A154B).withValues(
                alpha: isActive ? 0.12 : 0.04,
              ),
              blurRadius: isActive ? 18 : 12,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 44,
                height: 44,
                child: track.imageUrl == null
                    ? Container(
                        color: const Color(0xFFE2D1DF),
                        child: Icon(
                          isActive
                              ? Icons.equalizer_rounded
                              : Icons.music_note_rounded,
                          color: const Color(0xFF5A2C62),
                        ),
                      )
                    : Image.network(
                        track.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: const Color(0xFFE2D1DF),
                          child: const Icon(
                            Icons.music_note_rounded,
                            color: Color(0xFF5A2C62),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF38143E),
                    ),
                  ),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF6E2D72)
                    : const Color(0xFFF4EAF5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isActive ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                size: 18,
                color: isActive ? Colors.white : const Color(0xFF6E2D72),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
