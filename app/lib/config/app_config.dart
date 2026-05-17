class AppConfig {
  // API Configuration
  // Production backend: GCP VM samafox-backend (34.55.178.254)
  // Override at build time with --dart-define=API_BASE_URL=https://...
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://34.55.178.254:3000/api/v1/',
  );
  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'http://34.55.178.254:3000',
  );
  static const String googleOAuthUrl = String.fromEnvironment(
    'GOOGLE_OAUTH_URL',
    defaultValue: 'http://34.55.178.254:3000/api/v1/auth/google',
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '62771458278-73dh3jp1t12udcs1gp1e6atuga6ie5lg.apps.googleusercontent.com',
  );

  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '62771458278-73dh3jp1t12udcs1gp1e6atuga6ie5lg.apps.googleusercontent.com',
  );



  // App Configuration
  static const String appName = 'SamaFox';
  static const String appVersion = '1.0.0';
  
  // Timeouts
  static const int connectTimeout = 30000; // 30 seconds
  static const int receiveTimeout = 30000;
  static const int sendTimeout = 30000;
  
  // Socket Configuration
  static const int socketReconnectionAttempts = 5;
  static const int socketReconnectionDelay = 1000;
  
  // Pagination
  static const int defaultPageSize = 20;
  static const int maxRoomMembers = 50;
  static const int defaultMaxSeats = 8;
  
  // Storage Keys
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userDataKey = 'user_data';
  static const String guestUserIdKey = 'guest_user_id';
  static const String guestUsernameKey = 'guest_username';
  static const String languageKey = 'language';
  static const String darkModeKey = 'dark_mode';
  
  // Default Values
  static const String defaultLanguage = 'ar';
  static const bool defaultDarkMode = true;
}
