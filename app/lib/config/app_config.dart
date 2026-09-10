class AppConfig {
  // API Configuration
  // Production backend: AWS EC2 t4g.small (eu-central-1), Elastic IP 63.179.163.62
  // Override at build time with --dart-define=API_BASE_URL=https://...
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://63.179.163.62:3000/api/v1/',
  );
  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: 'http://63.179.163.62:3000',
  );
  static const String googleOAuthUrl = String.fromEnvironment(
    'GOOGLE_OAUTH_URL',
    defaultValue: 'http://63.179.163.62:3000/api/v1/auth/google',
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '62771458278-73dh3jp1t12udcs1gp1e6atuga6ie5lg.apps.googleusercontent.com',
  );

  static const String googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '62771458278-73dh3jp1t12udcs1gp1e6atuga6ie5lg.apps.googleusercontent.com',
  );



  // ── Voice / WebRTC ────────────────────────────────────────────────────────
  // STUN alone only connects two peers when at least one of them is reachable
  // from the outside. Two users on mobile data usually sit behind carrier-grade
  // NAT, where no direct path exists at all and the voice link silently never
  // comes up — the single biggest cause of "الصوت بيفصل" reports on phones.
  // A TURN server relays that traffic. Supply one at build time:
  //   --dart-define=TURN_URLS=turn:turn.example.com:3478?transport=udp,turns:turn.example.com:5349?transport=tcp
  //   --dart-define=TURN_USERNAME=... --dart-define=TURN_CREDENTIAL=...
  // Comma-separated; leave empty to keep the STUN-only behaviour.
  static const String turnUrls = String.fromEnvironment(
    'TURN_URLS',
    defaultValue: '',
  );
  static const String turnUsername = String.fromEnvironment(
    'TURN_USERNAME',
    defaultValue: '',
  );
  static const String turnCredential = String.fromEnvironment(
    'TURN_CREDENTIAL',
    defaultValue: '',
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
