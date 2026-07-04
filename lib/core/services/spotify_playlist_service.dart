import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/mood.dart';
import '../models/playlist.dart';
import 'playlist_service.dart';

class SpotifyPlaylistService implements PlaylistService {
  SpotifyPlaylistService({
    http.Client? client,
    this._fallback = const LocalPlaylistService(),
  }) : _client = client ?? http.Client();

  static const _selectionOffsets = <List<int>>[
    [0, 1, 2],
    [3, 4, 5],
    [0, 2, 4],
    [1, 3, 5],
    [0, 3, 4],
    [1, 2, 5],
    [0, 1, 5],
    [2, 3, 4],
  ];

  final http.Client _client;
  final PlaylistService _fallback;
  String? _cachedAccessToken;
  DateTime? _tokenExpiresAt;

  @override
  Future<AuraliaPlaylist> generatePlaylist(AuraliaMood mood) async {
    final accessToken = await _resolveAccessToken();
    if (accessToken == null) {
      if (AppConfig.spotifyOnly) {
        throw Exception(
          'Spotify API did not return playlists. Fallback is disabled for testing.',
        );
      }
      return _fallback.generatePlaylist(mood);
    }

    try {
      final playlist = await _generateSpotifyPlaylist(
        name: _nameForMood(mood),
        summary: _summaryForMood(mood),
        mood: mood,
        accessToken: accessToken,
        optionIndex: 0,
      );
      if (playlist != null) {
        return playlist;
      }
      if (AppConfig.spotifyOnly) {
        throw Exception(
          'Spotify API did not return playlists. Fallback is disabled for testing.',
        );
      }
      return await _fallback.generatePlaylist(mood);
    } catch (_) {
      if (AppConfig.spotifyOnly) {
        rethrow;
      }
      return _fallback.generatePlaylist(mood);
    }
  }

  @override
  Future<List<AuraliaPlaylist>> generatePlaylistOptions(
    AuraliaMood mood, {
    PlaylistGenerationContext? context,
  }) async {
    final seed = _generationSeed(mood, context);
    final fallbackOptions = _ensureEightPlaylistTemplates(
      mood,
      await _freshFallbackOptions(mood, seed),
    );
    final accessToken = await _resolveAccessToken();
    if (accessToken == null) {
      if (AppConfig.spotifyOnly) {
        throw Exception(
          'Spotify API is not available. Fallback is disabled for testing.',
        );
      }
      return await _curatedSpotifyOptions(
        mood: mood,
        fallbackOptions: fallbackOptions,
        seed: seed,
        context: context,
      );
    }

    final validOptions = await _generateSpotifyPlaylistOptions(
      mood: mood,
      fallbackOptions: fallbackOptions,
      accessToken: accessToken,
      seed: seed,
      context: context,
    );

    if (validOptions.isEmpty) {
      if (AppConfig.spotifyOnly) {
        throw Exception(
          'Spotify API returned no usable playlists. Fallback is disabled for testing.',
        );
      }
      return await _curatedSpotifyOptions(
        mood: mood,
        fallbackOptions: fallbackOptions,
        seed: seed,
        context: context,
      );
    }

    return validOptions;
  }

  Future<List<AuraliaPlaylist>> _curatedSpotifyOptions({
    required AuraliaMood mood,
    required List<AuraliaPlaylist> fallbackOptions,
    required int seed,
    PlaylistGenerationContext? context,
  }) async {
    final stagePools = _curatedCatalogForMood(mood);
    final stageCounts = context?.stageCountsForMood(mood) ?? const [3, 3, 3];
    final playlistTemplates = _ensureEightPlaylistTemplates(mood, fallbackOptions);
    final options = <AuraliaPlaylist>[];

    for (
      var optionIndex = 0;
      optionIndex < playlistTemplates.length;
      optionIndex++
    ) {
      final fallback = playlistTemplates[optionIndex];
      final tracks = <AuraliaTrack>[];
      final seen = <String>{};

      for (var stageIndex = 0; stageIndex < stagePools.length; stageIndex++) {
        final pool = stagePools[stageIndex];
        final stage = stageIndex == 0
            ? 'Validation'
            : stageIndex == 1
            ? 'Transition'
            : 'Elevation';

        for (
          var trackIndex = 0;
          trackIndex < stageCounts[stageIndex];
          trackIndex++
        ) {
          final offsets = _selectionOffsets[optionIndex % _selectionOffsets.length];
          final song = _pickCuratedSong(
            pool: pool,
            seen: seen,
            startIndex:
                seed +
                stageIndex * 11 +
                offsets[trackIndex % offsets.length] +
                trackIndex * 5,
          );

          final sequenceIndex = tracks.length;
          tracks.add(
            AuraliaTrack(
              id: song.id,
              title: song.title,
              artist: song.artist,
              stage: stage,
              valence: _stageValence(mood, sequenceIndex),
              energy: _stageEnergy(mood, sequenceIndex),
              externalUrl: 'https://open.spotify.com/track/${song.id}',
            ),
          );
        }
      }

      if (tracks.length == 9) {
        options.add(
          AuraliaPlaylist(
            name: _generatedPlaylistName(
              mood: mood,
              optionIndex: optionIndex,
              seed: seed,
            ),
            sourceMood: mood,
            summary: fallback.summary,
            tracks: tracks,
          ),
        );
      }
    }

    if (options.length != 8) {
      return const [];
    }

    return await _enrichPlaylistArtwork(options);
  }

  Future<List<AuraliaPlaylist>> _enrichPlaylistArtwork(
    List<AuraliaPlaylist> playlists,
  ) async {
    if (AppConfig.spotifyBackendUrl.isEmpty) {
      return playlists;
    }

    final ids = playlists
        .expand((playlist) => playlist.tracks)
        .map((track) => track.id)
        .whereType<String>()
        .where((id) => id.isNotEmpty && !id.startsWith('fallback-'))
        .toSet()
        .toList();

    if (ids.isEmpty) {
      return playlists;
    }

    final baseUri = Uri.parse(AppConfig.spotifyBackendUrl);
    final tracksPath = [
      baseUri.path.replaceAll(RegExp(r'/+$'), ''),
      'spotify',
      'tracks',
    ].where((part) => part.isNotEmpty).join('/');

    final spotifyById = <String, Map<String, dynamic>>{};
    try {
      for (var start = 0; start < ids.length; start += 50) {
        final response = await _client
            .get(
              baseUri.replace(
                path: '/$tracksPath',
                queryParameters: {'ids': ids.skip(start).take(50).join(',')},
              ),
            )
            .timeout(const Duration(seconds: 6));

        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final tracks = body['tracks'] as List<dynamic>? ?? [];
        for (final track in tracks.whereType<Map<String, dynamic>>()) {
          final id = track['id']?.toString();
          if (id != null && id.isNotEmpty) {
            spotifyById[id] = track;
          }
        }
      }

      if (spotifyById.isEmpty) {
        return playlists;
      }

      return playlists
          .map(
            (playlist) => AuraliaPlaylist(
              databaseId: playlist.databaseId,
              name: playlist.name,
              sourceMood: playlist.sourceMood,
              summary: playlist.summary,
              tracks: playlist.tracks
                  .map((track) => _mergeSpotifyTrackDetails(track, spotifyById))
                  .toList(),
            ),
          )
          .toList();
    } catch (_) {
      return playlists;
    }
  }

  AuraliaTrack _mergeSpotifyTrackDetails(
    AuraliaTrack track,
    Map<String, Map<String, dynamic>> spotifyById,
  ) {
    final id = track.id;
    final spotifyTrack = id == null ? null : spotifyById[id];
    if (spotifyTrack == null) {
      return track;
    }

    final album = spotifyTrack['album'] as Map<String, dynamic>?;
    final images = album?['images'] as List<dynamic>? ?? [];
    final image = images.isEmpty ? null : images.first as Map<String, dynamic>;
    final externalUrls = spotifyTrack['external_urls'] as Map<String, dynamic>?;

    return AuraliaTrack(
      id: track.id,
      title: track.title,
      artist: track.artist,
      stage: track.stage,
      valence: track.valence,
      energy: track.energy,
      previewUrl: spotifyTrack['preview_url']?.toString() ?? track.previewUrl,
      imageUrl: image?['url']?.toString() ?? track.imageUrl,
      externalUrl: externalUrls?['spotify']?.toString() ?? track.externalUrl,
      durationMs: _toInt(spotifyTrack['duration_ms']) ?? track.durationMs,
    );
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

  List<AuraliaPlaylist> _ensureEightPlaylistTemplates(
    AuraliaMood mood,
    List<AuraliaPlaylist> fallbackOptions,
  ) {
    if (fallbackOptions.length >= 8) {
      return fallbackOptions.take(8).toList();
    }

    final templates = List<AuraliaPlaylist>.from(fallbackOptions);
    final names = _templateNamesForMood(mood);
    var index = 0;
    while (templates.length < 8) {
      templates.add(
        AuraliaPlaylist(
          name: names[index % names.length],
          sourceMood: mood,
          summary: _summaryForMood(mood),
          tracks: const [],
        ),
      );
      index++;
    }
    return templates;
  }

  List<String> _templateNamesForMood(AuraliaMood mood) {
    switch (mood) {
      case AuraliaMood.sad:
        return const [
          'Gentle Lift Sequence',
          'Soft Hope Mix',
          'Night Calm Reset',
          'Emotional Recovery Flow',
          'Rainy Window Comfort',
          'Slow Healing Session',
          'Quiet Hope Radio',
          'After Tears Lift',
        ];
      case AuraliaMood.stressed:
        return const [
          'Stress Release Flow',
          'Deadline Decompression',
          'Breath and Reset',
          'Study Calm Mode',
          'Anxiety Ease Radio',
          'Calm Focus Station',
          'Pressure to Progress',
          'Unwind and Continue',
        ];
      case AuraliaMood.neutral:
        return const [
          'Balanced Study Drift',
          'Steady Focus Mix',
          'Neutral Reset',
          'Soft Productivity',
          'Clear Desk Flow',
          'Light Study Radio',
          'Warm Routine',
          'Even Pace Session',
        ];
      case AuraliaMood.happy:
        return const [
          'Positive Mood Keeper',
          'Bright Energy Mix',
          'Good Vibes Radio',
          'Happy Flow Session',
          'Sunlit Pop Drive',
          'Smile Boost Mix',
          'Weekend Glow',
          'Feel Good Station',
        ];
      case AuraliaMood.motivated:
        return const [
          'Momentum Builder',
          'Goal Mode Sequence',
          'Focus Energy Stream',
          'Deep Work Drive',
          'Productive Pulse',
          'Confidence Boost',
          'Finish Strong Mix',
          'Action Mode Radio',
        ];
    }
  }

  String _generatedPlaylistName({
    required AuraliaMood mood,
    required int optionIndex,
    required int seed,
  }) {
    final prefixes = _playlistNamePrefixesForMood(mood);
    final cores = _playlistNameCoresForMood(mood);
    final suffixes = _playlistNameSuffixesForMood(mood);
    final prefix = prefixes[(seed + optionIndex * 3) % prefixes.length];
    final core = cores[(seed ~/ 7 + optionIndex * 5) % cores.length];
    final suffix = suffixes[(seed ~/ 13 + optionIndex * 2) % suffixes.length];
    return '$prefix $core $suffix';
  }

  List<String> _playlistNamePrefixesForMood(AuraliaMood mood) {
    switch (mood) {
      case AuraliaMood.sad:
        return const [
          'Gentle',
          'Soft',
          'Quiet',
          'After Tears',
          'Rainy',
          'Healing',
          'Tender',
          'Hopeful',
        ];
      case AuraliaMood.stressed:
        return const [
          'Calm',
          'Breath',
          'Unwind',
          'Clear',
          'Ease',
          'Reset',
          'Steady',
          'Slow',
        ];
      case AuraliaMood.neutral:
        return const [
          'Balanced',
          'Steady',
          'Warm',
          'Clear',
          'Easy',
          'Light',
          'Smooth',
          'Everyday',
        ];
      case AuraliaMood.happy:
        return const [
          'Bright',
          'Golden',
          'Sunny',
          'Feel Good',
          'Glow',
          'Happy',
          'Fresh',
          'Upbeat',
        ];
      case AuraliaMood.motivated:
        return const [
          'Focus',
          'Momentum',
          'Goal',
          'Power',
          'Drive',
          'Action',
          'Forward',
          'Energy',
        ];
    }
  }

  List<String> _playlistNameCoresForMood(AuraliaMood mood) {
    switch (mood) {
      case AuraliaMood.sad:
        return const [
          'Recovery',
          'Heart',
          'Comfort',
          'Lift',
          'Window',
          'Hope',
          'Mood',
          'Reflection',
        ];
      case AuraliaMood.stressed:
        return const [
          'Release',
          'Focus',
          'Pressure',
          'Mind',
          'Pause',
          'Study',
          'Tension',
          'Balance',
        ];
      case AuraliaMood.neutral:
        return const [
          'Study',
          'Routine',
          'Drift',
          'Flow',
          'Reset',
          'Focus',
          'Mood',
          'Pace',
        ];
      case AuraliaMood.happy:
        return const [
          'Vibes',
          'Smile',
          'Pop',
          'Weekend',
          'Mood',
          'Energy',
          'Sunlight',
          'Joy',
        ];
      case AuraliaMood.motivated:
        return const [
          'Builder',
          'Mode',
          'Pulse',
          'Sprint',
          'Focus',
          'Confidence',
          'Hustle',
          'Progress',
        ];
    }
  }

  List<String> _playlistNameSuffixesForMood(AuraliaMood mood) {
    switch (mood) {
      case AuraliaMood.sad:
        return const [
          'Flow',
          'Radio',
          'Session',
          'Mix',
          'Sequence',
          'Reset',
          'Path',
          'Room',
        ];
      case AuraliaMood.stressed:
        return const [
          'Flow',
          'Station',
          'Reset',
          'Mix',
          'Session',
          'Mode',
          'Sequence',
          'Room',
        ];
      case AuraliaMood.neutral:
        return const [
          'Flow',
          'Radio',
          'Mix',
          'Session',
          'Mode',
          'Sequence',
          'Station',
          'Loop',
        ];
      case AuraliaMood.happy:
        return const [
          'Mix',
          'Radio',
          'Drive',
          'Session',
          'Flow',
          'Station',
          'Boost',
          'Loop',
        ];
      case AuraliaMood.motivated:
        return const [
          'Mix',
          'Mode',
          'Drive',
          'Sequence',
          'Flow',
          'Station',
          'Run',
          'Session',
        ];
    }
  }

  _CuratedSpotifySong _pickCuratedSong({
    required List<_CuratedSpotifySong> pool,
    required Set<String> seen,
    required int startIndex,
  }) {
    for (var offset = 0; offset < pool.length; offset++) {
      final song = pool[(startIndex + offset) % pool.length];
      if (seen.add(song.id)) {
        return song;
      }
    }

    final song = pool[startIndex % pool.length];
    seen.add('${song.id}-${seen.length}');
    return song;
  }

  Future<List<AuraliaPlaylist>> _generateSpotifyPlaylistOptions({
    required AuraliaMood mood,
    required List<AuraliaPlaylist> fallbackOptions,
    required String accessToken,
    required int seed,
    PlaylistGenerationContext? context,
  }) async {
    final plan = AppConfig.spotifyOnly
        ? _stageSearchPlanForMood(mood)
        : _queryPlanForMood(mood);
    final stageCounts = context?.stageCountsForMood(mood) ?? const [3, 3, 3];
    final results = await Future.wait(
      plan.map(
        (stage) => _searchTracks(
          query: stage.query,
          mood: mood,
          stage: stage.stage,
          valence: stage.valence,
          energy: stage.energy,
          accessToken: accessToken,
        ),
      ),
    ).timeout(
      Duration(seconds: AppConfig.spotifyOnly ? 20 : 12),
      onTimeout: () => List<List<AuraliaTrack>>.filled(plan.length, const []),
    );

    final stageOrder = <String>[];
    final tracksByStage = <String, List<AuraliaTrack>>{};
    for (var i = 0; i < plan.length; i++) {
      final stage = plan[i].stage;
      if (!tracksByStage.containsKey(stage)) {
        stageOrder.add(stage);
        tracksByStage[stage] = <AuraliaTrack>[];
      }
      tracksByStage[stage]!.addAll(results[i]);
    }

    final trackGroups = stageOrder
        .map(
          (stage) {
            final filtered = _filterTracksForMoodStage(
              mood: mood,
              stage: stage,
              tracks: _uniqueTracks(tracksByStage[stage] ?? const []),
            );
            return _personalizeTrackOrder(filtered, context);
          },
        )
        .toList();

    if (trackGroups.length != 3 ||
        trackGroups.every((group) => group.isEmpty)) {
      return const [];
    }

    final options = <AuraliaPlaylist>[];
    final sessionOffset = seed % 997;
    final contextOffset = (context?.personalizationSeed ?? 0) % 997;

    final playlistTemplates = _ensureEightPlaylistTemplates(
      mood,
      fallbackOptions,
    );
    final sessionSeen = <String>{};
    for (var optionIndex = 0; optionIndex < playlistTemplates.length; optionIndex++) {
      final fallback = playlistTemplates[optionIndex];
      final tracks = <AuraliaTrack>[];
      final playlistSeen = <String>{};

      for (var i = 0; i < trackGroups.length; i++) {
        final group = trackGroups[i];
        if (group.isEmpty) {
          continue;
        }

        for (
          var trackIndex = 0;
          trackIndex < stageCounts[i];
          trackIndex++
        ) {
          final offsets = _selectionOffsets[optionIndex % _selectionOffsets.length];
          final selected = _pickSpotifyTrack(
            group: group,
            playlistSeen: playlistSeen,
            sessionSeen: sessionSeen,
            startIndex:
                sessionOffset +
                contextOffset +
                optionIndex * 37 +
                i * 53 +
                trackIndex * 11 +
                offsets[trackIndex % offsets.length],
          );
          tracks.add(selected);
          sessionSeen.add(_trackKey(selected));
        }
      }

      if (tracks.length == 9) {
        options.add(
          AuraliaPlaylist(
            name: _generatedPlaylistName(
              mood: mood,
              optionIndex: optionIndex,
              seed: seed,
            ),
            sourceMood: mood,
            summary: fallback.summary,
            tracks: tracks,
          ),
        );
      }
    }

    return options.length == 8 ? options : const [];
  }

  AuraliaTrack _pickSpotifyTrack({
    required List<AuraliaTrack> group,
    required Set<String> playlistSeen,
    required Set<String> sessionSeen,
    required int startIndex,
  }) {
    for (var offset = 0; offset < group.length; offset++) {
      final track = group[(startIndex + offset) % group.length];
      final key = _trackKey(track);
      if (!playlistSeen.contains(key) && !sessionSeen.contains(key)) {
        playlistSeen.add(key);
        return track;
      }
    }

    for (var offset = 0; offset < group.length; offset++) {
      final track = group[(startIndex + offset) % group.length];
      final key = _trackKey(track);
      if (!playlistSeen.contains(key)) {
        playlistSeen.add(key);
        return track;
      }
    }

    for (var offset = 0; offset < group.length; offset++) {
      final track = group[(startIndex + offset) % group.length];
      final key = _trackKey(track);
      if (playlistSeen.add(key)) {
        return track;
      }
    }

    return group[startIndex % group.length];
  }

  List<AuraliaTrack> _uniqueTracks(List<AuraliaTrack> tracks) {
    final seen = <String>{};
    final unique = <AuraliaTrack>[];

    for (final track in tracks) {
      if (seen.add(_trackKey(track))) {
        unique.add(track);
      }
    }

    return unique;
  }

  String _trackKey(AuraliaTrack track) {
    return '${_normalizeTrackText(track.title)}-${_normalizeTrackText(track.artist)}';
  }

  String _normalizeTrackText(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  List<AuraliaTrack> _filterTracksForMoodStage({
    required AuraliaMood mood,
    required String stage,
    required List<AuraliaTrack> tracks,
  }) {
    if (!mood.isNegative) {
      return tracks;
    }

    final nonHype = tracks.where((track) => !_isHypeTrack(track)).toList();
    if (stage != 'Validation') {
      return nonHype.isEmpty ? tracks : nonHype;
    }

    final validationTracks = nonHype.where(_looksLikeValidationTrack).toList();
    if (validationTracks.length >= 6) {
      return validationTracks;
    }
    return nonHype.isEmpty ? tracks : nonHype;
  }

  bool _isHypeTrack(AuraliaTrack track) {
    final text = '${track.title} ${track.artist}'.toLowerCase();
    const hypeWords = [
      'happy',
      'dynamite',
      'firework',
      'shake it off',
      'uptown funk',
      'on top of the world',
      'high hopes',
      'party',
      'dance',
      'levitating',
      'blinding lights',
      'can\'t stop the feeling',
      'good life',
      'best day of my life',
    ];
    return hypeWords.any(text.contains);
  }

  bool _looksLikeValidationTrack(AuraliaTrack track) {
    final text = '${track.title} ${track.artist}'.toLowerCase();
    const validationWords = [
      'sad',
      'heartbreak',
      'drivers license',
      'someone like you',
      'all too well',
      'when i was your man',
      'let her go',
      'lose you',
      'traitor',
      'night we met',
      'lovely',
      'fix you',
      'yellow',
      'tears',
      'lonely',
      'hurt',
      'cry',
      'broken',
      'without you',
    ];
    return validationWords.any(text.contains);
  }

  int _generationSeed(
    AuraliaMood mood,
    PlaylistGenerationContext? context,
  ) {
    final now = DateTime.now();
    return Object.hash(
      mood.name,
      now.microsecondsSinceEpoch,
      context?.personalizationSeed ?? 0,
    ).abs();
  }

  List<AuraliaTrack> _personalizeTrackOrder(
    List<AuraliaTrack> tracks,
    PlaylistGenerationContext? context,
  ) {
    if (tracks.length < 2 || context == null) {
      return tracks;
    }

    final preferredArtists = {
      ...context.preferredArtists,
      ...context.positivelyRatedArtists,
    };
    final avoidedArtists = context.negativelyRatedArtists;
    final ordered = List<AuraliaTrack>.from(tracks);
    ordered.sort((a, b) {
      final aPreferred = preferredArtists.contains(a.artist.toLowerCase());
      final bPreferred = preferredArtists.contains(b.artist.toLowerCase());
      final aAvoided = avoidedArtists.contains(a.artist.toLowerCase());
      final bAvoided = avoidedArtists.contains(b.artist.toLowerCase());
      if (aAvoided != bAvoided) {
        return aAvoided ? 1 : -1;
      }
      if (aPreferred == bPreferred) {
        return 0;
      }
      return aPreferred ? -1 : 1;
    });
    return ordered;
  }

  List<_SpotifyStageQuery> _stageSearchPlanForMood(AuraliaMood mood) {
    final seenStages = <String>{};
    final stagePlan = <_SpotifyStageQuery>[];

    for (final query in _queryPlanForMood(mood)) {
      if (seenStages.add(query.stage)) {
        stagePlan.add(query);
      }
    }

    return stagePlan;
  }

  Future<List<AuraliaPlaylist>> _freshFallbackOptions(
    AuraliaMood mood,
    int seed,
  ) async {
    final options = List<AuraliaPlaylist>.from(
      await _fallback.generatePlaylistOptions(mood),
    );
    options.shuffle(Random(seed));
    return options;
  }

  Future<AuraliaPlaylist?> _generateSpotifyPlaylist({
    required String name,
    required String summary,
    required AuraliaMood mood,
    required String accessToken,
    required int optionIndex,
  }) async {
    final plan = _queryPlanForMood(mood);
    final tracks = <AuraliaTrack>[];

    final trackResults = await Future.wait(
      List.generate(plan.length, (i) {
        final stage = plan[i];
        return _searchTrack(
          query: stage.query,
          mood: mood,
          stage: stage.stage,
          valence: stage.valence,
          energy: stage.energy,
          accessToken: accessToken,
          pickIndex: (optionIndex + i) % 5,
        );
      }),
    ).timeout(const Duration(seconds: 8), onTimeout: () => <AuraliaTrack?>[]);

    for (final track in trackResults) {
      if (track != null && !tracks.any((existing) => existing.id == track.id)) {
        tracks.add(track);
      }
    }

    if (tracks.length < 6) {
      return null;
    }

    return AuraliaPlaylist(
      name: name,
      sourceMood: mood,
      summary: summary,
      tracks: tracks,
    );
  }

  Future<AuraliaTrack?> _searchTrack({
    required String query,
    required AuraliaMood mood,
    required String stage,
    required double valence,
    required double energy,
    required String accessToken,
    required int pickIndex,
  }) async {
    final tracks = await _searchTracks(
      query: query,
      mood: mood,
      stage: stage,
      valence: valence,
      energy: energy,
      accessToken: accessToken,
    );

    if (tracks.isEmpty) {
      return null;
    }

    return tracks[pickIndex.clamp(0, tracks.length - 1)];
  }

  Future<List<AuraliaTrack>> _searchTracks({
    required String query,
    required AuraliaMood mood,
    required String stage,
    required double valence,
    required double energy,
    required String accessToken,
  }) async {
    final constrainedQuery = 'english $query year:2021-2026';
    final http.Response response;
    try {
      response = AppConfig.spotifyBackendUrl.isNotEmpty
          ? await _client
                .get(_backendSearchUri(query, mood))
                .timeout(const Duration(seconds: 6))
          : await _client
                .get(
                  Uri.https('api.spotify.com', '/v1/search', {
                    'q': constrainedQuery,
                    'type': 'track',
                    'limit': '50',
                  }),
                  headers: {'Authorization': 'Bearer $accessToken'},
                )
                .timeout(const Duration(seconds: 5));
    } catch (_) {
      return const [];
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (AppConfig.spotifyOnly && body['auralia_source'] == 'fallback') {
      return const [];
    }
    final tracks = body['tracks'] as Map<String, dynamic>?;
    final items = tracks?['items'] as List<dynamic>? ?? [];

    if (items.isEmpty) {
      return const [];
    }

    return items
        .whereType<Map<String, dynamic>>()
        .where(
          (item) =>
              AppConfig.spotifyBackendUrl.isNotEmpty ||
              _isAllowedReleaseYear(item),
        )
        .map(
          (item) => AuraliaTrack.fromSpotifyJson(
            item,
            stage: stage,
            valence: valence,
            energy: energy,
          ),
        )
        .toList();
  }

  bool _isAllowedReleaseYear(Map<String, dynamic> item) {
    final album = item['album'] as Map<String, dynamic>?;
    final releaseDate = album?['release_date']?.toString() ?? '';
    final year = int.tryParse(
      releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '',
    );
    return year != null && year >= 2021 && year <= 2026;
  }

  Uri _backendSearchUri(String query, AuraliaMood mood) {
    final baseUri = Uri.parse(AppConfig.spotifyBackendUrl);
    final searchPath = [
      baseUri.path.replaceAll(RegExp(r'/+$'), ''),
      'spotify',
      'search',
    ].where((part) => part.isNotEmpty).join('/');

    return baseUri.replace(
      path: '/$searchPath',
      queryParameters: {
        'q': query,
        'mood': mood.name,
        'allow_fallback': AppConfig.spotifyOnly ? 'false' : 'true',
      },
    );
  }

  Future<String?> _resolveAccessToken() async {
    if (AppConfig.spotifyBackendUrl.isNotEmpty) {
      return 'backend-managed';
    }

    if (AppConfig.spotifyAccessToken.isNotEmpty) {
      return AppConfig.spotifyAccessToken;
    }

    if (AppConfig.spotifyBackendUrl.isEmpty) {
      return null;
    }

    final expiresAt = _tokenExpiresAt;
    if (_cachedAccessToken != null &&
        expiresAt != null &&
        DateTime.now().isBefore(expiresAt)) {
      return _cachedAccessToken;
    }

    try {
      final baseUri = Uri.parse(AppConfig.spotifyBackendUrl);
      final tokenPath = [
        baseUri.path.replaceAll(RegExp(r'/+$'), ''),
        'spotify',
        'token',
      ].where((part) => part.isNotEmpty).join('/');
      final tokenUri = baseUri.replace(path: '/$tokenPath');
      final response = await _client
          .post(tokenUri)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final token = body['access_token']?.toString();
      final expiresIn = body['expires_in'] as int? ?? 3600;

      if (token == null || token.isEmpty) {
        return null;
      }

      _cachedAccessToken = token;
      _tokenExpiresAt = DateTime.now().add(Duration(seconds: expiresIn - 60));
      return token;
    } catch (_) {
      return null;
    }
  }

  List<_SpotifyStageQuery> _queryPlanForMood(AuraliaMood mood) {
    switch (mood) {
      case AuraliaMood.sad:
        return const [
          _SpotifyStageQuery(
            'sad heartbreak ballads pop',
            'Validation',
            0.25,
            0.28,
          ),
          _SpotifyStageQuery(
            'emotional sad pop songs',
            'Validation',
            0.28,
            0.30,
          ),
          _SpotifyStageQuery('sad acoustic pop songs', 'Validation', 0.30, 0.32),
          _SpotifyStageQuery('healing soft pop songs', 'Transition', 0.46, 0.40),
          _SpotifyStageQuery('hopeful acoustic pop', 'Transition', 0.52, 0.44),
          _SpotifyStageQuery('warm chill pop songs', 'Transition', 0.58, 0.48),
          _SpotifyStageQuery('uplifting pop songs', 'Elevation', 0.72, 0.58),
          _SpotifyStageQuery('feel good pop hits', 'Elevation', 0.78, 0.62),
          _SpotifyStageQuery(
            'positive acoustic pop hits',
            'Elevation',
            0.84,
            0.66,
          ),
        ];
      case AuraliaMood.stressed:
        return const [
          _SpotifyStageQuery('calm acoustic pop songs', 'Validation', 0.34, 0.55),
          _SpotifyStageQuery('soft relaxing pop songs', 'Validation', 0.38, 0.52),
          _SpotifyStageQuery('gentle chill pop songs', 'Validation', 0.42, 0.50),
          _SpotifyStageQuery('relaxing pop songs', 'Transition', 0.52, 0.45),
          _SpotifyStageQuery('calm focus pop songs', 'Transition', 0.58, 0.42),
          _SpotifyStageQuery('peaceful acoustic pop', 'Transition', 0.64, 0.45),
          _SpotifyStageQuery(
            'positive focus pop hits',
            'Elevation',
            0.74,
            0.56,
          ),
          _SpotifyStageQuery('upbeat study hits', 'Elevation', 0.80, 0.60),
          _SpotifyStageQuery(
            'confidence boost pop hits',
            'Elevation',
            0.86,
            0.66,
          ),
        ];
      case AuraliaMood.neutral:
        return const [
          _SpotifyStageQuery('chill pop hits', 'Validation', 0.5, 0.42),
          _SpotifyStageQuery(
            'easy listening pop hits',
            'Validation',
            0.52,
            0.42,
          ),
          _SpotifyStageQuery('soft pop songs', 'Validation', 0.54, 0.44),
          _SpotifyStageQuery('light pop hits', 'Transition', 0.62, 0.48),
          _SpotifyStageQuery('warm chill hits', 'Transition', 0.66, 0.50),
          _SpotifyStageQuery('study pop hits', 'Transition', 0.70, 0.52),
          _SpotifyStageQuery(
            'feel good acoustic hits',
            'Elevation',
            0.76,
            0.56,
          ),
          _SpotifyStageQuery('positive pop hits', 'Elevation', 0.80, 0.60),
          _SpotifyStageQuery('bright indie pop hits', 'Elevation', 0.84, 0.64),
        ];
      case AuraliaMood.happy:
        return const [
          _SpotifyStageQuery('happy pop hits', 'Validation', 0.78, 0.64),
          _SpotifyStageQuery('sunny pop hits', 'Validation', 0.80, 0.66),
          _SpotifyStageQuery('feel good pop hits', 'Validation', 0.82, 0.68),
          _SpotifyStageQuery('good vibes pop hits', 'Transition', 0.84, 0.70),
          _SpotifyStageQuery('positive mood hits', 'Transition', 0.86, 0.72),
          _SpotifyStageQuery('bright upbeat hits', 'Transition', 0.88, 0.74),
          _SpotifyStageQuery('dance pop hits', 'Elevation', 0.90, 0.76),
          _SpotifyStageQuery('viral happy songs', 'Elevation', 0.92, 0.78),
          _SpotifyStageQuery('party pop hits', 'Elevation', 0.94, 0.80),
        ];
      case AuraliaMood.motivated:
        return const [
          _SpotifyStageQuery('motivational pop hits', 'Validation', 0.82, 0.78),
          _SpotifyStageQuery('study motivation hits', 'Validation', 0.84, 0.80),
          _SpotifyStageQuery('productive pop hits', 'Validation', 0.86, 0.82),
          _SpotifyStageQuery('focus pop hits', 'Transition', 0.88, 0.84),
          _SpotifyStageQuery('confidence pop hits', 'Transition', 0.90, 0.86),
          _SpotifyStageQuery('focus energy hits', 'Transition', 0.91, 0.87),
          _SpotifyStageQuery(
            'workout motivation hits',
            'Elevation',
            0.92,
            0.88,
          ),
          _SpotifyStageQuery('powerful upbeat hits', 'Elevation', 0.94, 0.90),
          _SpotifyStageQuery('finish strong pop hits', 'Elevation', 0.96, 0.92),
        ];
    }
  }

  String _nameForMood(AuraliaMood mood) {
    switch (mood) {
      case AuraliaMood.sad:
        return 'Spotify Gentle Lift Sequence';
      case AuraliaMood.stressed:
        return 'Spotify Stress Release Flow';
      case AuraliaMood.neutral:
        return 'Spotify Balanced Study Drift';
      case AuraliaMood.happy:
        return 'Spotify Positive Mood Keeper';
      case AuraliaMood.motivated:
        return 'Spotify Momentum Builder';
    }
  }

  String _summaryForMood(AuraliaMood mood) {
    if (mood.isNegative) {
      return 'Spotify tracks arranged from emotional validation into a healthier elevated state.';
    }
    return 'Spotify tracks arranged to maintain and strengthen your current positive mood.';
  }

  double _stageValence(AuraliaMood mood, int index) {
    final base = switch (mood) {
      AuraliaMood.sad => 0.25,
      AuraliaMood.stressed => 0.34,
      AuraliaMood.neutral => 0.50,
      AuraliaMood.happy => 0.78,
      AuraliaMood.motivated => 0.82,
    };
    return (base + (index * 0.07)).clamp(0.0, 1.0).toDouble();
  }

  double _stageEnergy(AuraliaMood mood, int index) {
    final base = switch (mood) {
      AuraliaMood.sad => 0.28,
      AuraliaMood.stressed => 0.50,
      AuraliaMood.neutral => 0.42,
      AuraliaMood.happy => 0.64,
      AuraliaMood.motivated => 0.78,
    };
    return (base + (index * 0.04)).clamp(0.0, 1.0).toDouble();
  }

  List<List<_CuratedSpotifySong>> _curatedCatalogForMood(AuraliaMood mood) {
    switch (mood) {
      case AuraliaMood.sad:
        return const [
          [
            _CuratedSpotifySong('5wANPM4fQCJwkGd4rN57mH', 'drivers license', 'Olivia Rodrigo'),
            _CuratedSpotifySong('4kflIGfjdZJW4ot2ioixTB', 'Someone Like You', 'Adele'),
            _CuratedSpotifySong('3hRV0jL3vUpRrcy398teAU', 'The Night We Met', 'Lord Huron'),
            _CuratedSpotifySong('0u2P5u6lvoDfwTYjAADbn4', 'lovely', 'Billie Eilish, Khalid'),
            _CuratedSpotifySong('7LVHVU3tWfcxj5aiPFEW4Q', 'Fix You', 'Coldplay'),
            _CuratedSpotifySong('3AJwUDP919kvQ9QcozQPxg', 'Yellow', 'Coldplay'),
          ],
          [
            _CuratedSpotifySong('6lanRgr6wXibZr8KgzXxBl', 'A Thousand Years', 'Christina Perri'),
            _CuratedSpotifySong('1HNkqx9Ahdgi1Ixy2xkKkL', 'Photograph', 'Ed Sheeran'),
            _CuratedSpotifySong('7nUlyv5E5Pz8dsbUd9Y0Ec', 'The Climb', 'Miley Cyrus'),
            _CuratedSpotifySong('5uCax9HTNlzGybIStD3vDh', "Say You Won't Let Go", 'James Arthur'),
            _CuratedSpotifySong('2b8fOow8UzyDFAE27YhOZM', 'Memories', 'Maroon 5'),
            _CuratedSpotifySong('3JvrhDOgAt6p7K8mDyZwRd', 'Riptide', 'Vance Joy'),
          ],
          [
            _CuratedSpotifySong('213x4gsFDm04hSqIUkg88w', 'On Top Of The World', 'Imagine Dragons'),
            _CuratedSpotifySong('6OtCIsQZ64Vs1EbzztvAv4', 'Good Life', 'OneRepublic'),
            _CuratedSpotifySong('4lCv7b86sLynZbXhfScfm2', 'Firework', 'Katy Perry'),
            _CuratedSpotifySong('0t1kP63rueHleOhQkYSXFY', 'Dynamite', 'BTS'),
            _CuratedSpotifySong('60nZcImufyMA1MKQY3dcCH', 'Happy', 'Pharrell Williams'),
            _CuratedSpotifySong('1p80LdxRV74UKvL8gnD7ky', 'Shake It Off', 'Taylor Swift'),
          ],
        ];
      case AuraliaMood.stressed:
        return const [
          [
            _CuratedSpotifySong('1HNkqx9Ahdgi1Ixy2xkKkL', 'Photograph', 'Ed Sheeran'),
            _CuratedSpotifySong('0T5iIrXA4p5GsubkhuBIKV', 'Until I Found You', 'Stephen Sanchez'),
            _CuratedSpotifySong('6lanRgr6wXibZr8KgzXxBl', 'A Thousand Years', 'Christina Perri'),
            _CuratedSpotifySong('1RMJOxR6GRPsBHL8qeC2ux', 'Best Part', 'Daniel Caesar, H.E.R.'),
            _CuratedSpotifySong('3JvrhDOgAt6p7K8mDyZwRd', 'Riptide', 'Vance Joy'),
            _CuratedSpotifySong('2b8fOow8UzyDFAE27YhOZM', 'Memories', 'Maroon 5'),
          ],
          [
            _CuratedSpotifySong('6UelLqGlWMcVH1E5c4H7lY', 'Watermelon Sugar', 'Harry Styles'),
            _CuratedSpotifySong('6OtCIsQZ64Vs1EbzztvAv4', 'Good Life', 'OneRepublic'),
            _CuratedSpotifySong('6OtCIsQZ64Vs1EbzztvAv4', 'Good Life', 'OneRepublic'),
            _CuratedSpotifySong('7l1qvxWjxcKpB9PCtBuTbU', 'Count on Me', 'Bruno Mars'),
            _CuratedSpotifySong('0RiRZpuVRbi7oqRdSMwhQY', 'Sunflower', 'Post Malone, Swae Lee'),
            _CuratedSpotifySong('02MWAaffLxlfxAUY7c5dvx', 'Heat Waves', 'Glass Animals'),
          ],
          [
            _CuratedSpotifySong('213x4gsFDm04hSqIUkg88w', 'On Top Of The World', 'Imagine Dragons'),
            _CuratedSpotifySong('60nZcImufyMA1MKQY3dcCH', 'Happy', 'Pharrell Williams'),
            _CuratedSpotifySong('463CkQjx2Zk1yXoBuierM9', 'Levitating', 'Dua Lipa'),
            _CuratedSpotifySong('0t1kP63rueHleOhQkYSXFY', 'Dynamite', 'BTS'),
            _CuratedSpotifySong('1p80LdxRV74UKvL8gnD7ky', 'Shake It Off', 'Taylor Swift'),
            _CuratedSpotifySong('0VjIjW4GlUZAMYd2vXMi3b', 'Blinding Lights', 'The Weeknd'),
          ],
        ];
      case AuraliaMood.neutral:
        return const [
          [
            _CuratedSpotifySong('1HNkqx9Ahdgi1Ixy2xkKkL', 'Photograph', 'Ed Sheeran'),
            _CuratedSpotifySong('7l1qvxWjxcKpB9PCtBuTbU', 'Count on Me', 'Bruno Mars'),
            _CuratedSpotifySong('3JvrhDOgAt6p7K8mDyZwRd', 'Riptide', 'Vance Joy'),
            _CuratedSpotifySong('6UelLqGlWMcVH1E5c4H7lY', 'Watermelon Sugar', 'Harry Styles'),
            _CuratedSpotifySong('0RiRZpuVRbi7oqRdSMwhQY', 'Sunflower', 'Post Malone, Swae Lee'),
            _CuratedSpotifySong('2b8fOow8UzyDFAE27YhOZM', 'Memories', 'Maroon 5'),
          ],
          [
            _CuratedSpotifySong('6OtCIsQZ64Vs1EbzztvAv4', 'Good Life', 'OneRepublic'),
            _CuratedSpotifySong('0yLdNVWF3Srea0uzk55zFn', 'Flowers', 'Miley Cyrus'),
            _CuratedSpotifySong('4LRPiXqCikLlN15c3yImP7', 'As It Was', 'Harry Styles'),
            _CuratedSpotifySong('02MWAaffLxlfxAUY7c5dvx', 'Heat Waves', 'Glass Animals'),
            _CuratedSpotifySong('3rmo8F54jFF8OgYsqTxm5d', 'Bad Habits', 'Ed Sheeran'),
            _CuratedSpotifySong('50nfwKoDiSYg8zOCREWAm5', 'Shivers', 'Ed Sheeran'),
          ],
          [
            _CuratedSpotifySong('463CkQjx2Zk1yXoBuierM9', 'Levitating', 'Dua Lipa'),
            _CuratedSpotifySong('1p80LdxRV74UKvL8gnD7ky', 'Shake It Off', 'Taylor Swift'),
            _CuratedSpotifySong('0t1kP63rueHleOhQkYSXFY', 'Dynamite', 'BTS'),
            _CuratedSpotifySong('0VjIjW4GlUZAMYd2vXMi3b', 'Blinding Lights', 'The Weeknd'),
            _CuratedSpotifySong('6JV2JOEocMgcZxYSZelKcc', "Can't Stop the Feeling!", 'Justin Timberlake'),
            _CuratedSpotifySong('32OlwWuMpZ6b0aN2RZOeMS', 'Uptown Funk', 'Mark Ronson, Bruno Mars'),
          ],
        ];
      case AuraliaMood.happy:
        return const [
          [
            _CuratedSpotifySong('60nZcImufyMA1MKQY3dcCH', 'Happy', 'Pharrell Williams'),
            _CuratedSpotifySong('6OtCIsQZ64Vs1EbzztvAv4', 'Good Life', 'OneRepublic'),
            _CuratedSpotifySong('6UelLqGlWMcVH1E5c4H7lY', 'Watermelon Sugar', 'Harry Styles'),
            _CuratedSpotifySong('0RiRZpuVRbi7oqRdSMwhQY', 'Sunflower', 'Post Malone, Swae Lee'),
            _CuratedSpotifySong('0yLdNVWF3Srea0uzk55zFn', 'Flowers', 'Miley Cyrus'),
            _CuratedSpotifySong('4LRPiXqCikLlN15c3yImP7', 'As It Was', 'Harry Styles'),
          ],
          [
            _CuratedSpotifySong('463CkQjx2Zk1yXoBuierM9', 'Levitating', 'Dua Lipa'),
            _CuratedSpotifySong('0VjIjW4GlUZAMYd2vXMi3b', 'Blinding Lights', 'The Weeknd'),
            _CuratedSpotifySong('50nfwKoDiSYg8zOCREWAm5', 'Shivers', 'Ed Sheeran'),
            _CuratedSpotifySong('3rmo8F54jFF8OgYsqTxm5d', 'Bad Habits', 'Ed Sheeran'),
            _CuratedSpotifySong('1p80LdxRV74UKvL8gnD7ky', 'Shake It Off', 'Taylor Swift'),
            _CuratedSpotifySong('4ZtFanR9U6ndgddUvNcjcG', 'good 4 u', 'Olivia Rodrigo'),
          ],
          [
            _CuratedSpotifySong('32OlwWuMpZ6b0aN2RZOeMS', 'Uptown Funk', 'Mark Ronson, Bruno Mars'),
            _CuratedSpotifySong('6JV2JOEocMgcZxYSZelKcc', "Can't Stop the Feeling!", 'Justin Timberlake'),
            _CuratedSpotifySong('0t1kP63rueHleOhQkYSXFY', 'Dynamite', 'BTS'),
            _CuratedSpotifySong('6v3KW9xbzN5yKLt9YKDYA2', 'Senorita', 'Shawn Mendes, Camila Cabello'),
            _CuratedSpotifySong('7qiZfU4dY1lWllzX7mPBI3', 'Shape of You', 'Ed Sheeran'),
            _CuratedSpotifySong('27tNWlhdAryQY04Gb2ZhUI', 'Roar', 'Katy Perry'),
          ],
        ];
      case AuraliaMood.motivated:
        return const [
          [
            _CuratedSpotifySong('0pqnGHJpmpxLKifKRmU6WP', 'Believer', 'Imagine Dragons'),
            _CuratedSpotifySong('1yvMUkIOTeUNtNWlWRgANS', 'Unstoppable', 'Sia'),
            _CuratedSpotifySong('1rqqCSm0Qe4I9rUvWncaom', 'High Hopes', 'Panic! At The Disco'),
            _CuratedSpotifySong('1X1DWw2pcNZ8zSub3uhlNz', 'Hall of Fame', 'The Script, will.i.am'),
            _CuratedSpotifySong('213x4gsFDm04hSqIUkg88w', 'On Top Of The World', 'Imagine Dragons'),
            _CuratedSpotifySong('6OtCIsQZ64Vs1EbzztvAv4', 'Good Life', 'OneRepublic'),
          ],
          [
            _CuratedSpotifySong('3bidbhpOYeV4knp8AIu8Xn', "Can't Hold Us", 'Macklemore & Ryan Lewis'),
            _CuratedSpotifySong('0ct6r3EGTcMLPtrXHDvVjc', 'The Nights', 'Avicii'),
            _CuratedSpotifySong('2dOTkLZFbpNXrhc24CnTFd', 'Titanium', 'David Guetta, Sia'),
            _CuratedSpotifySong('0VjIjW4GlUZAMYd2vXMi3b', 'Blinding Lights', 'The Weeknd'),
            _CuratedSpotifySong('50nfwKoDiSYg8zOCREWAm5', 'Shivers', 'Ed Sheeran'),
            _CuratedSpotifySong('4ZtFanR9U6ndgddUvNcjcG', 'good 4 u', 'Olivia Rodrigo'),
          ],
          [
            _CuratedSpotifySong('0t1kP63rueHleOhQkYSXFY', 'Dynamite', 'BTS'),
            _CuratedSpotifySong('32OlwWuMpZ6b0aN2RZOeMS', 'Uptown Funk', 'Mark Ronson, Bruno Mars'),
            _CuratedSpotifySong('6JV2JOEocMgcZxYSZelKcc', "Can't Stop the Feeling!", 'Justin Timberlake'),
            _CuratedSpotifySong('7qiZfU4dY1lWllzX7mPBI3', 'Shape of You', 'Ed Sheeran'),
            _CuratedSpotifySong('27tNWlhdAryQY04Gb2ZhUI', 'Roar', 'Katy Perry'),
            _CuratedSpotifySong('1p80LdxRV74UKvL8gnD7ky', 'Shake It Off', 'Taylor Swift'),
          ],
        ];
    }
  }
}

class _SpotifyStageQuery {
  const _SpotifyStageQuery(this.query, this.stage, this.valence, this.energy);

  final String query;
  final String stage;
  final double valence;
  final double energy;
}

class _CuratedSpotifySong {
  const _CuratedSpotifySong(this.id, this.title, this.artist);

  final String id;
  final String title;
  final String artist;
}
