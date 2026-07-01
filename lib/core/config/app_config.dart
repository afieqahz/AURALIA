class AppConfig {
  const AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const spotifyClientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
  static const spotifyAccessToken = String.fromEnvironment(
    'SPOTIFY_ACCESS_TOKEN',
  );
  static const spotifyBackendUrl = String.fromEnvironment(
    'SPOTIFY_BACKEND_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
  static const spotifyRedirectUrl = String.fromEnvironment(
    'SPOTIFY_REDIRECT_URL',
    defaultValue: 'auralia://callback',
  );
  static const passwordResetRedirectUrl = String.fromEnvironment(
    'PASSWORD_RESET_REDIRECT_URL',
    defaultValue: 'auralia://callback',
  );
  static const spotifyOnly = bool.fromEnvironment('SPOTIFY_ONLY');

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasSpotifyConfig =>
      spotifyClientId.isNotEmpty ||
      spotifyAccessToken.isNotEmpty ||
      spotifyBackendUrl.isNotEmpty;

  static bool get hasSpotifyPlaybackConfig =>
      spotifyClientId.isNotEmpty && spotifyRedirectUrl.isNotEmpty;
}
