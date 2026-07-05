import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:spotify_sdk/spotify_sdk.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/playlist.dart';

class SpotifyPlaybackService {
  factory SpotifyPlaybackService() => _instance;

  SpotifyPlaybackService._();

  static final SpotifyPlaybackService _instance = SpotifyPlaybackService._();

  bool _connected = false;
  bool _playbackOptionsConfigured = false;
  String? lastError;

  bool get isConnected => _connected;

  bool get isConfigured => AppConfig.hasSpotifyPlaybackConfig;

  Stream<SpotifyPlaybackSnapshot> get playerStateStream =>
      SpotifySdk.subscribePlayerState().map((state) {
        final track = state.track;
        return SpotifyPlaybackSnapshot(
          trackUri: track?.uri,
          position: Duration(milliseconds: state.playbackPosition),
          duration: Duration(milliseconds: track?.duration ?? 0),
          isPaused: state.isPaused,
        );
      });

  Future<bool> connect({String spotifyUri = ''}) async {
    if (!isConfigured) {
      lastError = 'Missing SPOTIFY_CLIENT_ID or redirect URL.';
      return false;
    }
    if (_connected) {
      return true;
    }

    try {
      lastError = null;
      if (!await _isSpotifyAppAvailable()) {
        lastError =
            'Spotify app is required to play full tracks. Install Spotify, log in with Premium, then try again.';
        return false;
      }

      final authorized = await authorize();
      if (!authorized) {
        return false;
      }

      _connected = await SpotifySdk.connectToSpotifyRemote(
        clientId: AppConfig.spotifyClientId,
        redirectUrl: AppConfig.spotifyRedirectUrl,
        spotifyUri: spotifyUri,
        playerName: 'AURALIA',
      ).timeout(const Duration(seconds: 12));
      if (_connected) {
        await _configurePlaybackOptions();
      }
      return _connected;
    } on TimeoutException {
      lastError =
          'Spotify did not respond. Open Spotify first, play any song, then return to AURALIA.';
      _connected = false;
      return false;
    } catch (error) {
      debugPrint('Spotify remote connection failed: $error');
      lastError = _friendlySpotifyError(error);
      _connected = false;
      return false;
    }
  }

  Future<bool> authorize() async {
    if (!isConfigured) {
      lastError = 'Missing SPOTIFY_CLIENT_ID or redirect URL.';
      return false;
    }

    try {
      lastError = null;
      await SpotifySdk.getAccessToken(
        clientId: AppConfig.spotifyClientId,
        redirectUrl: AppConfig.spotifyRedirectUrl,
        scope:
            'app-remote-control,user-modify-playback-state,user-read-playback-state',
      ).timeout(const Duration(seconds: 20));
      return true;
    } on TimeoutException {
      lastError =
          'Spotify authorization timed out. Open Spotify once, return to AURALIA, then tap Connect Spotify again.';
      return false;
    } catch (error) {
      debugPrint('Spotify authorization failed: $error');
      lastError = _friendlySpotifyError(error);
      return false;
    }
  }

  Future<bool> _isSpotifyAppAvailable() async {
    try {
      return await canLaunchUrl(Uri.parse('spotify:')) ||
          await canLaunchUrl(
            Uri.parse('spotify:track:0VjIjW4GlUZAMYd2vXMi3b'),
          );
    } catch (_) {
      return false;
    }
  }

  Future<bool> playTrack(AuraliaTrack track) async {
    final uri = spotifyUriForTrack(track);
    if (uri == null || !await connect(spotifyUri: uri)) {
      return false;
    }

    try {
      await SpotifySdk.play(spotifyUri: uri).timeout(
        const Duration(seconds: 8),
      );
      return true;
    } on TimeoutException {
      lastError =
          'Spotify playback timed out. Open Spotify first, play any song, then return to AURALIA.';
      _connected = false;
      return false;
    } catch (error) {
      debugPrint('Spotify play failed: $error');
      lastError = _friendlySpotifyError(error);
      _connected = false;
      return false;
    }
  }

  Future<bool> pause() async {
    if (!_connected && !await connect()) {
      return false;
    }
    try {
      await SpotifySdk.pause();
      return true;
    } catch (error) {
      debugPrint('Spotify pause failed: $error');
      lastError = _friendlySpotifyError(error);
      return false;
    }
  }

  Future<bool> resume() async {
    if (!_connected && !await connect()) {
      return false;
    }
    try {
      await SpotifySdk.resume();
      return true;
    } catch (error) {
      debugPrint('Spotify resume failed: $error');
      lastError = _friendlySpotifyError(error);
      return false;
    }
  }

  Future<void> seek(Duration position) async {
    if (!_connected && !await connect()) {
      return;
    }
    try {
      await SpotifySdk.seekTo(positionedMilliseconds: position.inMilliseconds);
    } catch (error) {
      debugPrint('Spotify seek failed: $error');
      lastError = _friendlySpotifyError(error);
    }
  }

  Future<void> disconnect() async {
    if (!_connected) {
      return;
    }
    try {
      await SpotifySdk.disconnect();
    } catch (error) {
      debugPrint('Spotify disconnect failed: $error');
      lastError = _friendlySpotifyError(error);
    } finally {
      _connected = false;
      _playbackOptionsConfigured = false;
    }
  }

  Future<void> _configurePlaybackOptions() async {
    if (_playbackOptionsConfigured) {
      return;
    }

    try {
      await SpotifySdk.setShuffle(shuffle: false).timeout(
        const Duration(seconds: 2),
      );
      await SpotifySdk.setRepeatMode(repeatMode: RepeatMode.off).timeout(
        const Duration(seconds: 2),
      );
      _playbackOptionsConfigured = true;
    } catch (error) {
      debugPrint('Spotify queue options could not be changed: $error');
    }
  }

  String? spotifyUriForTrack(AuraliaTrack track) {
    final id = _realSpotifyIdForTrack(track);
    if (id == null || id.isEmpty) {
      return null;
    }
    return 'spotify:track:$id';
  }

  String? _realSpotifyIdForTrack(AuraliaTrack track) {
    final id = track.id;
    if (id != null && id.isNotEmpty && !id.startsWith('fallback-')) {
      return id;
    }

    final key = '${track.title.trim().toLowerCase()}|${track.artist.trim().toLowerCase()}';
    return _knownSpotifyTrackIds[key];
  }

  String _friendlySpotifyError(Object error) {
    final message = error.toString();
    if (message.contains('CouldNotFindSpotifyApp') ||
        message.contains('Spotify app is not installed') ||
        message.contains('MissingPluginException') ||
        message.contains('No implementation found for method getAccessToken')) {
      return 'Spotify app is required to play full tracks. Install Spotify, log in with Premium, then try again.';
    }
    if (message.contains('NotLoggedIn') || message.contains('logged in')) {
      return 'Spotify is not logged in. Open Spotify and log in with Premium.';
    }
    if (message.contains('UserNotAuthorized') ||
        message.contains('authorize')) {
      return 'Spotify did not authorize AURALIA. Check test user, Android checkbox, package name, SHA-1, and redirect URI.';
    }
    if (message.contains('AUTHENTICATION_SERVICE_UNAVAILABLE')) {
      return 'Spotify auth service is unavailable. Update/reinstall Spotify, then open Spotify once before AURALIA.';
    }
    if (message.contains('Premium') || message.contains('premium')) {
      return 'Spotify Premium is required for full playback.';
    }
    return 'Spotify connection failed: $message';
  }
}

class SpotifyPlaybackSnapshot {
  const SpotifyPlaybackSnapshot({
    required this.trackUri,
    required this.position,
    required this.duration,
    required this.isPaused,
  });

  final String? trackUri;
  final Duration position;
  final Duration duration;
  final bool isPaused;
}

const _knownSpotifyTrackIds = <String, String>{
  'drivers license|olivia rodrigo': '5wANPM4fQCJwkGd4rN57mH',
  'someone like you|adele': '4kflIGfjdZJW4ot2ioixTB',
  'all too well|taylor swift': '3nsfB1vus2qaloUdcBZvDu',
  'when i was your man|bruno mars': '0nJW01T7XtvILxQgC5J7Wh',
  'let her go|passenger': '2jyjhRf6DVbMPU5zxagN2h',
  'fix you|coldplay': '7LVHVU3tWfcxj5aiPFEW4Q',
  'lose you to love me|selena gomez': '4l0Mvzj72xxOpRrp6h8nHi',
  'traitor|olivia rodrigo': '5CZ40GBx1sQ9agT82CLQCT',
  'the night we met|lord huron': '3hRV0jL3vUpRrcy398teAU',
  'lovely|billie eilish, khalid': '0u2P5u6lvoDfwTYjAADbn4',
  'the climb|miley cyrus': '7nUlyv5E5Pz8dsbUd9Y0Ec',
  'a thousand years|christina perri': '6lanRgr6wXibZr8KgzXxBl',
  'count on me|bruno mars': '7l1qvxWjxcKpB9PCtBuTbU',
  'keep your head up|andy grammer': '5Hroj5K7vLpIG4FNCRIjbP',
  'rainbow|kacey musgraves': '79qxwHypONUt3AFq0WPpT9',
  'rise up|andra day': '0tV8pOpiNsKqUys0ilUcXz',
  'photograph|ed sheeran': '1HNkqx9Ahdgi1Ixy2xkKkL',
  'yellow|coldplay': '3AJwUDP919kvQ9QcozQPxg',
  'good life|onerepublic': '6OtCIsQZ64Vs1EbzztvAv4',
  'walking on sunshine|katrina & the waves': '05wIrZSwuaVWhcv5FfqeH0',
  'best day of my life|american authors': '5Hroj5K7vLpIG4FNCRIjbP',
  'on top of the world|imagine dragons': '213x4gsFDm04hSqIUkg88w',
  'firework|katy perry': '4lCv7b86sLynZbXhfScfm2',
  'high hopes|panic! at the disco': '1rqqCSm0Qe4I9rUvWncaom',
  'shake it off|taylor swift': '1p80LdxRV74UKvL8gnD7ky',
  'happy|pharrell williams': '60nZcImufyMA1MKQY3dcCH',
  "can't stop the feeling!|justin timberlake": '6JV2JOEocMgcZxYSZelKcc',
  'dynamite|bts': '0t1kP63rueHleOhQkYSXFY',
  'until i found you|stephen sanchez': '0T5iIrXA4p5GsubkhuBIKV',
  'make you feel my love|adele': '0put0_a--NgKueYFLKIYo',
  'location unknown|honne, beka': '7jLQrCCYdK8A0YcYwHFeQ3',
  'breathe|taylor swift, colbie caillat': '49mWEy5MgtNujgT7xU3emT',
  'best part|daniel caesar, h.e.r.': '1RMJOxR6GRPsBHL8qeC2ux',
  'like real people do|hozier': '57yL3161hUMuw06zzzUCHi',
  'put your records on|corinne bailey rae': '2nGFzvICaeEWjIrBrL2RAx',
  'sunday morning|maroon 5': '5qII2n90lVdPDcgXEEVHNy',
  'levitating|dua lipa': '463CkQjx2Zk1yXoBuierM9',
  'as it was|harry styles': '4LRPiXqCikLlN15c3yImP7',
  'blinding lights|the weeknd': '0VjIjW4GlUZAMYd2vXMi3b',
  'uptown funk|mark ronson, bruno mars': '32OlwWuMpZ6b0aN2RZOeMS',
  'watermelon sugar|harry styles': '6UelLqGlWMcVH1E5c4H7lY',
  'good 4 u|olivia rodrigo': '4ZtFanR9U6ndgddUvNcjcG',
  'flowers|miley cyrus': '0yLdNVWF3Srea0uzk55zFn',
  'stronger|kanye west': '4fzsfWzRhPawzqhX8Qt9F3',
  'believer|imagine dragons': '0pqnGHJpmpxLKifKRmU6WP',
  'unstoppable|sia': '1yvMUkIOTeUNtNWlWRgANS',
  'titanium|david guetta, sia': '2dOTkLZFbpNXrhc24CnTFd',
  "can't hold us|macklemore & ryan lewis": '3bidbhpOYeV4knp8AIu8Xn',
  'hall of fame|the script, will.i.am': '1X1DWw2pcNZ8zSub3uhlNz',
  'eye of the tiger|survivor': '2HHtWyy5CgaQbC7XSoOb0e',
  'run the world (girls)|beyonce': '1uXbwHHfgsXcUKfSZw5ZJ0',
  'the nights|avicii': '0ct6r3EGTcMLPtrXHDvVjc',
  'shape of you|ed sheeran': '7qiZfU4dY1lWllzX7mPBI3',
};
