import 'widgets/top_snack.dart';
import 'services/effects_prefs.dart';
import 'services/room_link_handler.dart';
import 'services/screen_record_service.dart';
import 'services/active_room.dart';
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
import 'providers/locale_provider.dart';
import 'package:samafox/screens/games_hub_screen.dart';
import 'widgets/app_scale.dart';
import 'widgets/pip_overlay.dart';
import 'services/socket_service.dart';
import 'services/device_tier.dart';
import 'services/gpu_cache.dart';
import 'services/memory_guard.dart';
import 'utils/app_route_observer.dart';
import 'services/global_notification_service.dart';
import 'repositories/cp_repository.dart';
import 'widgets/cp_request_dialog.dart';
import 'widgets/room/room_events.dart';
import 'widgets/global_notification_bar.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'l10n/tr.dart';

/// Per-step start-up timings, sent once the reporter is up.
final Map<String, int> _bootMs = {};

/// One start-up step, capped. Everything awaited here runs while Android still
/// shows its own launch screen (the icon on black): the app's splash is a
/// Flutter frame, and no frame is drawn until `runApp`. A step that stalls —
/// a slow disk, a busy main thread on a phone at 3% battery — left that icon
/// up with nothing moving (14/10, "البرنامج مش عاوز يفتح"). A capped step that
/// times out keeps running in the background; start-up just stops waiting.
Future<void> _bootStep(String name, Future<void> Function() step, Duration cap) async {
  final sw = Stopwatch()..start();
  try {
    await step().timeout(cap);
  } on TimeoutException {
    _bootMs['$name!timeout'] = sw.elapsedMilliseconds;
    return;
  } catch (e) {
    debugPrint('[boot] $name failed: $e');
  }
  _bootMs[name] = sw.elapsedMilliseconds;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // SPEC52 #23 — personal gift/entry effect switches.
  // ignore: unawaited_futures
  EffectsPrefs.instance.load();
  final bootClock = Stopwatch()..start();

  // Decoded images: 60 MB instead of Flutter's 100 MB. Phones in a room sat at
  // img=100MB with ~350 MB of graphics beside it, and a realme RMX3760 died at
  // 1.2 GB (29/09). Evicted pictures are re-decoded from the disk cache.
  // Half that on a 2–4 GB phone, a quarter under 3 GB (see DeviceTier).
  await _bootStep('deviceTier', DeviceTier.init, const Duration(seconds: 3));
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      (DeviceTier.ultraLite ? 16 : DeviceTier.lite ? 32 : 60) << 20;
  unawaited(GpuCache.apply());

  // Before anything else can fail. The app shipped with NO error handler of any
  // kind, which is why "التطبيق يقفل بعد دقيقة" could only ever be guessed at:
  // a Dart error left nothing behind, and an OS kill for memory left even less.
  // CrashReporter catches the first and DETECTS the second on the next launch.
  await _bootStep('crashReporter', CrashReporter.install, const Duration(seconds: 4));
  MemoryGuard.install();
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

  // The token migration inside may keep running past the cap; StorageService
  // fetches its prefs lazily, so nothing reads a half-initialised service.
  await _bootStep('storage', StorageService.init, const Duration(seconds: 3));
  // Not capped: the providers need it, and it is the same instance StorageService
  // already asked for, so it is normally ready by now.
  final prefsClock = Stopwatch()..start();
  final sharedPreferences = await SharedPreferences.getInstance();
  _bootMs['prefs'] = prefsClock.elapsedMilliseconds;
  final _ = DioClient.dio;
  DioClient.init();
  // Which voice engine rooms use (mesh or SFU): cached value now, server value
  // refreshed in the background. Never blocks startup.
  await _bootStep('voiceEngine', VoiceEngineConfig.load, const Duration(seconds: 2));

  // How long Android's launch screen stayed up. Sent for every start so a
  // slow phone shows in /client-logs before anyone has to report it.
  final bootTotal = bootClock.elapsedMilliseconds;
  CrashReporter.event(
    'startup',
    'boot ${bootTotal}ms ${DeviceTier.summary}',
    level: bootTotal > 3000 || _bootMs.keys.any((k) => k.endsWith('!timeout'))
        ? 'warn'
        : 'info',
    data: {'totalMs': bootTotal, ..._bootMs},
  );

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
  StreamSubscription<Map<String, dynamic>>? _recordingSub;
  late final SocketService _socketService;

  @override
  void initState() {
    super.initState();
    unawaited(RoomLinkHandler.instance.initialize(navigatorKey));
    _recordingSub = ScreenRecordService.instance.events.listen((state) {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      final message = state['uri'] != null ? tr('تم حفظ التسجيل في الاستوديو', 'Recording saved to gallery')
          : state['error']?.toString() ??
            (state['recording'] == true && state['roomAudioIncluded'] == false
              ? ScreenRecordService.fallbackHint : null);
      if (message != null) showTopSnackBar(context, SnackBar(content: Text(message)));
    });

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
    RoomEventsBus.instance.wire();
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
              senderName: payload['senderName']?.toString() ?? tr('مستخدم', 'User'),
              senderAvatarUrl: (data['actor'] as Map?)?['avatarUrl']?.toString(),
              giftName: payload['giftName']?.toString() ?? tr('هدية', 'Gift'),
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
                      title.isNotEmpty ? title : tr('إشعار من الإدارة', 'Notice from the management'),
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
                  child: Text(tr('حسناً', 'OK'), style: TextStyle(color: Colors.lightBlueAccent)),
                ),
              ],
            ),
          );
        }
        return;
      }

      String localizedTitle() {
        if (title.isNotEmpty && !_looksEnglish(title)) return title;
        if (type.contains('follow')) return tr('طلب متابعة', 'Follow request');
        if (type.contains('relation')) return tr('طلب علاقة', 'Relationship request');
        if (type.contains('gift')) return tr('هدية جديدة', 'New gift');
        if (type.contains('message')) return tr('رسالة جديدة', 'New message');
        return title.isNotEmpty ? title : tr('إشعار جديد', 'New notification');
      }

      String localizedBody() {
        if (body.isNotEmpty && !_looksEnglish(body)) return body;
        if (type == 'follow_request') return tr('لديك طلب متابعة جديد. افتح الإشعارات للرد.', 'You have a new follow request. Open notifications to respond.');
        if (type == 'follow_accepted') return tr('تم قبول طلب المتابعة الخاص بك.', 'Your follow request was accepted.');
        if (type == 'follow_rejected') return tr('تم رفض طلب المتابعة الخاص بك.', 'Your follow request was declined.');
        if (type == 'relation_request') return tr('لديك طلب علاقة جديد. افتح الإشعارات للرد.', 'You have a new relationship request. Open notifications to respond.');
        if (type == 'relation_accepted') return tr('تم قبول طلب العلاقة.', 'Relationship request accepted.');
        if (type == 'relation_ended') return tr('تم إنهاء العلاقة.', 'The relationship has ended.');
        if (type.contains('gift')) return tr('وصلتك هدية جديدة.', 'You received a new gift.');
        if (type.contains('message')) return tr('لديك رسالة جديدة.', 'You have a new message.');
        return body.isNotEmpty ? body : tr('لديك إشعار جديد في حسابك.', 'You have a new notification.');
      }

      // A21 — the two banners the client called out get a short life and, for
      // the agent-percentage one, a drop below the gift bar. Everything else
      // keeps a readable dwell time; the notifications list stays the place to
      // review anything that flashed past ("مع عمل قائمة للإشعارات").
      final bool isGiftReceived = type.contains('gift');
      final bool isAgentPercentage =
          type.contains('commission') || type.contains('agency') || type.contains('target');
      // SPEC52 #31 — inside a room these go to the 🔔 above the messages
      // (with a badge) instead of a bar across the room.
      if (isAgentPercentage && ActiveRoom.instance.roomId != null) return;

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
      final name = from?['name']?.toString() ?? tr('مستخدم', 'User');
      showTopSnackBar(ctx, 
        SnackBar(
          backgroundColor: const Color(0xFF1A2744),
          content: Text(tr('👤 $name أرسل طلب متابعة', '👤 $name sent you a follow request')),
          action: SnackBarAction(
            label: tr('الإشعارات', 'Notifications'),
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
      final name = byUser?['name']?.toString() ?? tr('مستخدم', 'User');
      showTopSnackBar(context, 
        SnackBar(content: Text(tr('$name قبل طلب متابعتك', '$name accepted your follow request'))),
      );
    });
    _socketService.on('follow_rejected', (_) {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      showTopSnackBar(context, 
        SnackBar(content: Text(tr('تم رفض طلب المتابعة', 'Follow request declined'))),
      );
    });
    _socketService.on('relation_request', (data) {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      final fromUser = (data is Map ? data['fromUser'] : null) as Map?;
      final name = fromUser?['name']?.toString() ?? tr('مستخدم', 'User');
      showTopSnackBar(context, 
        SnackBar(
          backgroundColor: const Color(0xFF2D1B69),
          content: Text(tr('💍 $name يريد أن يكون في علاقة معك', '💍 $name wants to be in a relationship with you')),
          action: SnackBarAction(
            label: tr('عرض', 'View'),
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
      final name = byUser?['name']?.toString() ?? tr('مستخدم', 'User');
      showTopSnackBar(context, 
        SnackBar(
          backgroundColor: const Color(0xFF1a3a1a),
          content: Text(tr('💍 $name قبل طلب العلاقة!', '💍 $name accepted the relationship request!')),
          duration: const Duration(seconds: 4),
        ),
      );
    });
    _socketService.on('relation_ended', (_) {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      showTopSnackBar(context, 
        SnackBar(
          content: Text(tr('انتهت العلاقة', 'Relationship ended')),
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
    // Which engine each room is on can change while the app sits in the
    // background; pick up the current answer before the next room is entered.
    if (state == AppLifecycleState.resumed) unawaited(VoiceEngineConfig.refresh());

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
    RoomLinkHandler.instance.dispose();
    _recordingSub?.cancel();
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
    // The settings screen switches [localeProvider]; this used to watch the
    // older localizationProvider, so the app's locale and direction never
    // followed the switch.
    final locale = ref.watch(localeProvider).locale;

    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [appRouteObserver],
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
        // Same layout on every phone: no system font scaling, and a screen
        // under 360 dp is drawn as a scaled-down 360 dp one (see AppScale).
        return AppScale(
          child: Directionality(
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
          ),
        );
      },

    );
  }
}
