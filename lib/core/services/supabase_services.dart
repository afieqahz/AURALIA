import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/app_user.dart';
import '../models/mood.dart';
import '../models/playlist.dart';
import 'auth_service.dart';
import 'mood_repository.dart';
import 'playlist_repository.dart';

class SupabaseAuthService implements AuthService {
  SupabaseAuthService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;
  AppUser? _currentUser;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;

  static const _sessionAccessTokenKey = 'auralia.supabase.access_token';
  static const _sessionRefreshTokenKey = 'auralia.supabase.refresh_token';
  static const _sessionExpiresAtKey = 'auralia.supabase.expires_at';
  static const _sessionUserIdKey = 'auralia.supabase.user_id';
  static const _sessionUserEmailKey = 'auralia.supabase.user_email';
  static const _sessionUserNameKey = 'auralia.supabase.user_name';

  @override
  AppUser? get currentUser => _currentUser;

  String? get accessToken => _accessToken;

  @override
  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_sessionAccessTokenKey);
    final refreshToken = prefs.getString(_sessionRefreshTokenKey);
    final userId = prefs.getString(_sessionUserIdKey);
    final userEmail = prefs.getString(_sessionUserEmailKey);
    final userName = prefs.getString(_sessionUserNameKey);
    final expiresAtValue = prefs.getInt(_sessionExpiresAtKey);

    if (accessToken == null ||
        accessToken.isEmpty ||
        userId == null ||
        userId.isEmpty ||
        userEmail == null ||
        userEmail.isEmpty) {
      await _clearStoredSession();
      return false;
    }

    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _expiresAt = expiresAtValue == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiresAtValue);
    _currentUser = AppUser(
      id: userId,
      email: userEmail,
      name: userName?.isNotEmpty == true ? userName! : _nameFromEmail(userEmail),
    );

    if (_expiresAt != null &&
        _expiresAt!.isBefore(DateTime.now().add(const Duration(minutes: 2))) &&
        refreshToken != null &&
        refreshToken.isNotEmpty) {
      return _refreshSession(refreshToken);
    }

    return true;
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/auth/v1/token?grant_type=password',
    );
    final response = await _client.post(
      uri,
      headers: _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );

    return _userFromAuthResponse(response, fallbackName: _nameFromEmail(email));
  }

  @override
  Future<AppUser> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    final uri = Uri.parse('${AppConfig.supabaseUrl}/auth/v1/signup');
    final response = await _client.post(
      uri,
      headers: _headers(),
      body: jsonEncode({
        'email': email,
        'password': password,
        'data': {'name': name},
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthFlowException(_authErrorMessage(response));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (body['access_token'] == null) {
      throw const AuthEmailConfirmationRequired();
    }

    return _userFromBody(body, fallbackName: name);
  }

  @override
  Future<void> resetPassword({required String email}) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.supabaseUrl}/auth/v1/recover').replace(
        queryParameters: {'redirect_to': AppConfig.passwordResetRedirectUrl},
      ),
      headers: _headers(),
      body: jsonEncode({'email': email}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthFlowException(_authErrorMessage(response));
    }
  }

  @override
  Future<void> completePasswordReset({
    required String accessToken,
    required String newPassword,
  }) async {
    if (accessToken.isEmpty) {
      throw const AuthFlowException(
        'The reset link is missing a recovery session. Request a new link.',
      );
    }

    final response = await _client.put(
      Uri.parse('${AppConfig.supabaseUrl}/auth/v1/user'),
      headers: {..._headers(), 'Authorization': 'Bearer $accessToken'},
      body: jsonEncode({'password': newPassword}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthFlowException(_authErrorMessage(response));
    }
  }

  @override
  Future<AppUser> updateProfile({required String name}) async {
    final token = _accessToken;
    final currentUser = _currentUser;
    if (token == null || currentUser == null) {
      throw const AuthFlowException('You must be logged in to edit your profile.');
    }

    final response = await _client.put(
      Uri.parse('${AppConfig.supabaseUrl}/auth/v1/user'),
      headers: {..._headers(), 'Authorization': 'Bearer $token'},
      body: jsonEncode({
        'data': {'name': name},
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthFlowException(_authErrorMessage(response));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final metadata = body['user_metadata'] as Map<String, dynamic>?;
    _currentUser = AppUser(
      id: body['id']?.toString() ?? currentUser.id,
      email: body['email']?.toString() ?? currentUser.email,
      name: metadata?['name']?.toString() ?? name,
    );
    await _saveStoredSession();
    return _currentUser!;
  }

  @override
  Future<void> changePassword({required String newPassword}) async {
    final token = _accessToken;
    if (token == null || _currentUser == null) {
      throw const AuthFlowException(
        'You must be logged in to change your password.',
      );
    }

    final response = await _client.put(
      Uri.parse('${AppConfig.supabaseUrl}/auth/v1/user'),
      headers: {..._headers(), 'Authorization': 'Bearer $token'},
      body: jsonEncode({'password': newPassword}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthFlowException(_authErrorMessage(response));
    }
  }

  @override
  Future<void> deleteAccount() async {
    final token = _accessToken;
    if (token == null || _currentUser == null) {
      throw const AuthFlowException(
        'You must be logged in to delete your account.',
      );
    }

    final response = await _client.post(
      Uri.parse('${AppConfig.supabaseUrl}/rest/v1/rpc/delete_my_account'),
      headers: {..._headers(), 'Authorization': 'Bearer $token'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthFlowException(
        'Delete account is not enabled yet. Run supabase_delete_account.sql in Supabase, then try again.',
      );
    }

    _currentUser = null;
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    await _clearStoredSession();
  }

  @override
  Future<void> signOut() async {
    final token = _accessToken;
    if (token != null && token.isNotEmpty) {
      try {
        await _client.post(
          Uri.parse('${AppConfig.supabaseUrl}/auth/v1/logout'),
          headers: {..._headers(), 'Authorization': 'Bearer $token'},
        );
      } catch (_) {
        // Always clear the local session.
      }
    }
    _currentUser = null;
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    await _clearStoredSession();
  }

  AppUser _userFromAuthResponse(
    http.Response response, {
    required String fallbackName,
  }) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthFlowException(_authErrorMessage(response));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return _userFromBody(body, fallbackName: fallbackName);
  }

  AppUser _userFromBody(
    Map<String, dynamic> body, {
    required String fallbackName,
  }) {
    final user = body['user'] as Map<String, dynamic>?;
    if (user == null) {
      throw const AuthFlowException(
        'Authentication succeeded but no user account was returned.',
      );
    }
    final accessToken = body['access_token']?.toString();
    if (accessToken == null || accessToken.isEmpty) {
      throw const AuthFlowException(
        'No login session was returned. Confirm your email and try again.',
      );
    }
    final metadata = user['user_metadata'] as Map<String, dynamic>?;
    _accessToken = accessToken;
    _refreshToken = body['refresh_token']?.toString();
    final expiresIn = int.tryParse(body['expires_in']?.toString() ?? '');
    _expiresAt = expiresIn == null
        ? null
        : DateTime.now().add(Duration(seconds: expiresIn));
    _currentUser = AppUser(
      id: user['id']?.toString() ?? 'supabase-user',
      email: user['email']?.toString() ?? '',
      name: metadata?['name']?.toString() ?? fallbackName,
    );
    unawaited(_saveStoredSession());
    return _currentUser!;
  }

  Future<bool> _refreshSession(String refreshToken) async {
    try {
      final response = await _client.post(
        Uri.parse('${AppConfig.supabaseUrl}/auth/v1/token?grant_type=refresh_token'),
        headers: _headers(),
        body: jsonEncode({'refresh_token': refreshToken}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await _clearStoredSession();
        _currentUser = null;
        _accessToken = null;
        _refreshToken = null;
        _expiresAt = null;
        return false;
      }

      final restoredName = _currentUser?.name;
      final user = _userFromBody(
        jsonDecode(response.body) as Map<String, dynamic>,
        fallbackName: restoredName ?? 'Afiqah',
      );
      _currentUser = user;
      return true;
    } catch (_) {
      return _currentUser != null && _accessToken != null;
    }
  }

  Future<void> _saveStoredSession() async {
    final user = _currentUser;
    final accessToken = _accessToken;
    if (user == null || accessToken == null || accessToken.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionAccessTokenKey, accessToken);
    if (_refreshToken != null && _refreshToken!.isNotEmpty) {
      await prefs.setString(_sessionRefreshTokenKey, _refreshToken!);
    }
    if (_expiresAt != null) {
      await prefs.setInt(
        _sessionExpiresAtKey,
        _expiresAt!.millisecondsSinceEpoch,
      );
    }
    await prefs.setString(_sessionUserIdKey, user.id);
    await prefs.setString(_sessionUserEmailKey, user.email);
    await prefs.setString(_sessionUserNameKey, user.name);
  }

  Future<void> _clearStoredSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionAccessTokenKey);
    await prefs.remove(_sessionRefreshTokenKey);
    await prefs.remove(_sessionExpiresAtKey);
    await prefs.remove(_sessionUserIdKey);
    await prefs.remove(_sessionUserEmailKey);
    await prefs.remove(_sessionUserNameKey);
  }

  String _authErrorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final message =
          body['msg']?.toString() ??
          body['message']?.toString() ??
          body['error_description']?.toString() ??
          body['error']?.toString();
      if (message != null && message.isNotEmpty) {
        final lower = message.toLowerCase();
        if (lower.contains('invalid login credentials')) {
          return 'Incorrect email or password.';
        }
        if (lower.contains('email not confirmed')) {
          return 'Confirm your email address before logging in.';
        }
        if (lower.contains('user already registered')) {
          return 'An account with this email already exists.';
        }
        return message;
      }
    } catch (_) {
      // Use the status-based fallback.
    }

    return switch (response.statusCode) {
      400 => 'Please check the information and try again.',
      401 => 'Incorrect email or password.',
      422 => 'The account information is not valid.',
      429 => 'Too many attempts. Please wait and try again.',
      _ => 'Authentication service is unavailable. Please try again.',
    };
  }

  Map<String, String> _headers() {
    return {
      'apikey': AppConfig.supabaseAnonKey,
      'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
      'Content-Type': 'application/json',
    };
  }

  String _nameFromEmail(String email) {
    final prefix = email.split('@').first.trim();
    if (prefix.isEmpty) {
      return 'Afiqah';
    }
    return prefix[0].toUpperCase() + prefix.substring(1);
  }
}

class SupabaseMoodRepository implements MoodRepository {
  SupabaseMoodRepository({http.Client? client, this._accessTokenProvider})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String? Function()? _accessTokenProvider;

  @override
  Future<List<MoodEntry>> loadMoodHistory(String userId) async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/mood?user_id=eq.$userId&select=*&order=created_at.asc',
    );
    final response = await _client.get(uri, headers: _headers());

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load mood history: ${response.body}');
    }

    final rows = jsonDecode(response.body) as List<dynamic>;
    return rows
        .map((row) => MoodEntry.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<MoodEntry> saveMoodEntry({
    required String userId,
    required AuraliaMood mood,
    MoodCheckInType checkInType = MoodCheckInType.beforeListening,
    String? playlistName,
    ListeningHelpfulness? helpfulness,
  }) async {
    final uri = Uri.parse('${AppConfig.supabaseUrl}/rest/v1/mood');
    final entry = MoodEntry(
      mood: mood,
      createdAt: DateTime.now(),
      checkInType: checkInType,
      playlistName: playlistName,
      helpfulness: helpfulness,
    );
    var response = await _client.post(
      uri,
      headers: {..._headers(), 'Prefer': 'return=representation'},
      body: jsonEncode(entry.toJson(userId: userId)),
    );

    var usedLegacySchema = false;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      usedLegacySchema = true;
      response = await _client.post(
        uri,
        headers: {..._headers(), 'Prefer': 'return=representation'},
        body: jsonEncode({
          'user_id': userId,
          'mood_type': mood.name,
          'created_at': entry.createdAt.toIso8601String(),
        }),
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to save mood: ${response.body}');
    }

    if (usedLegacySchema) {
      return entry;
    }

    final rows = jsonDecode(response.body) as List<dynamic>;
    if (rows.isEmpty) {
      return entry;
    }
    return MoodEntry.fromJson(rows.first as Map<String, dynamic>);
  }

  Map<String, String> _headers() {
    final bearerToken =
        _accessTokenProvider?.call() ?? AppConfig.supabaseAnonKey;
    return {
      'apikey': AppConfig.supabaseAnonKey,
      'Authorization': 'Bearer $bearerToken',
      'Content-Type': 'application/json',
    };
  }
}

class SupabasePlaylistRepository implements PlaylistRepository {
  SupabasePlaylistRepository({http.Client? client, this._accessTokenProvider})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String? Function()? _accessTokenProvider;

  @override
  Future<List<AuraliaPlaylist>> loadSavedPlaylists(String userId) async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/playlist?user_id=eq.$userId&select=*,track(*)&order=created_at.desc',
    );
    final response = await _client.get(uri, headers: _headers());

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load playlists: ${response.body}');
    }

    final rows = jsonDecode(response.body) as List<dynamic>;
    return rows
        .map(
          (row) =>
              AuraliaPlaylist.fromDatabaseJson(row as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<List<AuraliaPlaylist>> loadFavoritePlaylists(String userId) async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/favorite?user_id=eq.$userId&status=eq.liked&select=playlist(*,track(*))&order=created_at.desc',
    );
    final response = await _client.get(uri, headers: _headers());

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load favorites: ${response.body}');
    }

    final rows = jsonDecode(response.body) as List<dynamic>;
    return rows
        .map((row) => (row as Map<String, dynamic>)['playlist'])
        .whereType<Map<String, dynamic>>()
        .map(AuraliaPlaylist.fromDatabaseJson)
        .toList();
  }

  @override
  Future<int> savePlaylist({
    required String userId,
    required String? moodId,
    required AuraliaPlaylist playlist,
  }) async {
    final playlistUri = Uri.parse('${AppConfig.supabaseUrl}/rest/v1/playlist');
    final playlistResponse = await _client.post(
      playlistUri,
      headers: {..._headers(), 'Prefer': 'return=representation'},
      body: jsonEncode(playlist.toJson(userId: userId, moodId: moodId)),
    );

    if (playlistResponse.statusCode < 200 ||
        playlistResponse.statusCode >= 300) {
      throw Exception('Failed to save playlist: ${playlistResponse.body}');
    }

    final playlistRows = jsonDecode(playlistResponse.body) as List<dynamic>;
    final playlistId =
        (playlistRows.first as Map<String, dynamic>)['id'] as int;

    final trackRows = playlist.tracks
        .map((track) => track.toJson(playlistId: playlistId))
        .toList();

    if (trackRows.isNotEmpty) {
      final trackUri = Uri.parse('${AppConfig.supabaseUrl}/rest/v1/track');
      var trackResponse = await _client.post(
        trackUri,
        headers: _headers(),
        body: jsonEncode(trackRows),
      );

      if (_missingDurationColumn(trackResponse)) {
        final legacyTrackRows = trackRows
            .map((row) => Map<String, dynamic>.from(row)..remove('duration_ms'))
            .toList();
        trackResponse = await _client.post(
          trackUri,
          headers: _headers(),
          body: jsonEncode(legacyTrackRows),
        );
      }

      if (trackResponse.statusCode < 200 || trackResponse.statusCode >= 300) {
        throw Exception('Failed to save tracks: ${trackResponse.body}');
      }
    }

    return playlistId;
  }

  bool _missingDurationColumn(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return response.body.contains('duration_ms') &&
          response.body.contains('schema cache');
    }
    return false;
  }

  @override
  Future<void> setFavorite({
    required String userId,
    required int playlistId,
    required bool liked,
  }) async {
    final uri = Uri.parse(
      '${AppConfig.supabaseUrl}/rest/v1/favorite?on_conflict=user_id,playlist_id',
    );

    if (!liked) {
      final deleteUri = Uri.parse(
        '${AppConfig.supabaseUrl}/rest/v1/favorite?user_id=eq.$userId&playlist_id=eq.$playlistId',
      );
      final response = await _client.delete(deleteUri, headers: _headers());
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to unlike playlist: ${response.body}');
      }
      return;
    }

    final response = await _client.post(
      uri,
      headers: {..._headers(), 'Prefer': 'resolution=merge-duplicates'},
      body: jsonEncode({
        'user_id': userId,
        'playlist_id': playlistId,
        'status': 'liked',
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to like playlist: ${response.body}');
    }
  }

  Map<String, String> _headers() {
    final bearerToken =
        _accessTokenProvider?.call() ?? AppConfig.supabaseAnonKey;
    return {
      'apikey': AppConfig.supabaseAnonKey,
      'Authorization': 'Bearer $bearerToken',
      'Content-Type': 'application/json',
    };
  }
}
