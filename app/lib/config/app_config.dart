class AppConfig {
  // API Configuration
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/api/v1/',
  );
  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'http://localhost:3000',
  );
  static const String googleOAuthUrl = String.fromEnvironment(
    'GOOGLE_OAUTH_URL',
    defaultValue: 'http://localhost:3000/api/v1/auth/google',
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
