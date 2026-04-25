import 'package:flutter/material.dart';
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
import 'screens/gifts_screen.dart';
import 'screens/charging_agent_screen.dart';
import 'screens/search_screen.dart';
import 'theme/app_theme.dart';
import 'utils/storage_service.dart';
import 'providers/localization_provider.dart';
import 'package:samafox/screens/games_hub_screen.dart';
import 'widgets/pip_overlay.dart';
import 'services/socket_service.dart';
import 'models/mega_gift_payload.dart';
import 'widgets/mega_gift_overlay.dart';
import 'services/global_notification_service.dart';
import 'widgets/global_notification_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize storage
  await StorageService.init();

  // Initialize SharedPreferences
  final sharedPreferences = await SharedPreferences.getInstance();
  final _ = DioClient.dio; // forces dio creation + interceptors attached
  DioClient.init();

  runApp(
    ProviderScope(
      overrides: [
        // Override the sharedPreferencesProvider with the actual instance
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
  StreamSubscription<Map<String, dynamic>>? _globalGiftSub;
  late final SocketService _socketService;

  int _extractGiftCoins(Map<String, dynamic> payload) {
    final candidates = <dynamic>[
      payload['coinsValue'],
      payload['giftCoins'],
      payload['coins'],
      payload['priceCoins'],
      payload['price_coins'],
      payload['totalCoins'],
      payload['amount'],
    ];

    for (final raw in candidates) {
      if (raw is int && raw > 0) return raw;
      if (raw is num && raw > 0) return raw.toInt();
      if (raw is String) {
        final parsed = int.tryParse(raw.trim());
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _socketService = SocketService();
    _globalGiftSub = SocketService().globalGiftBroadcastStream.listen((data) {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      final payload = MegaGiftPayload.fromJson(data);
      MegaGiftOverlay.show(context, payload);
      final giftCoins = _extractGiftCoins(data);
      if (giftCoins > 5000) {
        GlobalNotificationService.instance.show(
          GlobalNotificationEvent(
            title: 'هدية عالمية ضخمة',
            message: '${payload.senderName} أرسل ${payload.giftNameAr} بقيمة $giftCoins',
            routeName: '/notifications',
          ),
        );
      }
    });
    SocketService().on('follow_request', (data) {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return;
      final from = (data is Map ? data['fromUser'] : null) as Map?;
      final name = from?['name']?.toString() ?? 'مستخدم';
      GlobalNotificationService.instance.show(
        GlobalNotificationEvent(
          title: 'طلب متابعة',
          message: '$name أرسل طلب متابعة جديد',
          routeName: '/notifications',
        ),
      );
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
      GlobalNotificationService.instance.show(
        GlobalNotificationEvent(
          title: 'طلب علاقة',
          message: '$name يريد أن يكون في علاقة معك',
          routeName: '/notifications',
        ),
      );
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
      GlobalNotificationService.instance.show(
        GlobalNotificationEvent(
          title: 'تم قبول طلب العلاقة',
          message: '$name قبل طلب العلاقة',
          routeName: '/notifications',
        ),
      );
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
    _globalGiftSub?.cancel();
    _socketService.off('follow_request');
    _socketService.off('follow_accepted');
    _socketService.off('follow_rejected');
    _socketService.off('relation_request');
    _socketService.off('relation_accepted');
    _socketService.off('relation_ended');
    super.dispose();
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
