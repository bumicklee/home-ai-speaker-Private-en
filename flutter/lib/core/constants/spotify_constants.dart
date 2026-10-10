/// Spotify PKCE login (design document Sections 2.10, 3.5).
/// client_id is not a constant. Users create their own developer app and enter it.
library;

class SpotifyConstants {
  SpotifyConstants._();

  /// Redirect scheme. Must match Android `appAuthRedirectScheme` and iOS `CFBundleURLSchemes` (Q8)
  static const redirectScheme = 'com.aispeaker.app';
  static const redirectUri = '$redirectScheme://spotify-callback';

  static const authorizationEndpoint = 'https://accounts.spotify.com/authorize';
  static const tokenEndpoint = 'https://accounts.spotify.com/api/token';
  static const dashboardUrl = 'https://developer.spotify.com/dashboard';

  /// Design document Section 2.10 (`streaming` for the Connect receiver waits on the Q2 decision)
  static const scopes = [
    'user-read-playback-state',
    'user-modify-playback-state',
    'user-read-currently-playing',
  ];

  /// client_id format: 32 hex digits
  static final clientIdPattern = RegExp(r'^[0-9a-fA-F]{32}$');
}
