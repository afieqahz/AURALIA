import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/app_user.dart';
import '../models/mood.dart';
import '../models/playlist.dart';
import 'auralia_recommendation_service.dart';
import 'auth_service.dart';
import 'connectivity_bus.dart';
import 'mood_repository.dart';
import 'playlist_repository.dart';
import 'playlist_service.dart';
import 'post_listening_notification_service.dart';
import 'spotify_playlist_service.dart';
import 'spotify_track_details_service.dart';
import 'supabase_services.dart';

class AuraliaState extends ChangeNotifier {
  AuraliaState({
    AuthService? authService,
    MoodRepository? moodRepository,
    PlaylistRepository? playlistRepository,
    PlaylistService? playlistService,
  }) {
    final defaultAuthService = authService ?? _createDefaultAuthService();
    _authService = defaultAuthService;
    _moodRepository =
        moodRepository ?? _createDefaultMoodRepository(defaultAuthService);
    _playlistRepository =
        playlistRepository ??
        _createDefaultPlaylistRepository(defaultAuthService);
    _playlistService = playlistService ?? SpotifyPlaylistService();
    _currentPlaylist = const AuraliaRecommendationService().generatePlaylist(
      AuraliaMood.neutral,
    );
    _loadInitialHistory();
  }

  late final AuthService _authService;
  late final MoodRepository _moodRepository;
  late final PlaylistRepository _playlistRepository;
  late final PlaylistService _playlistService;
  final SpotifyTrackDetailsService _trackDetailsService =
      SpotifyTrackDetailsService();
  final List<MoodEntry> _moodHistory = [];
  final List<AuraliaPlaylist> _playlistOptions = [];
  final List<AuraliaPlaylist> _favoritePlaylists = [];
  final List<AuraliaPlaylist> _savedPlaylists = [];

  late AuraliaPlaylist _currentPlaylist;
  AuraliaPlaylist? _playbackPlaylist;
  AppUser? _currentUser;
  String? _playbackOwnerUserId;
  String? _currentMoodId;
  int? _currentPlaylistId;
  bool _isCurrentPlaylistLiked = false;
  bool _isBusy = false;
  int _playbackRequestId = 0;
  int _playlistSelectionId = 0;
  int _activeTrackIndex = 0;
  bool _hasActivePlayback = false;
  bool _isPlaybackPlaying = false;
  bool _playbackStartedByUser = false;
  String? _lastShownWellnessEntryKey;
  String? _errorMessage;
  bool _lastErrorWasConnectivity = false;

  static const _playbackPlaylistKey = 'auralia.playback.playlist';
  static const _playbackTrackIndexKey = 'auralia.playback.track_index';
  static const _playbackIsPlayingKey = 'auralia.playback.is_playing';
  static const _playbackSavedAtKey = 'auralia.playback.saved_at';
  static const _playbackUserIdKey = 'auralia.playback.user_id';
  static const _moodHistoryCachePrefix = 'auralia.mood_history';

  AppUser? get currentUser => _currentUser ?? _authService.currentUser;
  bool get isAuthenticated => currentUser != null;
  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  bool get lastErrorWasConnectivity => _lastErrorWasConnectivity;
  List<MoodEntry> get moodHistory => List.unmodifiable(_moodHistory);
  int get moodEntryCount => _moodHistory
      .where((entry) => entry.checkInType == MoodCheckInType.beforeListening)
      .length;
  int get postListeningCheckInCount => _moodHistory
      .where((entry) => entry.checkInType == MoodCheckInType.afterListening)
      .length;
  List<AuraliaPlaylist> get playlistOptions =>
      List.unmodifiable(_playlistOptions);
  List<AuraliaPlaylist> get favoritePlaylists =>
      List.unmodifiable(_favoritePlaylists);
  List<AuraliaPlaylist> get savedPlaylists =>
      List.unmodifiable(_savedPlaylists);
  List<AuraliaPlaylist> get recommendedPlaylists {
    final latestMoodValue = latestMood?.mood;
    final candidates = <AuraliaPlaylist>[
      ..._playlistOptions,
      ..._favoritePlaylists,
      ..._savedPlaylists,
    ];
    final seen = <String>{};
    final recommendations = <AuraliaPlaylist>[];

    for (final playlist in candidates) {
      if (latestMoodValue != null && playlist.sourceMood != latestMoodValue) {
        continue;
      }
      if (!_isSpotifyBackedPlaylist(playlist)) {
        continue;
      }
      if (seen.add(playlist.fingerprint)) {
        recommendations.add(playlist);
      }
    }

    return List.unmodifiable(recommendations);
  }

  AuraliaPlaylist get currentPlaylist => _currentPlaylist;
  AuraliaPlaylist? get playbackPlaylist => _playbackPlaylist;
  bool get isCurrentPlaylistSaved => _currentPlaylistId != null;
  bool get isCurrentPlaylistLiked => _isCurrentPlaylistLiked;
  int get playbackRequestId => _playbackRequestId;
  int get playlistSelectionId => _playlistSelectionId;
  int get activeTrackIndex => _activeTrackIndex;
  bool get hasActivePlayback =>
      _hasActivePlayback &&
      _playbackStartedByUser &&
      _isPlaybackOwnedByCurrentUser &&
      _isShowablePlaybackPlaylist &&
      activeTrack != null;
  bool get isPlaybackPlaying => _isPlaybackPlaying;
  AuraliaTrack? get activeTrack {
    if (!_isPlaybackOwnedByCurrentUser || !_isShowablePlaybackPlaylist) {
      return null;
    }
    final playlist = _playbackPlaylist;
    if (playlist == null || playlist.tracks.isEmpty) {
      return null;
    }
    return playlist.tracks[
        _activeTrackIndex.clamp(0, playlist.tracks.length - 1)];
  }
  bool get isViewingPlaybackPlaylist =>
      _playbackPlaylist != null &&
      _samePlaylist(_currentPlaylist, _playbackPlaylist!);
  bool get _isPlaybackOwnedByCurrentUser {
    final userId = currentUser?.id;
    return userId != null &&
        userId.isNotEmpty &&
        _playbackOwnerUserId != null &&
        _playbackOwnerUserId == userId;
  }
  bool get _isShowablePlaybackPlaylist {
    final playlist = _playbackPlaylist;
    return playlist != null && _isSpotifyBackedPlaylist(playlist);
  }
  MoodEntry? get latestMood {
    for (final entry in _moodHistory.reversed) {
      if (entry.checkInType == MoodCheckInType.beforeListening) {
        return entry;
      }
    }
    return null;
  }

  bool get shouldShowWellnessSuggestion {
    final recent = _moodHistory
        .where(
          (entry) => entry.checkInType == MoodCheckInType.beforeListening,
        )
        .toList();
    if (recent.length < 3) {
      return false;
    }

    final latestThree = recent.sublist(recent.length - 3);
    final latest = latestThree.last;
    final latestKey =
        latest.id ?? latest.createdAt.microsecondsSinceEpoch.toString();
    final streakJustReachedThree =
        latestThree.every((entry) => entry.mood.isNegative) &&
        (recent.length == 3 || !recent[recent.length - 4].mood.isNegative);
    return streakJustReachedThree &&
        latestKey != _lastShownWellnessEntryKey;
  }

  void markWellnessSuggestionShown() {
    final recent = _moodHistory
        .where(
          (entry) => entry.checkInType == MoodCheckInType.beforeListening,
        )
        .toList();
    if (recent.isEmpty) {
      return;
    }
    final latest = recent.last;
    _lastShownWellnessEntryKey =
        latest.id ?? latest.createdAt.microsecondsSinceEpoch.toString();
  }

  List<double> get weeklyScores {
    final now = DateTime.now();

    return List.generate(7, (index) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: 6 - index));
      final entries = _moodHistory.where((entry) {
        if (entry.checkInType != MoodCheckInType.beforeListening) {
          return false;
        }
        final created = DateTime(
          entry.createdAt.year,
          entry.createdAt.month,
          entry.createdAt.day,
        );
        return created == day;
      }).toList();

      if (entries.isEmpty) {
        return 0.5;
      }

      final total = entries.fold<double>(
        0,
        (sum, entry) => sum + entry.mood.score,
      );
      return total / entries.length;
    });
  }

  int get negativeMoodCount =>
      _moodHistory
          .where(
            (entry) =>
                entry.checkInType == MoodCheckInType.beforeListening &&
                entry.mood.isNegative,
          )
          .length;

  String get moodBaselineLabel {
    final scores = weeklyScores;
    final average =
        scores.fold<double>(0, (sum, score) => sum + score) / scores.length;
    return '${(average * 100).round()}% stable';
  }

  Future<bool> restoreSession() async {
    try {
      final restored = await _authService.restoreSession();
      _currentUser = _authService.currentUser;
      if (restored) {
        await _restorePlaybackState();
        unawaited(_refreshUserDataAfterAuthentication().then((_) {
          notifyListeners();
        }));
      }
      notifyListeners();
      return restored;
    } catch (error) {
      debugPrint('Saved session could not be restored: $error');
      return false;
    }
  }

  Future<bool> signIn({required String email, required String password}) async {
    return _runBusyTask(() async {
      await _clearPlaybackState();
      _resetPlaybackSession();
      _currentUser = await _authService.signIn(
        email: email,
        password: password,
      );
      await _clearPlaybackState();
      _resetPlaybackSession();
      await _refreshUserDataAfterAuthentication();
    });
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    return _runBusyTask(() async {
      await _clearPlaybackState();
      _resetPlaybackSession();
      _currentUser = await _authService.signUp(
        email: email,
        password: password,
        name: name,
      );
      await _clearPlaybackState();
      _resetPlaybackSession();
      await _refreshUserDataAfterAuthentication();
    });
  }

  Future<bool> resetPassword({required String email}) async {
    return _runBusyTask(() async {
      await _authService.resetPassword(email: email);
    });
  }

  Future<bool> completePasswordReset({
    required String accessToken,
    required String newPassword,
  }) async {
    return _runBusyTask(() async {
      await _authService.completePasswordReset(
        accessToken: accessToken,
        newPassword: newPassword,
      );
    });
  }

  Future<bool> updateProfile({required String name}) async {
    return _runBusyTask(() async {
      _currentUser = await _authService.updateProfile(name: name.trim());
    });
  }

  Future<bool> changePassword({required String newPassword}) async {
    return _runBusyTask(() async {
      await _authService.changePassword(newPassword: newPassword);
    });
  }

  Future<bool> deleteAccount() async {
    return _runBusyTask(() async {
      final userId = currentUser?.id ?? 'local-user';
      await PostListeningNotificationService.instance.cancelPlaylistFeedback();
      await _clearPlaybackState();
      await _authService.deleteAccount();
      await _clearMoodHistoryCache(userId);
      _currentUser = null;
      _currentMoodId = null;
      _currentPlaylistId = null;
      _resetPlaybackSession();
      _lastShownWellnessEntryKey = null;
      _isCurrentPlaylistLiked = false;
      _moodHistory.clear();
      _playlistOptions.clear();
      _favoritePlaylists.clear();
      _savedPlaylists.clear();
    });
  }

  Future<void> signOut() async {
    final userId = currentUser?.id ?? 'local-user';
    await PostListeningNotificationService.instance.cancelPlaylistFeedback();
    await _clearPlaybackState();
    await _authService.signOut();
    await _clearMoodHistoryCache(userId);
    _currentUser = null;
    _currentMoodId = null;
    _currentPlaylistId = null;
    _resetPlaybackSession();
    _lastShownWellnessEntryKey = null;
    _isCurrentPlaylistLiked = false;
    _moodHistory.clear();
    _playlistOptions.clear();
    _favoritePlaylists.clear();
    _savedPlaylists.clear();
    notifyListeners();
  }

  Future<void> refreshUserData() async {
    await Future.wait([
      refreshMoodHistory(),
      refreshSavedPlaylists(),
      refreshFavoritePlaylists(),
    ]);
  }

  Future<void> _refreshUserDataAfterAuthentication() async {
    try {
      await refreshUserData();
    } catch (error) {
      debugPrint('User data could not be refreshed after authentication: $error');
      _moodHistory.clear();
      _savedPlaylists.clear();
      _favoritePlaylists.clear();
    }
  }

  Future<void> refreshMoodHistory() async {
    final userId = currentUser?.id ?? 'local-user';
    var entries = <MoodEntry>[];
    try {
      entries = await _moodRepository.loadMoodHistory(userId);
    } catch (error) {
      debugPrint('Mood history could not be loaded from Supabase: $error');
    }
    final cachedEntries = await _loadCachedMoodEntries(userId);
    _moodHistory
      ..clear()
      ..addAll(_mergeMoodEntries([...entries, ...cachedEntries]));
    notifyListeners();
  }

  Future<void> refreshSavedPlaylists() async {
    final userId = currentUser?.id ?? 'local-user';
    final playlists = await _trackDetailsService.enrichPlaylists(
      await _playlistRepository.loadSavedPlaylists(userId),
    );
    _savedPlaylists
      ..clear()
      ..addAll(playlists);
    notifyListeners();
  }

  Future<void> refreshFavoritePlaylists() async {
    final userId = currentUser?.id ?? 'local-user';
    final playlists = await _trackDetailsService.enrichPlaylists(
      await _playlistRepository.loadFavoritePlaylists(userId),
    );
    _favoritePlaylists
      ..clear()
      ..addAll(playlists);
    _isCurrentPlaylistLiked = _favoritePlaylists.any(
      (playlist) => _samePlaylist(playlist, _currentPlaylist),
    );
    notifyListeners();
  }

  Future<bool> recordMood(AuraliaMood mood) async {
    return _runBusyTask(() async {
      final userId = currentUser?.id ?? 'local-user';
      final entry = await _moodRepository.saveMoodEntry(
        userId: userId,
        mood: mood,
      );
      _moodHistory.add(entry);
      _currentMoodId = entry.id;
      await _cacheMoodEntry(userId, entry);
      notifyListeners();
      unawaited(refreshMoodHistory().catchError((_) {}));
      final generatedOptions = await _playlistService.generatePlaylistOptions(
        mood,
        context: PlaylistGenerationContext(
          userId: userId,
          favoritePlaylists: List.unmodifiable(_favoritePlaylists),
          savedPlaylists: List.unmodifiable(_savedPlaylists),
          moodHistory: List.unmodifiable(_moodHistory),
        ),
      );
      _playlistOptions
        ..clear()
        ..addAll(generatedOptions);
      if (generatedOptions.isEmpty && AppConfig.spotifyOnly) {
        throw Exception(
          'Spotify API did not return playlists. Fallback is disabled for testing.',
        );
      }
      _currentPlaylist = generatedOptions.isEmpty
          ? await _playlistService.generatePlaylist(mood)
          : generatedOptions.first;
      _currentPlaylistId = null;
      _isCurrentPlaylistLiked = false;
      _enrichGeneratedPlaylistsInBackground([
        ...generatedOptions,
        if (generatedOptions.isEmpty) _currentPlaylist,
      ]);
    });
  }

  Future<bool> recordPostListeningCheckIn({
    required AuraliaMood mood,
    required ListeningHelpfulness helpfulness,
  }) async {
    return _runBusyTask(() async {
      final userId = currentUser?.id ?? 'local-user';
      final entry = await _moodRepository.saveMoodEntry(
        userId: userId,
        mood: mood,
        checkInType: MoodCheckInType.afterListening,
        playlistName: _playbackPlaylist?.name ?? _currentPlaylist.name,
        helpfulness: helpfulness,
      );
      _moodHistory.add(entry);
      await _cacheMoodEntry(userId, entry);
      notifyListeners();
      unawaited(refreshMoodHistory().catchError((_) {}));
      await PostListeningNotificationService.instance.cancelPlaylistFeedback();
      await _clearPlaybackState();
    });
  }

  void selectPlaylist(AuraliaPlaylist playlist) {
    _currentPlaylist = playlist;
    _currentPlaylistId = playlist.databaseId;
    _playlistSelectionId++;
    _isCurrentPlaylistLiked = _favoritePlaylists.any(
      (favorite) => _samePlaylist(favorite, playlist),
    );
    notifyListeners();
    _enrichSelectedPlaylistArtwork();
  }

  void playCurrentPlaylist() {
    final userId = currentUser?.id;
    if (userId == null || userId.isEmpty) {
      return;
    }
    if (!_isSpotifyBackedPlaylist(_currentPlaylist)) {
      _resetPlaybackSession();
      unawaited(_clearPlaybackState());
      return;
    }
    _playbackPlaylist = _currentPlaylist;
    _playbackOwnerUserId = userId;
    _activeTrackIndex = 0;
    _hasActivePlayback = true;
    _isPlaybackPlaying = true;
    _playbackStartedByUser = true;
    _playbackRequestId++;
    notifyListeners();
    unawaited(_savePlaybackState());
    unawaited(
      PostListeningNotificationService.instance.schedulePlaylistFeedback(
        _playbackPlaylist!,
      ),
    );
  }

  void openActivePlaybackPlaylist() {
    final playlist = _playbackPlaylist;
    if (playlist == null || !_isPlaybackOwnedByCurrentUser) {
      return;
    }
    _currentPlaylist = playlist;
    _currentPlaylistId = playlist.databaseId;
    _playlistSelectionId++;
    _isCurrentPlaylistLiked = _favoritePlaylists.any(
      (favorite) => _samePlaylist(favorite, playlist),
    );
    notifyListeners();
  }

  void activateCurrentPlaylistForPlayback({required int activeTrackIndex}) {
    final userId = currentUser?.id;
    if (userId == null || userId.isEmpty) {
      return;
    }
    if (!_isSpotifyBackedPlaylist(_currentPlaylist)) {
      _resetPlaybackSession();
      unawaited(_clearPlaybackState());
      return;
    }
    _playbackPlaylist = _currentPlaylist;
    _playbackOwnerUserId = userId;
    _activeTrackIndex = activeTrackIndex;
    _hasActivePlayback = true;
    _playbackStartedByUser = true;
  }

  void updatePlaybackState({
    required int activeTrackIndex,
    required bool isPlaying,
  }) {
    final userId = currentUser?.id;
    if (userId == null || userId.isEmpty) {
      return;
    }
    _playbackPlaylist ??= _currentPlaylist;
    if (!_isShowablePlaybackPlaylist) {
      _resetPlaybackSession();
      unawaited(_clearPlaybackState());
      return;
    }
    _playbackOwnerUserId = userId;
    _activeTrackIndex = activeTrackIndex;
    _hasActivePlayback = true;
    _playbackStartedByUser = true;
    _isPlaybackPlaying = isPlaying;
    notifyListeners();
    unawaited(_savePlaybackState());
  }

  Future<void> _restorePlaybackState() async {
    try {
      final userId = currentUser?.id;
      if (userId == null || userId.isEmpty) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final savedUserId = prefs.getString(_playbackUserIdKey);
      if (savedUserId == null || savedUserId != userId) {
        await _clearPlaybackState();
        _resetPlaybackSession();
        return;
      }

      final savedAt = prefs.getInt(_playbackSavedAtKey);
      if (savedAt == null) {
        return;
      }

      final savedTime = DateTime.fromMillisecondsSinceEpoch(savedAt);
      if (DateTime.now().difference(savedTime) > const Duration(hours: 12)) {
        await _clearPlaybackState();
        return;
      }

      final playlistJson = prefs.getString(_playbackPlaylistKey);
      if (playlistJson == null || playlistJson.isEmpty) {
        return;
      }

      final playlist = AuraliaPlaylist.fromDatabaseJson(
        jsonDecode(playlistJson) as Map<String, dynamic>,
      );
      if (playlist.tracks.isEmpty) {
        return;
      }
      if (!_isSpotifyBackedPlaylist(playlist)) {
        await _clearPlaybackState();
        _resetPlaybackSession();
        return;
      }

      _playbackPlaylist = playlist;
      _playbackOwnerUserId = userId;
      _currentPlaylist = playlist;
      _activeTrackIndex =
          (prefs.getInt(_playbackTrackIndexKey) ?? 0)
              .clamp(0, playlist.tracks.length - 1)
              .toInt();
      // Spotify may keep playing after AURALIA is closed, but the Spotify SDK
      // remote connection itself is not restored with the app process. Keep the
      // last playlist visible without claiming AURALIA is still connected.
      _isPlaybackPlaying = false;
      _hasActivePlayback = true;
      _playbackStartedByUser = false;
      _playlistSelectionId++;
      notifyListeners();
    } catch (error) {
      debugPrint('Playback state could not be restored: $error');
      await _clearPlaybackState();
    }
  }

  Future<void> _savePlaybackState() async {
    final playlist = _playbackPlaylist;
    if (playlist == null || playlist.tracks.isEmpty) {
      return;
    }
    if (!_isSpotifyBackedPlaylist(playlist)) {
      await _clearPlaybackState();
      return;
    }
    final userId = currentUser?.id;
    if (userId == null || userId.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_playbackUserIdKey, userId);
    await prefs.setString(
      _playbackPlaylistKey,
      jsonEncode(_playlistToStoredJson(playlist)),
    );
    await prefs.setInt(_playbackTrackIndexKey, _activeTrackIndex);
    await prefs.setBool(_playbackIsPlayingKey, _isPlaybackPlaying);
    await prefs.setInt(
      _playbackSavedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _clearPlaybackState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_playbackPlaylistKey);
    await prefs.remove(_playbackTrackIndexKey);
    await prefs.remove(_playbackIsPlayingKey);
    await prefs.remove(_playbackSavedAtKey);
    await prefs.remove(_playbackUserIdKey);
  }

  void _resetPlaybackSession() {
    _playbackPlaylist = null;
    _playbackOwnerUserId = null;
    _hasActivePlayback = false;
    _isPlaybackPlaying = false;
    _playbackStartedByUser = false;
    _activeTrackIndex = 0;
    _playbackRequestId++;
  }

  bool _isSpotifyBackedPlaylist(AuraliaPlaylist playlist) {
    return playlist.tracks.isNotEmpty &&
        playlist.tracks.every(_isSpotifyBackedTrack);
  }

  bool _isSpotifyBackedTrack(AuraliaTrack track) {
    final artist = track.artist.trim().toLowerCase();
    if (artist.startsWith('auralia ')) {
      return false;
    }

    final externalUrl = track.externalUrl?.trim().toLowerCase() ?? '';
    if (externalUrl.contains('open.spotify.com/track')) {
      return true;
    }

    final imageUrl = track.imageUrl?.trim().toLowerCase() ?? '';
    if (imageUrl.contains('scdn.co') || imageUrl.contains('spotifycdn')) {
      return true;
    }

    final id = track.id?.trim();
    return id != null &&
        id.isNotEmpty &&
        !track.title.toLowerCase().startsWith('balance ');
  }

  Map<String, dynamic> _playlistToStoredJson(AuraliaPlaylist playlist) {
    return {
      'id': playlist.databaseId,
      'playlist_name': playlist.name,
      'source_mood': playlist.sourceMood.name,
      'summary': playlist.summary,
      'track': playlist.tracks.map((track) => track.toJson()).toList(),
    };
  }

  void updateCurrentTrackDetails({
    required String trackId,
    String? imageUrl,
    String? previewUrl,
    String? externalUrl,
    int? durationMs,
  }) {
    bool updateTrack(AuraliaTrack track) => track.id == trackId;

    AuraliaTrack mergeTrack(AuraliaTrack track) {
      if (!updateTrack(track)) {
        return track;
      }
      return AuraliaTrack(
        id: track.id,
        title: track.title,
        artist: track.artist,
        stage: track.stage,
        valence: track.valence,
        energy: track.energy,
        previewUrl: previewUrl ?? track.previewUrl,
        imageUrl: imageUrl ?? track.imageUrl,
        externalUrl: externalUrl ?? track.externalUrl,
        durationMs: durationMs ?? track.durationMs,
      );
    }

    final hasCurrentTrack = _currentPlaylist.tracks.any(updateTrack);
    final hasPlaybackTrack =
        _playbackPlaylist?.tracks.any(updateTrack) ?? false;
    final hasOptionTrack = _playlistOptions.any(
      (playlist) => playlist.tracks.any(updateTrack),
    );
    final hasSavedTrack = _savedPlaylists.any(
      (playlist) => playlist.tracks.any(updateTrack),
    );
    final hasFavoriteTrack = _favoritePlaylists.any(
      (playlist) => playlist.tracks.any(updateTrack),
    );

    if (!hasCurrentTrack &&
        !hasPlaybackTrack &&
        !hasOptionTrack &&
        !hasSavedTrack &&
        !hasFavoriteTrack) {
      return;
    }

    AuraliaPlaylist mergePlaylist(AuraliaPlaylist playlist) {
      return AuraliaPlaylist(
        databaseId: playlist.databaseId,
        name: playlist.name,
        sourceMood: playlist.sourceMood,
        summary: playlist.summary,
        tracks: playlist.tracks.map(mergeTrack).toList(),
      );
    }

    if (hasCurrentTrack) {
      _currentPlaylist = mergePlaylist(_currentPlaylist);
    }
    if (hasPlaybackTrack) {
      _playbackPlaylist = mergePlaylist(_playbackPlaylist!);
    }
    for (var i = 0; i < _playlistOptions.length; i++) {
      if (_playlistOptions[i].tracks.any(updateTrack)) {
        _playlistOptions[i] = mergePlaylist(_playlistOptions[i]);
      }
    }
    for (var i = 0; i < _savedPlaylists.length; i++) {
      if (_savedPlaylists[i].tracks.any(updateTrack)) {
        _savedPlaylists[i] = mergePlaylist(_savedPlaylists[i]);
      }
    }
    for (var i = 0; i < _favoritePlaylists.length; i++) {
      if (_favoritePlaylists[i].tracks.any(updateTrack)) {
        _favoritePlaylists[i] = mergePlaylist(_favoritePlaylists[i]);
      }
    }
    notifyListeners();
  }

  Future<void> _enrichSelectedPlaylistArtwork() async {
    final originalName = _currentPlaylist.name;
    final enriched = await _trackDetailsService.enrichPlaylist(
      _currentPlaylist,
    );
    if (originalName != _currentPlaylist.name) {
      return;
    }
    _currentPlaylist = enriched;
    notifyListeners();
  }

  Future<void> _enrichGeneratedPlaylistsInBackground(
    List<AuraliaPlaylist> playlists,
  ) async {
    if (playlists.isEmpty) {
      return;
    }

    final List<AuraliaPlaylist> enriched;
    try {
      enriched = await _trackDetailsService.enrichPlaylists(playlists);
    } catch (error) {
      debugPrint('Generated playlists could not be enriched: $error');
      return;
    }
    if (enriched.isEmpty) {
      return;
    }

    final enrichedByFingerprint = {
      for (final playlist in enriched) playlist.fingerprint: playlist,
    };
    var changed = false;

    for (var i = 0; i < _playlistOptions.length; i++) {
      final enrichedPlaylist =
          enrichedByFingerprint[_playlistOptions[i].fingerprint];
      if (enrichedPlaylist != null) {
        _playlistOptions[i] = enrichedPlaylist;
        changed = true;
      }
    }

    final enrichedCurrent = enrichedByFingerprint[_currentPlaylist.fingerprint];
    if (enrichedCurrent != null) {
      _currentPlaylist = enrichedCurrent;
      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  Future<bool> saveCurrentPlaylist() async {
    _attachExistingPlaylistIdIfAvailable();

    if (_currentPlaylistId != null) {
      if (!_isCurrentPlaylistLiked) {
        return _runBusyTask(() async {
          final userId = currentUser?.id ?? 'local-user';
          await _playlistRepository.setFavorite(
            userId: userId,
            playlistId: _currentPlaylistId!,
            liked: true,
          );
          _isCurrentPlaylistLiked = true;
          _favoritePlaylists.removeWhere(
            (playlist) => _samePlaylist(playlist, _currentPlaylist),
          );
          _favoritePlaylists.insert(0, _currentPlaylist);
        });
      }
      return true;
    }

    return _runBusyTask(() async {
      final userId = currentUser?.id ?? 'local-user';
      final generatedFingerprint = _currentPlaylist.fingerprint;
      _currentPlaylistId = await _playlistRepository.savePlaylist(
        userId: userId,
        moodId: _currentMoodId,
        playlist: _currentPlaylist,
      );
      _currentPlaylist = _currentPlaylist.copyWithDatabaseId(
        _currentPlaylistId!,
      );
      _savedPlaylists.removeWhere(
        (playlist) => _samePlaylist(playlist, _currentPlaylist),
      );
      _savedPlaylists.insert(0, _currentPlaylist);
      await _playlistRepository.setFavorite(
        userId: userId,
        playlistId: _currentPlaylistId!,
        liked: true,
      );
      _isCurrentPlaylistLiked = true;
      _favoritePlaylists.removeWhere(
        (playlist) => _samePlaylist(playlist, _currentPlaylist),
      );
      _favoritePlaylists.insert(0, _currentPlaylist);
      for (var i = 0; i < _playlistOptions.length; i++) {
        if (_playlistOptions[i].fingerprint == generatedFingerprint) {
          _playlistOptions[i] = _currentPlaylist;
        }
      }
    });
  }

  Future<bool> toggleCurrentPlaylistFavorite() async {
    _attachExistingPlaylistIdIfAvailable();

    if (_currentPlaylistId == null) {
      return saveCurrentPlaylist();
    }

    return _runBusyTask(() async {
      final userId = currentUser?.id ?? 'local-user';
      final liked = !_isCurrentPlaylistLiked;
      final duplicateFavoriteIds = _favoritePlaylists
          .where((playlist) => _samePlaylist(playlist, _currentPlaylist))
          .map((playlist) => playlist.databaseId)
          .whereType<int>()
          .where((playlistId) => playlistId != _currentPlaylistId)
          .toSet();
      await _playlistRepository.setFavorite(
        userId: userId,
        playlistId: _currentPlaylistId!,
        liked: liked,
      );
      if (!liked) {
        for (final playlistId in duplicateFavoriteIds) {
          await _playlistRepository.setFavorite(
            userId: userId,
            playlistId: playlistId,
            liked: false,
          );
        }
      }
      _isCurrentPlaylistLiked = liked;
      if (liked) {
        _favoritePlaylists.removeWhere(
          (playlist) => _samePlaylist(playlist, _currentPlaylist),
        );
        _favoritePlaylists.insert(0, _currentPlaylist);
      } else {
        _favoritePlaylists.removeWhere(
          (playlist) => _samePlaylist(playlist, _currentPlaylist),
        );
      }
    });
  }

  Future<bool> removePlaylistFromFavorites(AuraliaPlaylist playlist) async {
    final playlistId = playlist.databaseId;
    if (playlistId == null) {
      _favoritePlaylists.removeWhere(
        (favorite) => _samePlaylist(favorite, playlist),
      );
      if (_samePlaylist(_currentPlaylist, playlist)) {
        _isCurrentPlaylistLiked = false;
      }
      notifyListeners();
      return true;
    }

    return _runBusyTask(() async {
      final userId = currentUser?.id ?? 'local-user';
      final duplicateFavoriteIds = _favoritePlaylists
          .where((favorite) => _samePlaylist(favorite, playlist))
          .map((favorite) => favorite.databaseId)
          .whereType<int>()
          .where((favoriteId) => favoriteId != playlistId)
          .toSet();
      await _playlistRepository.setFavorite(
        userId: userId,
        playlistId: playlistId,
        liked: false,
      );
      for (final duplicateId in duplicateFavoriteIds) {
        await _playlistRepository.setFavorite(
          userId: userId,
          playlistId: duplicateId,
          liked: false,
        );
      }
      _favoritePlaylists.removeWhere(
        (favorite) =>
            favorite.databaseId == playlistId ||
            _samePlaylist(favorite, playlist),
      );
      if (_currentPlaylistId == playlistId ||
          _samePlaylist(_currentPlaylist, playlist)) {
        _isCurrentPlaylistLiked = false;
      }
    });
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> _runBusyTask(Future<void> Function() task) async {
    _isBusy = true;
    _errorMessage = null;
    _lastErrorWasConnectivity = false;
    notifyListeners();

    try {
      await task();
      return true;
    } catch (error) {
      final isConnectivityError = _isConnectivityError(error);
      _lastErrorWasConnectivity = isConnectivityError;
      if (isConnectivityError) {
        // Don't surface a raw SocketException/ClientException string —
        // the global connectivity overlay already tells the user what's
        // wrong. Just nudge it to check right away instead of waiting for
        // its next poll.
        _errorMessage = null;
        ConnectivityBus.instance.notifyPossibleDisconnect();
      } else {
        _errorMessage = _friendlyErrorMessage(error);
      }
      return false;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  bool _isConnectivityError(Object error) {
    if (error is SocketException) {
      return true;
    }
    final text = error.toString();
    return text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('Connection failed') ||
        text.contains('Network is unreachable') ||
        text.contains('Connection reset by peer');
  }

  String _friendlyErrorMessage(Object error) {
    final raw = error.toString().trim();
    final message = raw
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^AuthFlowException:\s*'), '')
        .trim();
    final lower = message.toLowerCase();

    if (lower.contains('jwt') ||
        lower.contains('unauthorized') ||
        lower.contains('invalid token')) {
      return 'Your session has expired. Please log in again.';
    }
    if (lower.contains('spotify api did not return playlists')) {
      return 'Spotify did not return playlists right now. Please try again.';
    }
    if (lower.contains('failed to save mood')) {
      return 'Unable to save your mood right now. Please try again.';
    }
    if (lower.contains('failed to load mood history')) {
      return 'Unable to load your mood history right now.';
    }
    if (lower.contains('failed to load playlists') ||
        lower.contains('failed to load favorites')) {
      return 'Unable to load your playlists right now.';
    }
    if (lower.contains('failed to save playlist') ||
        lower.contains('failed to save tracks')) {
      return 'Unable to save this playlist right now. Please try again.';
    }
    if (lower.contains('failed to like playlist') ||
        lower.contains('failed to unlike playlist')) {
      return 'Unable to update this playlist right now. Please try again.';
    }
    if (message.isEmpty) {
      return 'Something went wrong. Please try again.';
    }
    return message;
  }

  Future<void> _cacheMoodEntry(String userId, MoodEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _moodHistoryCacheKey(userId);
    final cached = await _loadCachedMoodEntries(userId);
    final merged = _mergeMoodEntries([...cached, entry]);
    await prefs.setString(
      key,
      jsonEncode(merged.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<MoodEntry>> _loadCachedMoodEntries(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getString(_moodHistoryCacheKey(userId));
      if (encoded == null || encoded.isEmpty) {
        return const [];
      }
      final rows = jsonDecode(encoded);
      if (rows is! List) {
        return const [];
      }
      return rows.whereType<Map>().map((row) {
        return MoodEntry.fromJson(Map<String, dynamic>.from(row));
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _clearMoodHistoryCache(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_moodHistoryCacheKey(userId));
  }

  List<MoodEntry> _mergeMoodEntries(List<MoodEntry> entries) {
    final byKey = <String, MoodEntry>{};
    for (final entry in entries) {
      final semanticKey = _moodEntrySemanticKey(entry);
      final existing = byKey[semanticKey];
      if (existing == null || (existing.id == null && entry.id != null)) {
        byKey[semanticKey] = entry;
      }
    }
    return byKey.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  String _moodEntrySemanticKey(MoodEntry entry) {
    final createdAt = entry.createdAt.toUtc().toIso8601String();
    return [
      createdAt,
      entry.mood.name,
      entry.checkInType.name,
      entry.playlistName ?? '',
      entry.helpfulness?.name ?? '',
    ].join('|');
  }

  String _moodHistoryCacheKey(String userId) =>
      '$_moodHistoryCachePrefix.$userId';

  Future<void> _loadInitialHistory() async {
    if (!AppConfig.hasSupabaseConfig || isAuthenticated) {
      try {
        await refreshUserData();
      } catch (error) {
        debugPrint('Initial user data could not be loaded: $error');
      }
    }
  }

  bool _samePlaylist(AuraliaPlaylist first, AuraliaPlaylist second) {
    if (first.databaseId != null &&
        second.databaseId != null &&
        first.databaseId == second.databaseId) {
      return true;
    }
    if (first.fingerprint == second.fingerprint) {
      return true;
    }
    if (first.sourceMood != second.sourceMood ||
        _normalizedPlaylistName(first.name) !=
            _normalizedPlaylistName(second.name)) {
      return false;
    }

    final firstKeys = first.tracks.map(_trackIdentityKey).toSet();
    final secondKeys = second.tracks.map(_trackIdentityKey).toSet();
    firstKeys.remove('');
    secondKeys.remove('');
    if (firstKeys.isEmpty || secondKeys.isEmpty) {
      return false;
    }

    final overlap = firstKeys.intersection(secondKeys).length;
    return overlap >= 3 ||
        overlap == firstKeys.length ||
        overlap == secondKeys.length;
  }

  void _attachExistingPlaylistIdIfAvailable() {
    if (_currentPlaylistId != null) {
      return;
    }

    for (final playlist in [
      ..._favoritePlaylists,
      ..._savedPlaylists,
      ..._playlistOptions,
    ]) {
      final playlistId = playlist.databaseId;
      if (playlistId != null && _samePlaylist(playlist, _currentPlaylist)) {
        _currentPlaylistId = playlistId;
        _currentPlaylist = _currentPlaylist.copyWithDatabaseId(playlistId);
        _isCurrentPlaylistLiked = _favoritePlaylists.any(
          (favorite) => _samePlaylist(favorite, _currentPlaylist),
        );
        return;
      }
    }
  }

  String _normalizedPlaylistName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _trackIdentityKey(AuraliaTrack track) {
    final id = track.id?.trim();
    if (id != null && id.isNotEmpty) {
      return 'id:$id';
    }
    final title = track.title.trim().toLowerCase();
    final artist = track.artist.trim().toLowerCase();
    if (title.isEmpty && artist.isEmpty) {
      return '';
    }
    return 'text:$title|$artist';
  }

  static AuthService _createDefaultAuthService() {
    if (AppConfig.hasSupabaseConfig) {
      return SupabaseAuthService();
    }
    return LocalAuthService();
  }

  static MoodRepository _createDefaultMoodRepository(AuthService authService) {
    if (AppConfig.hasSupabaseConfig && authService is SupabaseAuthService) {
      return SupabaseMoodRepository(
        accessTokenProvider: () => authService.accessToken,
      );
    }
    return LocalMoodRepository();
  }

  static PlaylistRepository _createDefaultPlaylistRepository(
    AuthService authService,
  ) {
    if (AppConfig.hasSupabaseConfig && authService is SupabaseAuthService) {
      return SupabasePlaylistRepository(
        accessTokenProvider: () => authService.accessToken,
      );
    }
    return LocalPlaylistRepository();
  }
}
