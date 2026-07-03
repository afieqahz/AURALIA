import '../models/mood.dart';
import '../models/playlist.dart';
import 'auralia_recommendation_service.dart';

abstract class PlaylistService {
  Future<AuraliaPlaylist> generatePlaylist(AuraliaMood mood);

  Future<List<AuraliaPlaylist>> generatePlaylistOptions(
    AuraliaMood mood, {
    PlaylistGenerationContext? context,
  });
}

class PlaylistGenerationContext {
  const PlaylistGenerationContext({
    required this.userId,
    this.favoritePlaylists = const [],
    this.savedPlaylists = const [],
    this.moodHistory = const [],
  });

  final String userId;
  final List<AuraliaPlaylist> favoritePlaylists;
  final List<AuraliaPlaylist> savedPlaylists;
  final List<MoodEntry> moodHistory;

  int get personalizationSeed {
    var hash = userId.hashCode;

    for (final playlist in favoritePlaylists.take(5)) {
      hash = Object.hash(hash, playlist.name, playlist.sourceMood.name);
      for (final track in playlist.tracks.take(3)) {
        hash = Object.hash(hash, track.title, track.artist);
      }
    }

    for (final playlist in savedPlaylists.take(5)) {
      hash = Object.hash(hash, playlist.name, playlist.sourceMood.name);
    }

    for (final entry in moodHistory.take(7)) {
      hash = Object.hash(
        hash,
        entry.mood.name,
        entry.checkInType.name,
        entry.helpfulness?.name,
        entry.playlistName,
      );
    }

    return hash.abs();
  }

  Set<String> get preferredArtists {
    final artists = <String>{};
    for (final playlist in [...favoritePlaylists, ...savedPlaylists]) {
      for (final track in playlist.tracks) {
        artists.add(track.artist.toLowerCase());
      }
    }
    return artists;
  }

  Set<String> get positivelyRatedArtists =>
      _artistsForFeedback(const {
        ListeningHelpfulness.yes,
        ListeningHelpfulness.aLittle,
      });

  Set<String> get negativelyRatedArtists =>
      _artistsForFeedback(const {ListeningHelpfulness.no});

  Set<String> _artistsForFeedback(Set<ListeningHelpfulness> ratings) {
    final playlistNames = moodHistory
        .where(
          (entry) =>
              entry.checkInType == MoodCheckInType.afterListening &&
              entry.helpfulness != null &&
              ratings.contains(entry.helpfulness) &&
              entry.playlistName != null,
        )
        .map((entry) => entry.playlistName!.toLowerCase())
        .toSet();
    final artists = <String>{};
    for (final playlist in [...favoritePlaylists, ...savedPlaylists]) {
      if (!playlistNames.contains(playlist.name.toLowerCase())) {
        continue;
      }
      for (final track in playlist.tracks) {
        artists.add(track.artist.toLowerCase());
      }
    }
    return artists;
  }

  ListeningHelpfulness? feedbackForMood(AuraliaMood mood) {
    for (var index = moodHistory.length - 1; index >= 0; index--) {
      final entry = moodHistory[index];
      if (entry.checkInType != MoodCheckInType.afterListening ||
          entry.helpfulness == null) {
        continue;
      }

      for (var beforeIndex = index - 1; beforeIndex >= 0; beforeIndex--) {
        final before = moodHistory[beforeIndex];
        if (before.checkInType == MoodCheckInType.beforeListening) {
          if (before.mood == mood) {
            return entry.helpfulness;
          }
          break;
        }
      }
    }
    return null;
  }

  List<int> stageCountsForMood(AuraliaMood mood) {
    return switch (feedbackForMood(mood)) {
      ListeningHelpfulness.aLittle => const [3, 4, 2],
      ListeningHelpfulness.no => const [4, 3, 2],
      _ => const [3, 3, 3],
    };
  }
}

class LocalPlaylistService implements PlaylistService {
  const LocalPlaylistService({
    this._recommendationService = const AuraliaRecommendationService(),
  });

  final AuraliaRecommendationService _recommendationService;

  @override
  Future<AuraliaPlaylist> generatePlaylist(AuraliaMood mood) async {
    return _recommendationService.generatePlaylist(mood);
  }

  @override
  Future<List<AuraliaPlaylist>> generatePlaylistOptions(
    AuraliaMood mood, {
    PlaylistGenerationContext? context,
  }) async {
    return _recommendationService.generatePlaylistOptions(mood);
  }
}