import '../models/playlist.dart';

abstract class PlaylistRepository {
  Future<List<AuraliaPlaylist>> loadSavedPlaylists(String userId);

  Future<List<AuraliaPlaylist>> loadFavoritePlaylists(String userId);

  Future<int> savePlaylist({
    required String userId,
    required String? moodId,
    required AuraliaPlaylist playlist,
  });

  Future<void> setFavorite({
    required String userId,
    required int playlistId,
    required bool liked,
  });
}

class LocalPlaylistRepository implements PlaylistRepository {
  int _nextPlaylistId = 1;
  final Map<int, AuraliaPlaylist> _playlists = {};
  final Set<int> _favoriteIds = {};

  @override
  Future<List<AuraliaPlaylist>> loadSavedPlaylists(String userId) async {
    return _playlists.entries
        .map((entry) => entry.value.copyWithDatabaseId(entry.key))
        .toList();
  }

  @override
  Future<List<AuraliaPlaylist>> loadFavoritePlaylists(String userId) async {
    return _favoriteIds
        .where(_playlists.containsKey)
        .map((id) => _playlists[id]!.copyWithDatabaseId(id))
        .toList();
  }

  @override
  Future<int> savePlaylist({
    required String userId,
    required String? moodId,
    required AuraliaPlaylist playlist,
  }) async {
    final id = _nextPlaylistId++;
    _playlists[id] = playlist.copyWithDatabaseId(id);
    return id;
  }

  @override
  Future<void> setFavorite({
    required String userId,
    required int playlistId,
    required bool liked,
  }) async {
    if (liked) {
      _favoriteIds.add(playlistId);
    } else {
      _favoriteIds.remove(playlistId);
    }
  }
}
