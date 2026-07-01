import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/playlist.dart';

class SpotifyTrackDetailsService {
  SpotifyTrackDetailsService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<AuraliaPlaylist>> enrichPlaylists(
    List<AuraliaPlaylist> playlists,
  ) async {
    if (AppConfig.spotifyBackendUrl.isEmpty || playlists.isEmpty) {
      return playlists;
    }

    final ids = playlists
        .expand((playlist) => playlist.tracks)
        .where(
          (track) =>
              track.imageUrl == null ||
              track.imageUrl!.isEmpty ||
              track.durationMs == null,
        )
        .map((track) => track.id)
        .whereType<String>()
        .where((id) => id.isNotEmpty && !id.startsWith('fallback-'))
        .toSet()
        .toList();

    if (ids.isEmpty) {
      return playlists;
    }

    final spotifyById = await _fetchTracksById(ids);
    final artworkById = await _fetchOembedArtworkById(
      ids.where((id) {
        final spotifyTrack = spotifyById[id];
        final album = spotifyTrack?['album'] as Map<String, dynamic>?;
        final images = album?['images'] as List<dynamic>? ?? [];
        return images.isEmpty;
      }).toList(),
    );
    if (spotifyById.isEmpty && artworkById.isEmpty) {
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
                .map(
                  (track) => _mergeTrackDetails(
                    track,
                    spotifyById,
                    artworkById,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  Future<AuraliaPlaylist> enrichPlaylist(AuraliaPlaylist playlist) async {
    final playlists = await enrichPlaylists([playlist]);
    return playlists.isEmpty ? playlist : playlists.first;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchTracksById(
    List<String> ids,
  ) async {
    final spotifyById = <String, Map<String, dynamic>>{};
    final baseUri = Uri.parse(AppConfig.spotifyBackendUrl);
    final tracksPath = [
      baseUri.path.replaceAll(RegExp(r'/+$'), ''),
      'spotify',
      'tracks',
    ].where((part) => part.isNotEmpty).join('/');

    final batches = <List<String>>[
      for (var start = 0; start < ids.length; start += 50)
        ids.skip(start).take(50).toList(),
    ];

    final responses = await Future.wait(
      batches.map((batch) async {
        try {
          return await _client
              .get(
                baseUri.replace(
                  path: '/$tracksPath',
                  queryParameters: {'ids': batch.join(',')},
                ),
              )
              .timeout(const Duration(seconds: 6));
        } catch (_) {
          return null;
        }
      }),
    );

    for (final response in responses.whereType<http.Response>()) {
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

    return spotifyById;
  }

  Future<Map<String, String>> _fetchOembedArtworkById(List<String> ids) async {
    final artworkById = <String, String>{};
    final uniqueIds = ids
        .where((id) => id.isNotEmpty && !id.startsWith('fallback-'))
        .toSet()
        .take(50)
        .toList();

    for (var start = 0; start < uniqueIds.length; start += 10) {
      final batch = uniqueIds.skip(start).take(10).toList();
      final results = await Future.wait(
        batch.map((id) async {
          try {
            final response = await _client
                .get(
                  Uri.https('open.spotify.com', '/oembed', {
                    'url': 'https://open.spotify.com/track/$id',
                  }),
                )
                .timeout(const Duration(seconds: 3));
            if (response.statusCode < 200 || response.statusCode >= 300) {
              return null;
            }

            final body = jsonDecode(response.body) as Map<String, dynamic>;
            final thumbnailUrl = body['thumbnail_url']?.toString();
            if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
              return null;
            }
            return MapEntry(id, thumbnailUrl);
          } catch (_) {
            return null;
          }
        }),
      );

      for (final result in results.whereType<MapEntry<String, String>>()) {
        artworkById[result.key] = result.value;
      }
    }

    return artworkById;
  }

  AuraliaTrack _mergeTrackDetails(
    AuraliaTrack track,
    Map<String, Map<String, dynamic>> spotifyById,
    Map<String, String> artworkById,
  ) {
    final id = track.id;
    final spotifyTrack = id == null ? null : spotifyById[id];
    if (spotifyTrack == null && (id == null || artworkById[id] == null)) {
      return track;
    }

    final album = spotifyTrack?['album'] as Map<String, dynamic>?;
    final images = album?['images'] as List<dynamic>? ?? [];
    final image = images.isEmpty ? null : images.first as Map<String, dynamic>;
    final externalUrls =
        spotifyTrack?['external_urls'] as Map<String, dynamic>?;
    final oembedImage = id == null ? null : artworkById[id];

    return AuraliaTrack(
      id: track.id,
      title: spotifyTrack?['name']?.toString() ?? track.title,
      artist: spotifyTrack == null ? track.artist : _artistsFrom(spotifyTrack),
      stage: track.stage,
      valence: track.valence,
      energy: track.energy,
      previewUrl: spotifyTrack?['preview_url']?.toString() ?? track.previewUrl,
      imageUrl: image?['url']?.toString() ?? oembedImage ?? track.imageUrl,
      externalUrl: externalUrls?['spotify']?.toString() ?? track.externalUrl,
      durationMs: _toInt(spotifyTrack?['duration_ms']) ?? track.durationMs,
    );
  }

  String _artistsFrom(Map<String, dynamic> spotifyTrack) {
    final artists = (spotifyTrack['artists'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((artist) => artist['name']?.toString())
        .whereType<String>()
        .join(', ');
    return artists.isEmpty ? 'Unknown artist' : artists;
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
}
