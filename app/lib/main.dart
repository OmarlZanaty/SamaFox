import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';
import 'package:samafox/screens/chat_screen.dart';
import 'package:samafox/screens/feature_screens.dart';
import 'package:samafox/screens/store_screen.dart';
import 'package:samafox/services/dio_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/room_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/charging_agent_screen.dart';
import 'screens/agency_panel_screen.dart';
import 'screens/my_agencies_screen.dart';
import 'screens/search_screen.dart';
import 'theme/app_theme.dart';
import 'utils/storage_service.dart';
import 'providers/localization_provider.dart';
import 'package:samafox/screens/games_hub_screen.dart';
import 'widgets/pip_overlay.dart';
import 'services/socket_service.dart';
import 'services/global_notification_service.dart';
import 'widgets/global_notification_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

/*  // ✅ Initialize Facebook SDK for WEB only
  if (kIsWeb) {
    await FacebookAuth.instance.webInitialize(
      appId: "1027283767143922",
      cookie: true,
      xfbml: true,
      version: "v18.0",
    );
  }*/

  await StorageService.init();
  final sharedPreferences = await SharedPreferences.getInstance();
  final _ = DioClient.dio;
  DioClient.init();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
      ],
      child: const SamaFoxApp(),
    ),
  );
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class SamaFoxApp extends ConsumerStatefulWidget {
  const SamaFoxApp({super.key});

  @override
  ConsumerState<SamaFoxApp> createState() => _SamaFoxAppState();
}

class _SamaFoxAppState extends ConsumerState<SamaFoxApp> {
  StreamSubscription<Map<String, dynamic>>? _globalNotificationSub;
  late final SocketService _socketService;

  @override
  void initState() {
    super.initState();
    _socketService = SocketService();
    _globalNotificationSub = _socketService.notificationStream.listen((data) {
      final type = (data['type'] as String? ?? '').toLowerCase();
      final title = (data['title'] as String? ?? '').trim();
      final body = (data['body'] as String? ?? '').trim();

      // Admin control-panel broadcast: show verbatim in a prominent dialog.
      if (type == 'admin_broadcast') {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          showDialog(
            context: ctx,
            builder: (dctx) => AlertDialog(
              backgroundColor: const Color(0xFF1A2744),
              title: Row(
                children: [
                  const Icon(Icons.campaign, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title.isNotEmpty ? title : 'إشعار من الإدارة',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Text(body, style: const TextStyle(color: Colors.white70, height: 1.5)),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dctx).pop(),
                  child: const Text('حسناً', style: TextStyle(color: Colors.lightBlueAccent)),
                ),
              ],
            ),
          );
        }
        return;
      }

      String localizedTitle() {
        if (title.isNotEmpty && !_looksEnglish(title)) return title;
        if (type.contains('follow')) return 'طلب متابعة';
        if (type.contains('relation')) return 'طلب علاقة';
        if (type.contains('gift')) return 'هدية جديدة';
        if (type.contains('message')) return 'رسالة جديدة';
        return title.isNotEmpty ? title : 'إشعار جديد';
      }

      String localizedBody() {
        if (body.isNotEmpty && !_looksEnglish(body)) return body;
        if (type == 'follow_request') return 'لديك طلب متابعة جديد. افتح الإشعارات للرد.';
        if (type == 'follow_accepted') return 'تم قبول طلب المتابعة الخاص بك.';
        if (type == 'follow_rejected') return 'تم رفض طلب المتابعة الخاص بك.';
        if (type == 'relation_request') return 'لديك طلب علاقة جديد. افتح الإشعارات للرد.';
        if (type == 'relation_accepted') return 'تم قبول طلب العلاقة.';
        if (type == 'relation_ended') return 'تم إنهاء العلاقة.';
        if (type.contains('gift')) return 'وصلتك هدية جديدة.';
        if (type.contains('message')) return 'لديك رسالة جديدة.';
        return body.isNotEmpty ? body : 'لديك إشعار جديد في حسابك.';
      }

      GlobalNotificationService.instance.show(
        GlobalNotificationEvent(
          title: localizedTitle(),
          message: localizedBody(),
          routeName: '/notifications',
        ),
      );
    });
    // Mega-gift / global broadcast overlay is handled by the V2 gift system
    // (GiftAnimationOverlay + BroadcastBannerLayer mounted inside RoomScreen).
    SocketService().on('follow_request', (data) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      final from = (data is Map ? data['fromUser'] : null) as Map?;
      final name = from?['name']?.toString() ?? 'مستخدم';
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1A2744),
          content: Text('👤 $name أرسل طلب متابعة'),
          action: SnackBarAction(
            label: 'الإشعارات',
            textColor: Colors.lightBlueAccent,
            onPressed: () => Navigator.pushNamed(ctx, '/notifications'),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    });
    _socketService.on('follow_accepted', (data) {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      final byUser = (data is Map ? data['byUser'] : null) as Map?;
      final name = byUser?['name']?.toString() ?? 'مستخدم';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name قبل طلب متابعتك')),
      );
    });
    _socketService.on('follow_rejected', (_) {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم رفض طلب المتابعة')),
      );
    });
    _socketService.on('relation_request', (data) {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      final fromUser = (data is Map ? data['fromUser'] : null) as Map?;
      final name = fromUser?['name']?.toString() ?? 'مستخدم';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2D1B69),
          content: Text('💍 $name يريد أن يكون في علاقة معك'),
          action: SnackBarAction(
            label: 'عرض',
            textColor: Colors.amber,
            onPressed: () => Navigator.pushNamed(context, '/notifications'),
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    });
    _socketService.on('relation_accepted', (data) {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      final byUser = (data is Map ? data['byUser'] : null) as Map?;
      final name = byUser?['name']?.toString() ?? 'مستخدم';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF1a3a1a),
          content: Text('💍 $name قبل طلب العلاقة!'),
          duration: const Duration(seconds: 4),
        ),
      );
    });
    _socketService.on('relation_ended', (_) {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('انتهت العلاقة'),
          duration: Duration(seconds: 3),
        ),
      );
    });
  }

  @override
  void dispose() {
    _globalNotificationSub?.cancel();
    _socketService.off('follow_request');
    _socketService.off('follow_accepted');
    _socketService.off('follow_rejected');
    _socketService.off('relation_request');
    _socketService.off('relation_accepted');
    _socketService.off('relation_ended');
    super.dispose();
  }

  bool _looksEnglish(String value) {
    final latin = RegExp(r'[A-Za-z]');
    final arabic = RegExp(r'[\u0600-\u06FF]');
    return latin.hasMatch(value) && !arabic.hasMatch(value);
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localizationProvider);

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'SamaFox',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,


      // Localization settings
      locale: locale,
      supportedLocales: const [
        Locale('ar', ''), // Arabic (default)
        Locale('en', ''), // English
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const MainNavigationScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/messages': (_) => const MessagesScreen(),
        '/notifications': (_) => const NotificationsScreen(),
        '/chat': (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          final data = (args is Map) ? Map<String, dynamic>.from(args) : <String, dynamic>{};

          return ChatScreen(
            partnerId: data['partnerId'] as int? ?? 0,
            partnerName: data['partnerName'] as String? ?? '',
            partnerAvatarUrl: data['partnerAvatarUrl'] as String?,
            partnerOnline: data['partnerOnline'] as bool? ?? false,
          );
        },
        '/store': (context) => const StoreScreen(),
        '/charging-agent': (_) => const ChargingAgentScreen(),
        '/agency-panel': (_) => const AgencyPanelScreen(),
        // وكالتي — routes to the right agency, or lets the user pick when
        // they hold both a hosting and a charging one.
        '/my-agencies': (_) => const MyAgenciesScreen(),
        '/search': (context) => const SearchScreen(),
        '/games': (_) => const GamesHubScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/room') {
          final roomId = settings.arguments as int;
          return MaterialPageRoute(
            builder: (context) => RoomScreen(roomId: roomId),
          );
        }
        return null;
      },

      builder: (context, child) {
        final isArabic = locale.languageCode.toLowerCase() == 'ar';
        return Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: Stack(
            children: [
              child!,
              Consumer(
                builder: (context, ref, _) => const PipOverlay(),
              ),
              const GlobalNotificationBar(),
            ],
          ),
        );
      },

    );
  }
}
