import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';
import 'package:samafox/screens/chat_screen.dart';
import 'package:samafox/screens/feature_screens.dart';
import 'package:samafox/screens/store_screen.dart';
import 'package:samafox/services/crash_reporter.dart';
import 'package:samafox/services/dio_client.dart';
import 'package:samafox/services/voice_engine.dart';
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
import 'repositories/cp_repository.dart';
import 'widgets/cp_request_dialog.dart';
import 'widgets/global_notification_bar.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Before anything else can fail. The app shipped with NO error handler of any
  // kind, which is why "التطبيق يقفل بعد دقيقة" could only ever be guessed at:
  // a Dart error left nothing behind, and an OS kill for memory left even less.
  // CrashReporter catches the first and DETECTS the second on the next launch.
  await CrashReporter.install();
  // Play's Photo and Video Permissions policy: pick photos through the system
  // photo picker everywhere, not only on Android 13+, so no media permission
  // is needed on any version. Manifest declares none.
  final picker = ImagePickerPlatform.instance;
  if (picker is ImagePickerAndroid) picker.useAndroidPhotoPicker = true;

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
  // Which voice engine rooms use (mesh or SFU): cached value now, server value
  // refreshed in the background. Never blocks startup.
  await VoiceEngineConfig.load();

  // Inside the guard: an error that escapes the widget callbacks lands here
  // instead of disappearing.
  CrashReporter.guard(() {
    runApp(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        ],
        child: const SamaFoxApp(),
      ),
    );
  });
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class SamaFoxApp extends ConsumerStatefulWidget {
  const SamaFoxApp({super.key});

  @override
  ConsumerState<SamaFoxApp> createState() => _SamaFoxAppState();
}

class _SamaFoxAppState extends ConsumerState<SamaFoxApp> with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>>? _globalNotificationSub;
  late final SocketService _socketService;

  @override
  void initState() {
    super.initState();

    // A10 — "طول ما المستخدم داخل التطبيق الشاشة ما تفصلش تلقائي", and
    // deliberately independent of the phone's own sleep timeout. Held for the
    // whole app rather than just the room: the client's wording is
    // "داخل التطبيق", and the store, the games and the chat all suffered the
    // same mid-read blackout.
    //
    // Released when the app leaves the foreground so it can never keep a
    // backgrounded phone awake — that would be a battery complaint instead.
    WidgetsBinding.instance.addObserver(this);
    _applyWakelock(true);

    _socketService = SocketService();
    _globalNotificationSub = _socketService.notificationStream.listen((data) {
      final type = (data['type'] as String? ?? '').toLowerCase();
      final title = (data['title'] as String? ?? '').trim();
      final body = (data['body'] as String? ?? '').trim();

      // A15 — an incoming CP gift needs an answer, not a banner: the sender's
      // coins are held on the outcome (full price on accept, 30% on reject), so
      // the prompt is raised straight away. Dismissing it costs nobody
      // anything and the invitation stays in the notifications list.
      if (type == 'cp_request') {
        final ctx = navigatorKey.currentContext;
        final payload = (data['data'] as Map?) ?? const {};
        final requestId = (payload['cpRequestId'] as num?)?.toInt();
        if (ctx != null && requestId != null) {
          CpRequestDialog.show(
            ctx,
            CpRequest(
              id: requestId,
              senderId: (payload['senderId'] as num?)?.toInt() ?? 0,
              senderName: payload['senderName']?.toString() ?? 'مستخدم',
              senderAvatarUrl: (data['actor'] as Map?)?['avatarUrl']?.toString(),
              giftName: payload['giftName']?.toString() ?? 'هدية',
              giftIconUrl: payload['giftIconUrl']?.toString() ?? '',
              quantity: (payload['quantity'] as num?)?.toInt() ?? 1,
              totalCoins: (payload['totalCoins'] as num?)?.toInt() ?? 0,
              // Mirrors the server's CP_REJECT_FEE_RATE. Shown, not enforced —
              // the server is what actually charges it.
              rejectFeeCoins:
                  (((payload['totalCoins'] as num?)?.toInt() ?? 0) * 0.3).floor(),
            ),
          );
        }
        return;
      }

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

      // A21 — the two banners the client called out get a short life and, for
      // the agent-percentage one, a drop below the gift bar. Everything else
      // keeps a readable dwell time; the notifications list stays the place to
      // review anything that flashed past ("مع عمل قائمة للإشعارات").
      final bool isGiftReceived = type.contains('gift');
      final bool isAgentPercentage =
          type.contains('commission') || type.contains('agency') || type.contains('target');

      GlobalNotificationService.instance.show(
        GlobalNotificationEvent(
          title: localizedTitle(),
          message: localizedBody(),
          routeName: '/notifications',
          duration: (isGiftReceived || isAgentPercentage)
              ? kNotificationBriefDuration
              : kNotificationDefaultDuration,
          // D8 — "الإشعار ينزل تحت شريط الهدية مباشرة مش فوقه". BOTH banners
          // the client named cover the gift bar, so both drop below it; only
          // the agent-percentage one did before.
          topOffset:
              (isAgentPercentage || isGiftReceived) ? kBelowGiftBarOffset : 0,
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

  /// Never let a wakelock failure surface: an unsupported platform or a denied
  /// request must not break app start-up.
  Future<void> _applyWakelock(bool enable) async {
    try {
      await WakelockPlus.toggle(enable: enable);
    } catch (e) {
      debugPrint('[wakelock] toggle($enable) failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _applyWakelock(state == AppLifecycleState.resumed);

    // `detached` is the app going away on purpose. Clearing the session marker
    // here is what makes its survival meaningful: if it is still on disk at the
    // next launch, the previous run did NOT end on purpose — the OS killed it.
    if (state == AppLifecycleState.detached) {
      unawaited(CrashReporter.markCleanExit());
    } else {
      CrashReporter.breadcrumb('lifecycle ${state.name}');
      // Going to the background is the last reliable moment to send what has
      // been logged: the OS may freeze or kill the process before the next
      // timer tick.
      if (state == AppLifecycleState.paused) unawaited(CrashReporter.flushEvents());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _applyWakelock(false);
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
              // D6/D7 — this cannot be reordered to sit under the room's
              // banners: they live inside `child` above, so any sibling after
              // it paints over them regardless of order. The overlap is solved
              // by moving the notification DOWN instead — see kBelowGiftBarOffset
              // where the banner is built.
              const GlobalNotificationBar(),
            ],
          ),
        );
      },

    );
  }
}
