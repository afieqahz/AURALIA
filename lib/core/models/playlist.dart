import 'mood.dart';

class AuraliaTrack {
  const AuraliaTrack({
    this.id,
    required this.title,
    required this.artist,
    required this.stage,
    required this.valence,
    required this.energy,
    this.previewUrl,
    this.imageUrl,
    this.externalUrl,
    this.durationMs,
  });

  final String? id;
  final String title;
  final String artist;
  final String stage;
  final double valence;
  final double energy;
  final String? previewUrl;
  final String? imageUrl;
  final String? externalUrl;
  final int? durationMs;

  Map<String, dynamic> toJson({int? playlistId}) {
    final json = <String, dynamic>{
      'title': title,
      'artist': artist,
      'stage': stage,
      'valence': valence,
      'energy': energy,
      'preview_url': previewUrl,
      'image_url': imageUrl,
      'external_url': externalUrl,
      'duration_ms': durationMs,
    };
    if (id != null) {
      json['track_id'] = id;
    }
    if (playlistId != null) {
      json['playlist_id'] = playlistId;
    }
    return json;
  }

  factory AuraliaTrack.fromSpotifyJson(
    Map<String, dynamic> json, {
    required String stage,
    required double valence,
    required double energy,
  }) {
    final artists = (json['artists'] as List<dynamic>? ?? [])
        .map((artist) => (artist as Map<String, dynamic>)['name']?.toString())
        .whereType<String>()
        .join(', ');
    final album = json['album'] as Map<String, dynamic>?;
    final images = album?['images'] as List<dynamic>? ?? [];
    final image = images.isEmpty ? null : images.first as Map<String, dynamic>;
    final externalUrls = json['external_urls'] as Map<String, dynamic>?;

    return AuraliaTrack(
      id: json['id']?.toString(),
      title: json['name']?.toString() ?? 'Unknown track',
      artist: artists.isEmpty ? 'Unknown artist' : artists,
      stage: stage,
      valence: valence,
      energy: energy,
      previewUrl: json['preview_url']?.toString(),
      imageUrl: image?['url']?.toString(),
      externalUrl: externalUrls?['spotify']?.toString(),
      durationMs: _toInt(json['duration_ms']),
    );
  }

  factory AuraliaTrack.fromDatabaseJson(Map<String, dynamic> json) {
    return AuraliaTrack(
      id: json['track_id']?.toString(),
      title: json['title']?.toString() ?? 'Unknown track',
      artist: json['artist']?.toString() ?? 'Unknown artist',
      stage: json['stage']?.toString() ?? 'Validation',
      valence: _toDouble(json['valence']),
      energy: _toDouble(json['energy']),
      previewUrl: json['preview_url']?.toString(),
      imageUrl: json['image_url']?.toString(),
      externalUrl: json['external_url']?.toString(),
      durationMs: _toInt(json['duration_ms']),
    );
  }

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);

  static double _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}

class AuraliaPlaylist {
  const AuraliaPlaylist({
    this.databaseId,
    required this.name,
    required this.sourceMood,
    required this.summary,
    required this.tracks,
  });

  final int? databaseId;
  final String name;
  final AuraliaMood sourceMood;
  final String summary;
  final List<AuraliaTrack> tracks;

  String get fingerprint {
    final trackKeys = tracks
        .map((track) {
          final id = track.id;
          if (id != null && id.isNotEmpty) {
            return id;
          }
          return '${track.title.toLowerCase()}|${track.artist.toLowerCase()}';
        })
        .join('>');
    return '${sourceMood.name}|$name|$trackKeys';
  }

  Map<String, dynamic> toJson({String? userId, String? moodId}) {
    final json = <String, dynamic>{
      'playlist_name': name,
      'source_mood': sourceMood.name,
      'summary': summary,
    };
    if (userId != null) {
      json['user_id'] = userId;
    }
    if (moodId != null) {
      json['mood_id'] = moodId;
    }
    return json;
  }

  factory AuraliaPlaylist.fromDatabaseJson(Map<String, dynamic> json) {
    final tracksJson = json['track'] as List<dynamic>? ?? [];
    return AuraliaPlaylist(
      databaseId: json['id'] as int?,
      name: json['playlist_name']?.toString() ?? 'Saved Playlist',
      sourceMood: AuraliaMood.values.firstWhere(
        (mood) => mood.name == json['source_mood'],
        orElse: () => AuraliaMood.neutral,
      ),
      summary: json['summary']?.toString() ?? '',
      tracks: tracksJson
          .map(
            (track) =>
                AuraliaTrack.fromDatabaseJson(track as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  AuraliaPlaylist copyWithDatabaseId(int databaseId) {
    return AuraliaPlaylist(
      databaseId: databaseId,
      name: name,
      sourceMood: sourceMood,
      summary: summary,
      tracks: tracks,
    );
  }
}
