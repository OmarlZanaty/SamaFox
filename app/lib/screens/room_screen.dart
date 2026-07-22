import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import '../config/app_config.dart';
import '../models/InventoryItem.dart';
import '../models/room.dart';
import '../providers/auth_provider.dart';
import '../providers/pip_state.dart';
import '../providers/room_controller_provider.dart';
import '../models/user.dart';
import '../providers/room_live_provider.dart';
import '../providers/room_provider.dart';
import '../services/dio_client.dart';
import '../services/socket_service.dart';
import '../services/store_service.dart';
import '../services/webrtc_audio_service.dart';
import '../services/api_service.dart';
import '../services/audio_controller.dart';
import '../services/follow_service.dart';
import '../widgets/online_dot.dart';
import '../widgets/vip_badge.dart';
import '../widgets/mic_perfect_badge.dart';
import '../utils/result.dart' show Result;
import '../utils/storage_service.dart';
import '../widgets/room/_FloatingChatOverlay.dart';
import '../widgets/room/entrance_banner_layer.dart';
import '../widgets/room/mic_queue_panel.dart';
import '../widgets/room/room_chat_panel.dart';
import 'package:permission_handler/permission_handler.dart';
import '../gifts/services/gift_repository.dart';
import '../gifts/services/gift_socket_service.dart';
import '../gifts/widgets/gift_picker_sheet.dart';
import '../gifts/widgets/gift_animation_overlay.dart';
import 'dart:ui';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../repositories/message_repository.dart';
import '../repositories/room_repository.dart';
import '../repositories/user_repository.dart';
import '../utils/country_flag.dart';
import '../utils/result.dart';
import '../widgets/room/seats_grid.dart';
import 'package:video_player/video_player.dart';
import '../models/room_event.dart';
import '../screens/messages_screen.dart';
import '../screens/challenges_screen.dart';
import '../screens/leaderboard_screen.dart';
import '../screens/wallet_screen.dart';
import 'chat_screen.dart';
import 'games_hub_screen.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/FramedAvatar.dart';
import '../screens/profile_screen.dart'; // adjust path to your project

final isAndroid = !kIsWeb && Platform.isAndroid;

enum _RoomImageType { roomImage, background }

class BottomWaveClipper extends CustomClipper<Path> {
  final double depth;

  BottomWaveClipper({this.depth = 40});

  @override
  Path getClip(Size size) {
    final path = Path();

    path.moveTo(0, 0);
    path.lineTo(0, size.height - depth);

    path.quadraticBezierTo(
      size.width / 2,
      size.height,
      size.width,
      size.height - depth,
    );

    path.lineTo(size.width, 0);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class RoomScreen extends ConsumerStatefulWidget {
  final int roomId;
  final int? maxSeats; // ✅ add

  const RoomScreen({Key? key, required this.roomId, this.maxSeats}) : super(key: key);

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> with WidgetsBindingObserver {
  late final ApiService _api = ApiService(DioClient.dio);
  late final GiftSocketService _giftSocket = GiftSocketService(SocketService());
  late final GiftRepository _giftRepository = GiftRepository();
  bool _openingMic = false;
  /// WebRTC audio service for voice chat
  late final WebRTCAudioService _audioService;
  /// Track current seat and mute state to detect changes
  int? _currentSeatNumber;
  bool _currentSeatMuted = true;
  final Completer<void> _roomReady = Completer<void>();
  static const double _bottomBarH = 64.0; // 👈 bottom bar height

  /// Artwork for the seat-tap profile card. Bundled as app assets rather than
  /// served from the API: it's one shared design for every card, so there's no
  /// reason to pay a network round-trip (and a loading flicker) per open.
  static const String _profileCardBackground = 'assets/images/profile_card_bg.png';
  static const String _profileCardCrown = 'assets/images/profile_card_crown.png';
  // ===== Admin bottom panel controllers (PERSISTENT) =====
  final TextEditingController _roomImageCtrl = TextEditingController();
  final TextEditingController _bgImageCtrl = TextEditingController();
  StreamSubscription<String>? _socketErrSub;
  StreamSubscription<Map<String, dynamic>>? _joinDeniedSub;
  bool _pinDialogOpen = false; // guards against stacking PIN dialogs
  final TextEditingController _chatController = TextEditingController();  // Text controller for input
  Timer? _timer;
  final TextEditingController _externalTextController = TextEditingController();
  bool _showAdminPanel = false;
  bool _savingRoomImg = false;
  bool _savingBgImg = false;
  bool _showChatPanel = false; // hidden by default
  final FocusNode _chatFocus = FocusNode();
  bool _keyboardVisible = false;
  final Map<int, GlobalKey> _seatKeys = {};
  final GlobalKey _overlayKey = GlobalKey();
  VideoPlayerController? _seatVideoController;
  bool _showSeatVideo = false;

  final Queue<String> _seatEffectQueue = Queue();
  bool _isPlayingEffect = false;
  String? _activeSeatEffectUrl;
  String? _lastPlayedSeatEffectUrl;
  DateTime? _lastPlayedSeatEffectAt;
  static const Duration _seatEffectDedupWindow = Duration(seconds: 2);

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _playedEntrance = false;

  bool _showGlow = false;
  Color _glowColor = Colors.purpleAccent;

  bool _noiseReduction = false;
  double _volumeLevel = 1.0;
  bool _musicOn = false;

  int? _activeConversationId;
  int? _activeUserId;
  String? _activeUserName;
  String? _activeAvatar;

  bool _isMinimized = false;
  Offset _pipOffset = const Offset(20, 100);

  final FocusNode _topChatFocus = FocusNode();
  StreamSubscription? _seatEffectSub;

  void _closeChat() {
    if (!_showChatPanel) return;

    _topChatFocus.unfocus();

    setState(() {
      _showChatPanel = false;
    });
  }

  Future<void> _playSeatBackgroundVideo(String videoUrl) async {
    final normalizedUrl = videoUrl.trim();
    if (normalizedUrl.isEmpty) return;

    final now = DateTime.now();
    if (_lastPlayedSeatEffectUrl == normalizedUrl &&
        _lastPlayedSeatEffectAt != null &&
        now.difference(_lastPlayedSeatEffectAt!) <= _seatEffectDedupWindow) {
      return;
    }

    _lastPlayedSeatEffectUrl = normalizedUrl;
    _lastPlayedSeatEffectAt = now;
    _isPlayingEffect = true;

    _seatVideoController?.dispose();

    _seatVideoController = VideoPlayerController.networkUrl(Uri.parse(normalizedUrl));

    try {
      await _seatVideoController!.initialize();
    } catch (e) {
      // Bad URL or network failure — release the stuck flag so the queue can continue.
      _isPlayingEffect = false;
      _seatVideoController?.dispose();
      _seatVideoController = null;
      _tryPlayNextEffect();
      return;
    }

    await _seatVideoController!.setVolume(1.0);

    if (!mounted) {
      _isPlayingEffect = false;
      return;
    }

    setState(() {
      _showSeatVideo = true;
    });

    final controller = _seatVideoController;
    if (controller == null) {
      _isPlayingEffect = false;
      return;
    }

    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted || controller != _seatVideoController) {
      _isPlayingEffect = false;
      return;
    }

    controller.play();

    await Future.delayed(controller.value.duration);

    if (!mounted) return;

    setState(() {
      _showSeatVideo = false;
    });

    await Future.delayed(const Duration(milliseconds: 400));

    _isPlayingEffect = false;

    await Future.delayed(const Duration(milliseconds: 300));

    _tryPlayNextEffect();
  }

  bool _keyboardWasOpen = false;

  @override
  void didChangeMetrics() {
    final kb = WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom;
    final isOpen = kb > 0;

    // detect transition ONLY
    if (_keyboardWasOpen && !isOpen) {
      if (_showChatPanel && mounted) {
        setState(() {
          _showChatPanel = false;
        });
      }
    }

    _keyboardWasOpen = isOpen;
  }

  Future<void> _initializeVideo() async {
    if (_seatVideoController != null) {
      await _seatVideoController!.dispose();
    }

    _seatVideoController = VideoPlayerController.asset('assets/seat_effect.mp4');
    await _seatVideoController!.initialize();
    await _seatVideoController!.setLooping(false);

    if (!mounted) return;
    setState(() {
      _showSeatVideo = true;
    });
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    precacheImage(const AssetImage("assets/mega/dragon.png"), context);
    precacheImage(const AssetImage("assets/mega/rocket.png"), context);
    precacheImage(const AssetImage("assets/mega/castle.png"), context);
    precacheImage(const AssetImage("assets/mega/explosion.gif"), context);
  }

  Offset _getSeatPosition(int seatNumber) {
    final key = _seatKeys[seatNumber];

    if (key == null || key.currentContext == null) {
      final size = MediaQuery.of(context).size;
      return Offset(size.width / 2, size.height / 2);
    }

    final seatBox = key.currentContext!.findRenderObject() as RenderBox?;
    final overlayBox = _overlayKey.currentContext?.findRenderObject() as RenderBox?;

    if (seatBox == null || overlayBox == null) {
      final size = MediaQuery.of(context).size;
      return Offset(size.width / 2, size.height / 2);
    }

    final seatCenter = seatBox.localToGlobal(
      seatBox.size.center(Offset.zero),
    );

    return overlayBox.globalToLocal(seatCenter);
  }

  /// Resolves a user's screen position for the gift flight overlay.
  /// If the user is seated, returns their seat centre in overlay coordinates;
  /// otherwise returns the centre of the screen.
  Offset _getSeatPositionByUser(int userId) {
    final seatNumber = _getSeatOfUser(userId);
    if (seatNumber != null) return _getSeatPosition(seatNumber);
    final size = MediaQuery.of(context).size;
    return Offset(size.width / 2, size.height / 2);
  }

  int? _getSeatOfUser(int? userId) {
    if (userId == null) return null;

    final state = ref.read(roomControllerProvider(widget.roomId));

    for (final seat in state.seats.values) {
      if (seat.userId != null &&
          seat.userId.toString() == userId.toString()) {
        return seat.seatNumber;
      }
    }

    return null;
  }

  Future<bool> _ensureMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  void _tryPlayNextEffect() {
    if (_isPlayingEffect) return;
    if (_seatEffectQueue.isEmpty) return;

    final videoUrl = _seatEffectQueue.removeFirst();

    _playSeatBackgroundVideo(videoUrl);
  }


  Future<void> _loadActiveItems() async {
    final token = await StorageService.getAccessToken();
    if (token == null || token.isEmpty) {
      debugPrint('INVENTORY ERROR: No token available');
      return;
    }
    try {
      final items = await StoreService().getInventory(token);

      debugPrint('SELECTED TYPE: seat_effect');
      debugPrint('ITEM TYPES: ${items.map((e) => e.type).toList()}');

      InventoryItem? activeSeatEffect;
      try {
        activeSeatEffect = items.firstWhere(
              (e) => e.type == "seat_effect" && e.isActive,
        );
      } catch (_) {
        activeSeatEffect = null;
      }

      if (activeSeatEffect != null) {
        _activeSeatEffectUrl = activeSeatEffect.fileUrl;
      }
    } catch (e) {
      debugPrint('INVENTORY ERROR: $e');
    }
  }

  void _openSeatCountDialog(BuildContext context) {
    int selected = ref.read(roomControllerProvider(widget.roomId)).seatCount;

    final options = [5, 10, 15, 20, 25, 30];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              decoration: const BoxDecoration(
                color: Color(0xFF2A1655),
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  // 🔘 handle
                  Container(
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    "تحويل نمط مقعد الميكروفون",
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    "وضع الغرفة الصوتية",
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),

                  const SizedBox(height: 20),

                  // ✅ GRID
                  GridView.builder(
                    shrinkWrap: true,
                    itemCount: options.length,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.9,
                    ),
                    itemBuilder: (_, i) {
                      final value = options[i];
                      final isSelected = selected == value;

                      return GestureDetector(
                        onTap: () {
                          setModalState(() {
                            selected = value;
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.deepPurpleAccent
                                  : Colors.white24,
                              width: 2,
                            ),
                            color: Colors.white.withOpacity(0.05),
                          ),
                          child: Stack(
                            children: [

                              // ✔ check
                              if (isSelected)
                                const Positioned(
                                  top: 6,
                                  right: 6,
                                  child: CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Colors.deepPurpleAccent,
                                    child: Icon(Icons.check, size: 14, color: Colors.white),
                                  ),
                                ),

                              // 🔘 dots preview
                              Center(
                                child: Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: List.generate(
                                    value,
                                        (_) => Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Colors.white38,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // label
                              Positioned(
                                bottom: 8,
                                left: 0,
                                right: 0,
                                child: Text(
                                  "مايك $value",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // ✅ confirm button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _updateSeatCount(selected);
                      },
                      child: const Text(
                        "تأكيد",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showRoomSnack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.redAccent : null,
      ),
    );
  }

  bool _isVideoAssetUrl(String url) {
    final value = url.trim().toLowerCase();
    return value.endsWith('.mp4') ||
        value.endsWith('.mov') ||
        value.endsWith('.webm') ||
        value.endsWith('.m4v') ||
        value.endsWith('.mkv');
  }

  Future<void> _handleFollowFromRoom(int targetUserId) async {
    final myUserId = ref.read(authStateProvider).user?.id;
    if (myUserId == null) {
      _showRoomSnack('يجب تسجيل الدخول أولاً', error: true);
      return;
    }
    if (targetUserId == myUserId) {
      _showRoomSnack('لا يمكنك متابعة نفسك', error: true);
      return;
    }

    try {
      final status = await FollowService.getFollowStatus(targetUserId);
      if (status == 'following' || status == 'mutual') {
        _showRoomSnack('أنت تتابع هذا المستخدم بالفعل');
        return;
      }
      if (status == 'pending_sent') {
        _showRoomSnack('تم إرسال طلب المتابعة مسبقاً');
        return;
      }
      if (status == 'blocked') {
        _showRoomSnack('لا يمكن إرسال طلب متابعة لهذا المستخدم', error: true);
        return;
      }

      await FollowService.sendFollowRequest(targetUserId);
      _showRoomSnack('تم إرسال طلب المتابعة');
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = data is Map ? (data['message']?.toString() ?? 'تعذر إرسال طلب المتابعة') : 'تعذر إرسال طلب المتابعة';
      _showRoomSnack(msg, error: true);
    } catch (_) {
      _showRoomSnack('تعذر إرسال طلب المتابعة', error: true);
    }
  }

  Future<void> _refreshRoomData() async {
    await ref.read(roomsProvider.notifier).loadRooms();
    await ref.read(roomControllerProvider(widget.roomId).notifier).loadRoomDetails();
  }

  Future<int?> _mySeatNumber() async {
    final me = ref.read(authStateProvider).user?.id;
    if (me == null) return null;

    final state = ref.read(roomControllerProvider(widget.roomId));
    for (final seat in state.seats.values) {
      if (seat.userId == me) return seat.seatNumber;
    }
    return null;
  }

  Future<void> _updateSeatCount(int count) async {
    final safe = count.clamp(1, 24);
    final roomCtrl = ref.read(roomControllerProvider(widget.roomId).notifier);

    roomCtrl.setSeatCountLocal(safe);
    SocketService().setSeatCount(roomId: widget.roomId, seatCount: safe);

    try {
      await _api.updateMaxSeats({
        'roomId': widget.roomId,
        'room_id': widget.roomId,
        'maxSeats': safe,
        'max_seats': safe,
        'seatCount': safe,
        'seat_count': safe,
      });

      await _refreshRoomData();
      _showRoomSnack('تم تحديث عدد الميكروفونات إلى $safe');
    } catch (e) {
      _showRoomSnack('تعذر تحديث عدد الميكروفونات: $e', error: true);
    }
  }

  Future<void> _toggleRoomLock() async {
    final room = ref.read(roomsProvider).findById(widget.roomId);
    final currentlyLocked = room?.isRoomLocked ?? false;

    // Already locked → open the room to everyone (clears the PIN server-side).
    if (currentlyLocked) {
      try {
        await _api.toggleRoomLock({
          'roomId': widget.roomId,
          'room_id': widget.roomId,
          'locked': false,
          'isLocked': false,
          'isPublic': true,
        });
        await _refreshRoomData();
        _showRoomSnack('تم فتح الغرفة للجميع');
      } catch (e) {
        _showRoomSnack('تعذر فتح الغرفة: $e', error: true);
      }
      return;
    }

    // Not locked → ask the admin for a 5-digit PIN (suggest a random one).
    final suggested =
        (10000 + (DateTime.now().microsecondsSinceEpoch % 90000)).toString();
    final code = await _askFiveDigitCode(
      title: 'قفل الغرفة برمز سري',
      hint: 'لن يدخل أحد الغرفة إلا بهذا الرقم المكوّن من 5 أرقام',
      confirmLabel: 'قفل الغرفة',
      initial: suggested,
    );
    if (code == null) return; // cancelled

    try {
      await _api.toggleRoomLock({
        'roomId': widget.roomId,
        'room_id': widget.roomId,
        'locked': true,
        'isLocked': true,
        'isPublic': false,
        'accessCode': code,
        'code': code,
      });
      await _refreshRoomData();
      _showRoomSnack('تم قفل الغرفة 🔒 الرمز السري: $code');
    } catch (e) {
      _showRoomSnack('تعذر قفل الغرفة: $e', error: true);
    }
  }

  /// Shown when the server denies entry to a locked room: prompt for the PIN
  /// and re-join. Cancelling leaves the room.
  Future<void> _promptRoomAccessCode() async {
    if (_pinDialogOpen) return;
    _pinDialogOpen = true;
    try {
      final code = await _askFiveDigitCode(
        title: 'غرفة مقفلة 🔒',
        hint: 'أدخل الرمز السري المكوّن من 5 أرقام للدخول',
        confirmLabel: 'دخول',
      );
      if (!mounted) return;
      if (code == null) {
        Navigator.of(context).maybePop(); // user declined → leave room
        return;
      }
      await ref
          .read(roomControllerProvider(widget.roomId).notifier)
          .rejoinWithCode(code);
    } finally {
      _pinDialogOpen = false;
    }
  }

  /// Reusable 5-digit numeric PIN dialog. Returns the digits, or null if cancelled.
  /// Delegates to [_PinDialog], which owns its own controller so it is disposed
  /// only once the dialog route is fully gone (avoids "used after disposed").
  Future<String?> _askFiveDigitCode({
    required String title,
    required String hint,
    required String confirmLabel,
    String? initial,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PinDialog(
        title: title,
        hint: hint,
        confirmLabel: confirmLabel,
        initial: initial,
      ),
    );
  }

  /// Appoint a user as room supervisor (Step 11): admin powers, but the server
  /// blocks them from acting on admins/owner.
  Future<void> _appointSupervisor(int? userId) async {
    if (userId == null) return;
    try {
      await _api.addRoomAdmin({
        'roomId': widget.roomId,
        'room_id': widget.roomId,
        'userId': userId,
        'user_id': userId,
        'role': 'supervisor',
      });
      _showRoomSnack('تم تعيين المستخدم مشرفًا للغرفة');
    } catch (e) {
      _showRoomSnack('تعذر التعيين: $e', error: true);
    }
  }

  /// Block/unblock a user from taking a mic seat (Step 10).
  /// Admin options for an EMPTY seat: lock/unlock and mute/unmute the seat.
  void _showEmptySeatAdminSheet(BuildContext context, int seatNumber, {int? myCurrentSeat}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final st = ref.read(roomControllerProvider(widget.roomId));
        final isLocked = st.lockedSeats.contains(seatNumber);
        final isMuted = st.mutedSeats.contains(seatNumber);
        final notifier = ref.read(roomControllerProvider(widget.roomId).notifier);
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A0E3E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 8),
                  Text('المقعد رقم $seatNumber',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _adminSeatOption(
                    label: isMuted ? 'فك كتم المقعد' : 'كتم المقعد',
                    icon: isMuted ? Icons.mic : Icons.mic_off,
                    color: Colors.orangeAccent,
                    onTap: () {
                      Navigator.pop(context);
                      notifier.toggleSeatMute(seatNumber: seatNumber, muted: !isMuted);
                      _showRoomSnack(isMuted ? 'تم فك كتم المقعد $seatNumber' : 'تم كتم المقعد $seatNumber');
                    },
                  ),
                  _adminSeatOption(
                    label: isLocked ? 'فك قفل المقعد' : 'قفل المقعد',
                    icon: isLocked ? Icons.lock_open : Icons.lock,
                    color: Colors.lightBlueAccent,
                    onTap: () {
                      Navigator.pop(context);
                      notifier.toggleSeatLock(seatNumber: seatNumber, locked: !isLocked);
                      _showRoomSnack(isLocked ? 'تم فك قفل المقعد $seatNumber' : 'تم قفل المقعد $seatNumber');
                    },
                  ),
                  _adminSeatOption(
                    label: 'الجلوس على هذا المقعد',
                    icon: Icons.event_seat,
                    color: Colors.greenAccent,
                    onTap: () {
                      Navigator.pop(context);
                      ref.read(roomControllerProvider(widget.roomId).notifier)
                          .takeSeat(seatNumber: seatNumber);
                    },
                  ),
                  // If the admin is already seated, let them MOVE to this seat.
                  if (myCurrentSeat != null && myCurrentSeat != seatNumber)
                    _adminSeatOption(
                      label: 'الانتقال إلى هذا المقعد',
                      icon: Icons.swap_horiz,
                      color: Colors.tealAccent,
                      onTap: () {
                        Navigator.pop(context);
                        ref.read(roomControllerProvider(widget.roomId).notifier)
                            .moveSeat(fromSeat: myCurrentSeat, toSeat: seatNumber);
                      },
                    ),
                  // #12: invite an audience member onto this seat.
                  _adminSeatOption(
                    label: 'دعوة إلى المقعد',
                    icon: Icons.person_add_alt_1,
                    color: Colors.pinkAccent,
                    onTap: () {
                      Navigator.pop(context);
                      _showInviteToSeatSheet(seatNumber);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// #12: pick an audience user (in the room, not on a mic) to invite to [seatNumber].
  void _showInviteToSeatSheet(int seatNumber) {
    final st = ref.read(roomControllerProvider(widget.roomId));
    final seatedIds = st.seats.values.map((s) => s.userId).whereType<int>().toSet();
    final audience = st.onlineUsers.values.where((u) => !seatedIds.contains(u.id)).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0E3E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text('دعوة إلى المقعد $seatNumber',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              if (audience.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('لا يوجد أشخاص في الغرفة لدعوتهم', style: TextStyle(color: Colors.white54)),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: audience.map((u) => ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF3D2B7A),
                        child: Text((u.name ?? '?').isNotEmpty ? u.name![0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white)),
                      ),
                      title: Text(u.name ?? 'User #${u.id}', style: const TextStyle(color: Colors.white)),
                      trailing: const Icon(Icons.person_add, color: Colors.pinkAccent),
                      onTap: () {
                        Navigator.pop(sctx);
                        ref.read(roomControllerProvider(widget.roomId).notifier)
                            .inviteToSeat(seatNumber: seatNumber, targetUserId: u.id);
                        _showRoomSnack('تمت دعوة ${u.name ?? ''} إلى المقعد $seatNumber');
                      },
                    )).toList(),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Admin moderation list: users currently muted / seat-blocked / banned,
  /// each with a button to lift that sanction.
  Future<void> _showModerationSheet(BuildContext context) async {
    Future<List<Map<String, dynamic>>> fetch() async {
      final res = await DioClient.dio.get('/room-admin/${widget.roomId}/moderated');
      final list = (res.data is Map) ? (res.data['data'] as List? ?? const []) : const [];
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF1A0E3E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(width: 40, height: 4, alignment: Alignment.center,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(height: 12),
                      const Text('قائمة الإجراءات (كتم / منع مقعد / طرد)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Flexible(
                        child: FutureBuilder<List<Map<String, dynamic>>>(
                          future: fetch(),
                          builder: (c, snap) {
                            if (snap.connectionState != ConnectionState.done) {
                              return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                            }
                            final rows = snap.data ?? const [];
                            if (rows.isEmpty) {
                              return const Padding(padding: EdgeInsets.all(24),
                                child: Text('لا يوجد مستخدمون عليهم إجراءات حالياً',
                                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)));
                            }
                            return ListView(
                              shrinkWrap: true,
                              children: rows.map((u) => _moderatedRow(ctx, u, setSheet)).toList(),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _moderatedRow(BuildContext ctx, Map<String, dynamic> u, void Function(void Function()) setSheet) {
    final userId = (u['userId'] as num?)?.toInt();
    final chips = <Widget>[];
    Widget chip(String label, Color color) => Container(
      margin: const EdgeInsets.only(left: 6, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11)),
    );
    if (u['forceMuted'] == true) chips.add(chip('مكتوم', Colors.orangeAccent));
    if (u['seatBlocked'] == true) chips.add(chip('ممنوع من المقعد', Colors.deepOrangeAccent));
    if (u['banned'] == true) chips.add(chip('مطرود', Colors.redAccent));

    Future<void> lift(Future<void> Function() action) async {
      try { await action(); setSheet(() {}); } catch (e) { _showRoomSnack('تعذر: $e', error: true); }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(radius: 18,
              backgroundImage: (u['avatarUrl'] ?? '').toString().isNotEmpty ? NetworkImage(u['avatarUrl']) : null,
              child: (u['avatarUrl'] ?? '').toString().isEmpty ? const Icon(Icons.person, size: 18) : null),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${u['name'] ?? ''}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text('#${u['displayId'] ?? userId}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
            Wrap(children: chips),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            if (u['forceMuted'] == true)
              _liftBtn('فك الكتم', () => lift(() => _forceMute(userId, false))),
            if (u['seatBlocked'] == true)
              _liftBtn('فك منع المقعد', () => lift(() => _setSeatBlock(userId, false))),
            if (u['banned'] == true)
              _liftBtn('فك الطرد', () => lift(() => DioClient.dio.post('/room-admin/unban',
                data: {'roomId': widget.roomId, 'userId': userId}))),
          ]),
        ],
      ),
    );
  }

  Widget _liftBtn(String label, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(left: 8),
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF6B4CE6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
    ),
  );

  /// Admin force-mute (Step 10): mutes the target's mic; they cannot unmute
  /// themselves until an admin lifts it. Backend emits seat_mute_changed.
  Future<void> _forceMute(int? userId, bool muted) async {
    if (userId == null) return;
    try {
      await DioClient.dio.post('/room-admin/mute', data: {
        'roomId': widget.roomId,
        'userId': userId,
        'isMuted': muted,
      });
      _showRoomSnack(muted ? 'تم كتم المستخدم (لا يمكنه فتح المايك)' : 'تم رفع الكتم عن المستخدم');
    } catch (e) {
      _showRoomSnack('تعذر تنفيذ الإجراء: $e', error: true);
    }
  }

  Future<void> _setSeatBlock(int? userId, bool blocked) async {
    if (userId == null) return;
    try {
      await DioClient.dio.post('/room-admin/seat-block', data: {
        'roomId': widget.roomId,
        'userId': userId,
        'blocked': blocked,
      });
      _showRoomSnack(blocked
          ? 'تم منع المستخدم من الجلوس على المايك'
          : 'تم رفع المنع عن المستخدم');
    } catch (e) {
      _showRoomSnack('تعذر تنفيذ الإجراء: $e', error: true);
    }
  }

  Widget _kickDurationTile(BuildContext ctx, String label, int minutes) {
    return ListTile(
      leading: const Icon(Icons.timer_outlined, color: Colors.redAccent),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: () => Navigator.pop(ctx, minutes),
    );
  }

  /// Kick a user with a chosen duration (0 = permanent) (Step 10).
  Future<void> _promptKickUser(int? userId) async {
    if (userId == null) return;
    final minutes = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text('مدة الطرد من الغرفة',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
              _kickDurationTile(ctx, '5 دقائق', 5),
              _kickDurationTile(ctx, 'ساعة', 60),
              _kickDurationTile(ctx, 'يوم كامل', 1440),
              _kickDurationTile(ctx, 'طرد دائم', 0),
            ],
          ),
        ),
      ),
    );
    if (minutes == null) return;
    try {
      await _api.kickUser({
        'roomId': widget.roomId,
        'room_id': widget.roomId,
        'userId': userId,
        'user_id': userId,
        'minutes': minutes,
      });
      _showRoomSnack(minutes == 0
          ? 'تم طرد المستخدم نهائيًا'
          : 'تم طرد المستخدم لمدة محددة');
    } catch (e) {
      _showRoomSnack('تعذر الطرد: $e', error: true);
    }
  }

  Future<void> _clearRoomChat() async {
    try {
      await _api.clearChat({
        'roomId': widget.roomId,
        'room_id': widget.roomId,
      });

      ref.read(roomControllerProvider(widget.roomId).notifier).clearMessages();
      _showRoomSnack('تم حذف دردشة الغرفة');
    } catch (e) {
      _showRoomSnack('تعذر حذف دردشة الغرفة: $e', error: true);
    }
  }

  Future<List<RoomMember>> _loadRoomMembers() async {
    final fresh = await RoomRepository().getRoomById(widget.roomId);
    if (fresh.isSuccess && fresh.data != null) {
      return fresh.data!.roomMembers;
    }
    final cached = ref.read(roomsProvider).findById(widget.roomId);
    return cached?.roomMembers ?? const <RoomMember>[];
  }

  Future<void> _toggleAdminForMember({
    required RoomMember member,
    required bool makeAdmin,
  }) async {
    final targetId = member.userId_ ?? member.user?.id;
    if (targetId == null) return;

    try {
      if (makeAdmin) {
        await _api.addRoomAdmin({
          'roomId': widget.roomId,
          'room_id': widget.roomId,
          'userId': targetId,
          'user_id': targetId,
        });
      } else {
        await _api.removeRoomAdmin({
          'roomId': widget.roomId,
          'room_id': widget.roomId,
          'userId': targetId,
          'user_id': targetId,
        });
      }

      await _refreshRoomData();
      _showRoomSnack(makeAdmin ? 'تمت إضافة مسؤول جديد' : 'تمت إزالة المسؤول');
    } catch (e) {
      _showRoomSnack('تعذر تحديث المسؤولين: $e', error: true);
    }
  }

  void _openManageAdminsDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            decoration: const BoxDecoration(
              color: Color(0xFF2A1655),
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: FutureBuilder<List<RoomMember>>(
              future: _loadRoomMembers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final members = snapshot.data ?? const <RoomMember>[];
                if (members.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(30),
                    child: Text(
                      'لا يوجد أعضاء متاحون حالياً',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'مسؤولو الغرفة',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: members.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final member = members[index];
                          final targetId = member.userId_ ?? member.user?.id ?? 0;
                          final displayName = member.user?.name ?? member.name ?? 'User #$targetId';
                          final role = (member.role ?? 'member').toLowerCase();
                          final isOwnerRole = role == 'owner';
                          final isAdminRole = role == 'admin' || isOwnerRole;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundImage: member.user?.avatarUrl != null
                                      ? NetworkImage(member.user!.avatarUrl!)
                                      : null,
                                  child: member.user?.avatarUrl == null
                                      ? const Icon(Icons.person, color: Colors.white)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        isOwnerRole ? 'مالك الغرفة' : (isAdminRole ? 'مسؤول' : 'عضو'),
                                        style: TextStyle(
                                          color: isOwnerRole
                                              ? Colors.amber
                                              : (isAdminRole ? Colors.lightBlueAccent : Colors.white60),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!isOwnerRole)
                                  Switch.adaptive(
                                    value: isAdminRole,
                                    onChanged: (value) async {
                                      Navigator.pop(context);
                                      await _toggleAdminForMember(
                                        member: member,
                                        makeAdmin: value,
                                      );
                                    },
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadBanEntries() async {
    final result = await _api.getBanList(widget.roomId);
    if (result is List) {
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (result is Map && result['data'] is List) {
      return (result['data'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<void> _unbanUser(Map<String, dynamic> entry) async {
    final targetId = entry['userId'] ?? entry['user_id'] ?? entry['id'];
    if (targetId == null) return;

    try {
      await _api.unbanUser({
        'roomId': widget.roomId,
        'room_id': widget.roomId,
        'userId': targetId,
        'user_id': targetId,
      });
      _showRoomSnack('تم إلغاء حظر المستخدم');
      await _refreshRoomData();
    } catch (e) {
      _showRoomSnack('تعذر إلغاء الحظر: $e', error: true);
    }
  }

  void _openBanListDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            decoration: const BoxDecoration(
              color: Color(0xFF2A1655),
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _loadBanEntries(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final entries = snapshot.data ?? const <Map<String, dynamic>>[];
                if (entries.isEmpty) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 50,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'قائمة الحظر',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'لا يوجد مستخدمون محظورون حالياً',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'قائمة الحظر',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final name = entry['username'] ??
                              entry['name'] ??
                              entry['user']?['name'] ??
                              'User';
                          final reason = entry['reason']?.toString();

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              children: [
                                const CircleAvatar(
                                  backgroundColor: Colors.redAccent,
                                  child: Icon(Icons.block, color: Colors.white),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$name',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (reason != null && reason.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          reason,
                                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    Navigator.pop(context);
                                    await _unbanUser(entry);
                                  },
                                  child: const Text('إلغاء الحظر'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<List<InventoryItem>> _loadInventory() async {
    final token = await StorageService.getAccessToken();
    if (token == null || token.isEmpty) return const <InventoryItem>[];
    return StoreService().getInventory(token);
  }

  Future<void> _activateInventoryItem(InventoryItem item) async {
    final token = await StorageService.getAccessToken();
    if (token == null || token.isEmpty) {
      _showRoomSnack('يجب تسجيل الدخول أولاً', error: true);
      return;
    }

    try {
      await StoreService().activateItem(token, item.id);
      await _loadActiveItems();
      _showRoomSnack('تم تفعيل ${item.name}');
    } catch (e) {
      _showRoomSnack('تعذر تفعيل ${item.name}: $e', error: true);
    }
  }

  void _openBackpackSheet(BuildContext context, {String? typeFilter}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            decoration: const BoxDecoration(
              color: Color(0xFF2A1655),
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: FutureBuilder<List<InventoryItem>>(
              future: _loadInventory(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                var items = snapshot.data ?? const <InventoryItem>[];
                if (typeFilter != null) {
                  items = items.where((item) => item.type == typeFilter).toList();
                }

                if (items.isEmpty) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 50,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        typeFilter == null ? 'حقيبة الظهر' : 'غلاف الميكروفون',
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'لا توجد عناصر متاحة',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  );
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 50,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        typeFilter == null ? 'حقيبة الظهر' : 'غلاف الميكروفون',
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: item.isActive ? Colors.greenAccent : Colors.white24),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: item.previewUrl.isNotEmpty && !_isVideoAssetUrl(item.previewUrl)
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(14),
                                          child: Image.network(
                                            item.previewUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(
                                              Icons.inventory_2,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        )
                                      : item.previewUrl.isNotEmpty && _isVideoAssetUrl(item.previewUrl)
                                          ? const Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.play_circle_fill_rounded,
                                                  color: Colors.white70,
                                                  size: 24,
                                                ),
                                                SizedBox(height: 2),
                                                Text(
                                                  'VIDEO',
                                                  style: TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            )
                                      : const Icon(Icons.inventory_2, color: Colors.white70),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.type,
                                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: item.isActive
                                      ? null
                                      : () async {
                                          Navigator.pop(context);
                                          await _activateInventoryItem(item);
                                        },
                                  child: Text(item.isActive ? 'مفعّل' : 'تفعيل'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _openEventsCenter(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            decoration: const BoxDecoration(
              color: Color(0xFF2A1655),
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 18),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'مركز الفعاليات',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _menuItem(Icons.emoji_events, 'التحديات', Colors.amber, () {
                      Navigator.pop(context);
                      Navigator.push(
                        this.context,
                        MaterialPageRoute(builder: (_) => const ChallengesScreen()),
                      );
                    }),
                    _menuItem(Icons.sports_esports, 'الألعاب', Colors.greenAccent, () {
                      Navigator.pop(context);
                      Navigator.push(
                        this.context,
                        MaterialPageRoute(builder: (_) => const GamesHubScreen()),
                      );
                    }),
                    _menuItem(Icons.leaderboard, 'لوحة الصدارة', Colors.lightBlueAccent, () {
                      Navigator.pop(context);
                      Navigator.push(
                        this.context,
                        MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
                      );
                    }),
                    _menuItem(Icons.account_balance_wallet, 'المحفظة', Colors.orangeAccent, () {
                      Navigator.pop(context);
                      Navigator.push(
                        this.context,
                        MaterialPageRoute(builder: (_) => const WalletScreen()),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _toggleMusicSetting() async {
    final room = ref.read(roomsProvider).findById(widget.roomId);
    final url = room?.backgroundMusicUrl ?? '';
    final nextValue = !_musicOn;

    setState(() => _musicOn = nextValue);

    try {
      await _api.setBackgroundMusic({
        'roomId': widget.roomId,
        'room_id': widget.roomId,
        'enabled': nextValue,
        'isEnabled': nextValue,
        'musicOn': nextValue,
        'url': url,
        'backgroundMusicUrl': url,
      });
      _showRoomSnack(nextValue ? 'تم تفعيل موسيقى الغرفة' : 'تم إيقاف موسيقى الغرفة');
    } catch (_) {
      _showRoomSnack(
        nextValue ? 'تم تفعيل الموسيقى محلياً' : 'تم إيقاف الموسيقى محلياً',
      );
    }
  }

  void _toggleNoiseReduction() {
    setState(() => _noiseReduction = !_noiseReduction);
    _showRoomSnack(
      _noiseReduction ? 'تم تفعيل تقليل الضوضاء' : 'تم إيقاف تقليل الضوضاء',
    );
  }

  void _openVolumeDialog(BuildContext context) {
    double tempVolume = _volumeLevel;

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A1655),
          title: const Text('مستوى الصوت', style: TextStyle(color: Colors.white)),
          content: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    value: tempVolume,
                    min: 0,
                    max: 1,
                    divisions: 10,
                    label: '${(tempVolume * 100).round()}%',
                    onChanged: (value) {
                      setModalState(() => tempVolume = value);
                    },
                  ),
                  Text(
                    '${(tempVolume * 100).round()}%',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                setState(() => _volumeLevel = tempVolume);
                await _audioPlayer.setVolume(tempVolume);
                if (_seatVideoController != null) {
                  await _seatVideoController!.setVolume(tempVolume);
                }
                if (mounted) Navigator.pop(context);
                _showRoomSnack('تم تحديث مستوى الصوت');
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
  }

  void _openSoundEffectsDialog(BuildContext context) {
    final room = ref.read(roomsProvider).findById(widget.roomId);
    bool muteGifts = room?.giftSoundsMuted ?? false;
    bool muteEntrance = room?.entranceSoundsMuted ?? false;

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A1655),
          title: const Text('المؤثرات الصوتية', style: TextStyle(color: Colors.white)),
          content: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile.adaptive(
                    value: !muteGifts,
                    onChanged: (value) => setModalState(() => muteGifts = !value),
                    title: const Text('أصوات الهدايا', style: TextStyle(color: Colors.white)),
                  ),
                  SwitchListTile.adaptive(
                    value: !muteEntrance,
                    onChanged: (value) => setModalState(() => muteEntrance = !value),
                    title: const Text('أصوات الدخول', style: TextStyle(color: Colors.white)),
                  ),
                  // #17-18: the coin-counter reset moved to its own item in the
                  // main room menu (next to "حذف الدردشة") — it doesn't belong
                  // under Sound Effects, which is why the owner couldn't find it.
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await _api.toggleSoundSettings({
                    'roomId': widget.roomId,
                    'room_id': widget.roomId,
                    'muteGiftSounds': muteGifts,
                    'mute_gift_sounds': muteGifts,
                    'muteEntranceSounds': muteEntrance,
                    'mute_entrance_sounds': muteEntrance,
                  });
                  await _refreshRoomData();
                  if (mounted) Navigator.pop(context);
                  _showRoomSnack('تم حفظ إعدادات المؤثرات الصوتية');
                } catch (e) {
                  if (mounted) Navigator.pop(context);
                  _showRoomSnack('تعذر حفظ الإعدادات: $e', error: true);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleMicFromMenu() async {
    final seatNumber = await _mySeatNumber();
    if (seatNumber == null) {
      if (_audioReady) {
        final enableMic = _audioService.isMicMuted;
        await AudioController.instance.setMicEnabled(enableMic);
        await _audioService.toggleMute();
        _showRoomSnack(_audioService.isMicMuted ? 'تم كتم الميكروفون' : 'تم فتح الميكروفون');
      } else {
        _showRoomSnack('يجب الصعود إلى مقعد أولاً', error: true);
      }
      return;
    }

    final state = ref.read(roomControllerProvider(widget.roomId));
    final seat = state.seats[seatNumber];
    if (seat == null) return;

    // Step 10: admin force-mute (per-user) or seat-mute (per-seat) — block self-unmute.
    final seatMuted = state.mutedSeats.contains(seatNumber);
    if (seat.forceMuted || seatMuted) {
      await AudioController.instance.setMicEnabled(false);
      if (_audioReady) await _audioService.muteAudio();
      _showRoomSnack('هذا المقعد مكتوم من المشرف، لا يمكنك فتح المايك', error: true);
      return;
    }

    final isMicTurningOn = seat.isMuted;
    await AudioController.instance.setMicEnabled(isMicTurningOn);
    ref.read(roomControllerProvider(widget.roomId).notifier).toggleMute(
      seatNumber: seatNumber,
      isMuted: !seat.isMuted,
      targetUserId: seat.userId,
    );

    if (seat.isMuted) {
      await AudioController.instance.setMicEnabled(true);
      await _audioService.unmuteAudio();
      _showRoomSnack('تم فتح الميكروفون');
    } else {
      await AudioController.instance.setMicEnabled(false);
      await _audioService.muteAudio();
      _showRoomSnack('تم كتم الميكروفون');
    }
  }

  void _openAudioSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A1655),
          title: const Text('إعدادات الصوت', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  _musicOn ? Icons.music_note : Icons.music_off,
                  color: Colors.white70,
                ),
                title: const Text('موسيقى الغرفة', style: TextStyle(color: Colors.white)),
                trailing: Switch.adaptive(
                  value: _musicOn,
                  onChanged: (_) async {
                    Navigator.pop(context);
                    await _toggleMusicSetting();
                  },
                ),
              ),
              ListTile(
                leading: Icon(
                  _noiseReduction ? Icons.hearing : Icons.hearing_disabled,
                  color: Colors.white70,
                ),
                title: const Text('تقليل الضوضاء', style: TextStyle(color: Colors.white)),
                trailing: Switch.adaptive(
                  value: _noiseReduction,
                  onChanged: (_) {
                    Navigator.pop(context);
                    _toggleNoiseReduction();
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.volume_up, color: Colors.white70),
                title: const Text('مستوى الصوت', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  '${(_volumeLevel * 100).round()}%',
                  style: const TextStyle(color: Colors.white60),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openVolumeDialog(this.context);
                },
              ),
              ListTile(
                leading: Icon(
                  _audioService.isMicMuted ? Icons.mic_off : Icons.mic,
                  color: Colors.white70,
                ),
                title: const Text('الميكروفون', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  await _toggleMicFromMenu();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  void _shareRoom() {
    final room = ref.read(roomsProvider).findById(widget.roomId);
    final roomName = room?.name ?? 'SamaFox Room';
    Share.share('Join my room on SamaFox\nRoom: $roomName\nID: ${widget.roomId}');
  }

  void _openReportDialog(BuildContext context) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A1655),
          title: const Text('إبلاغ', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'صف المشكلة أو البلاغ وسيتم تجهيز نص جاهز للمشاركة مع فريق الدعم.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 5,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'اكتب سبب البلاغ...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () async {
                final reportText =
                    'SamaFox room report\nRoom ID: ${widget.roomId}\nIssue: ${controller.text.trim()}';
                await Clipboard.setData(ClipboardData(text: reportText));
                if (mounted) Navigator.pop(context);
                _showRoomSnack('تم نسخ نص البلاغ');
              },
              child: const Text('نسخ'),
            ),
            ElevatedButton(
              onPressed: () {
                final reportText =
                    'SamaFox room report\nRoom ID: ${widget.roomId}\nIssue: ${controller.text.trim()}';
                Navigator.pop(context);
                Share.share(reportText);
              },
              child: const Text('مشاركة'),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  @override
  void initState() {
    debugPrint('🟣 RoomScreen.initState room=${widget.roomId}');
    super.initState();
    AudioController.instance.initialize();

    _audioService = WebRTCAudioService();

    _loadActiveItems(); // 🔥 ADD THIS
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), () {    });
    // Listen for keyboard visibility changes


    WidgetsBinding.instance.addObserver(this);

    final roomId = widget.roomId;

    _audioService.onVoiceActivityChanged = (isSpeaking) async {
      final userId = ref.read(authStateProvider).user?.id;
      if (userId == null) return;

      final controller = ref.read(roomControllerProvider(widget.roomId));

      await _audioService.initialize(
        roomId: widget.roomId,
        userId: userId,
        listenOnly: true,
      );

      if (controller.seats.isEmpty) return; // ✅ IMPORTANT

      ref.read(roomControllerProvider(widget.roomId).notifier)
          .setUserSpeaking(userId, isSpeaking);
    };

    final state = ref.read(roomControllerProvider(widget.roomId));
    debugPrint("🧪 seats before speaking update: ${state.seats}");

    // ✅ ADD THIS BLOCK
    WebRTCAudioService().onVoiceUsersUpdated = (users) {
      debugPrint("🔥 UPDATE UI USERS: $users");

      ref
          .read(roomControllerProvider(roomId).notifier)
          .setVoiceUsers(users);
    };

    _topChatFocus.addListener(() {
      if (!_topChatFocus.hasFocus && _showChatPanel) {

      }
    });

    // Bind the new gift socket; GiftAnimationOverlay handles its own subscriptions.
    _giftSocket.bind();

    Future.microtask(() {
      ref.read(roomControllerProvider(widget.roomId).notifier)
          .loadRoomDetails(); // 🔥 ADD THIS
    });

    _live = ref.read(roomLiveProvider(widget.roomId).notifier);
    _live.bind();
    // ✅ Initialize audio service first (safe)

    if (!mounted) return; // ✅ stop if disposed

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = ref.read(roomControllerProvider(widget.roomId).notifier);

      // Locked-room gate: register the denial listener BEFORE joining, otherwise
      // the server's join_denied (a broadcast event) fires while nobody is
      // listening and is dropped — the PIN dialog would never appear.
      _joinDeniedSub = SocketService().joinDeniedStream.listen((data) {
        if (!mounted) return;
        final rid = data['roomId'];
        if (rid != null && rid != widget.roomId) return;
        final reason = data['reason'];
        if (reason == 'banned') {
          _showRoomSnack(
            (data['message'] ?? 'تم طردك من هذه الغرفة').toString(),
            error: true,
          );
          Navigator.of(context).maybePop();
          return;
        }
        if (reason == 'closed') {
          _showRoomSnack('الغرفة مغلقة', error: true);
          Navigator.of(context).maybePop();
          return;
        }
        _promptRoomAccessCode();
      });

      // Live room background change (admin set a new background).
      SocketService().on('room_background_changed', (data) {
        if (!mounted || data is! Map) return;
        final rid = data['roomId'];
        if (rid != null && rid != widget.roomId) return;
        final url = data['backgroundImageUrl']?.toString();
        ref
            .read(roomControllerProvider(widget.roomId).notifier)
            .setRoomBackgroundUrlLocal(url ?? '');
      });

      // Admin kicked us live → leave the room immediately.
      SocketService().on('kicked_from_room', (data) {
        if (!mounted) return;
        final rid = (data is Map) ? data['roomId'] : null;
        if (rid != null && rid != widget.roomId) return;
        final msg = (data is Map ? data['message'] : null)?.toString() ??
            'تم طردك من الغرفة';
        _showRoomSnack(msg, error: true);
        Navigator.of(context).maybePop();
      });

      SocketService().on('room_closed', (data) {
        if (!mounted) return;
        final rid = (data is Map) ? data['roomId'] : null;
        if (rid != null && rid != widget.roomId) return;
        _showRoomSnack('تم إغلاق الغرفة من قِبَل المالك', error: true);
        Navigator.of(context).maybePop();
      });

      // Dashboard force-closed the room → everyone inside leaves immediately.
      SocketService().on('room_force_closed', (data) {
        if (!mounted) return;
        final rid = (data is Map) ? data['roomId'] : null;
        if (rid != null && rid != widget.roomId) return;
        final msg = (data is Map ? data['reason'] : null)?.toString() ??
            'تم إغلاق الغرفة من الإدارة';
        _showRoomSnack(msg, error: true);
        Navigator.of(context).maybePop();
      });

      // Dashboard renamed the room → refresh so the watched name updates live.
      SocketService().on('room_updated', (data) {
        if (!mounted || data is! Map) return;
        final rid = data['roomId'];
        if (rid != null && rid != widget.roomId) return;
        ref.read(roomsProvider.notifier).loadRooms();
      });

      // ✅ LOAD INVENTORY FIRST
      await _loadActiveItems();
      debugPrint("🎬 video url = $_activeSeatEffectUrl");
      // ✅ set from REST list if available (prevents 1-seat fallback)
      final maxSeats = widget.maxSeats;
      if (maxSeats != null && maxSeats > 0) {
        controller.setSeatCountLocal(maxSeats);
      }

      // ✅ open room ONCE
      await controller.openRoom();

      final user = ref.read(authStateProvider).user;

      if (user != null) {
        controller.addOnlineUser(
          User(
            id: user.id,
            name: user.name ?? "Me",
          ),
        );
      }

      if (!_playedEntrance &&
          _activeSeatEffectUrl != null &&
          _activeSeatEffectUrl!.isNotEmpty) {

        _playedEntrance = true;
        // Route the entrance effect through the same serialized queue as other
        // seat effects so it never disposes a video that is mid-play (and vice
        // versa). Playing it directly here used to clobber an in-flight effect.
        _seatEffectQueue.add(_activeSeatEffectUrl!);
        _tryPlayNextEffect();
      }


      if (!_roomReady.isCompleted) _roomReady.complete();

      // optional: init audio service early (only if you want)
      final userId = ref.read(authStateProvider).user?.id;
      if (userId != null && !_audioReady) {
        await _audioService.initialize(
          roomId: widget.roomId,
          userId: userId,
          listenOnly: false,
        );
        _audioReady = true;
        // Step 5: report the perfect-mic self-test result to the room.
        SocketService().reportMicStatus(
          roomId: widget.roomId,
          ok: _audioService.micHealthy,
        );
      }

      _seatEffectSub = SocketService().seatEffectStream.listen((event) {

        final videoUrl = event['video'];

        _seatEffectQueue.add(videoUrl);

        _tryPlayNextEffect();

      });

      _socketErrSub = SocketService().errorStream.listen((msg) {
        if (!mounted) return;

        final normalized = msg.trim().toLowerCase();
        final isReconnectState = normalized.contains('connect') ||
            normalized.contains('reconnect') ||
            normalized.contains('transport close') ||
            normalized.contains('ping timeout');

        final text = isReconnectState
            ? 'Connecting…'
            : (msg.isNotEmpty ? msg : 'Socket error');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(text)),
        );
      });
    });

    SocketService().userEventStream.listen((event) {
      // Some backends omit roomId on user join/leave. Treat 0 as "current room".
      if (event.roomId != 0 && event.roomId != widget.roomId) return;
      final notifier = ref.read(roomControllerProvider(widget.roomId).notifier);

      if (event.type == UserEventType.joined) {
        notifier.addOnlineUser(
          User(
            id: event.userId,
            name: event.username,
          ),
        );
        notifier.addActivity(
          'انضم إلى الغرفة',
          RoomEventType.join,
          username: event.username,
        );
      }

      if (event.type == UserEventType.left) {
        notifier.removeOnlineUser(event.userId);
      }
    });

    // Legacy gift socket listeners removed.
    // GiftSocketService (bound above) feeds GiftAnimationOverlay,
    // which renders gift_sent / gift_legendary_incoming / gift_broadcast.
  }

  late final RoomLiveNotifier _live;

  @override
  bool _lifecycleLeft = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    super.didChangeAppLifecycleState(appState);
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    if (appState == AppLifecycleState.paused ||
        appState == AppLifecycleState.detached) {
      // Screen locked / app backgrounded → leave the room cleanly so other
      // devices don't keep showing a stale online/in-seat entry (presence desync).
      if (_lifecycleLeft) return;
      _lifecycleLeft = true;
      try { if (_audioReady) _audioService.muteAudio(); } catch (_) {}
      try { AudioController.instance.setMicEnabled(false); } catch (_) {}
      try {
        SocketService().leaveRoom(roomId: widget.roomId, userId: user.id);
      } catch (_) {}
    } else if (appState == AppLifecycleState.resumed && _lifecycleLeft) {
      _lifecycleLeft = false;
      // Back in foreground → re-join cleanly and re-sync seats.
      try {
        SocketService().joinRoom(
          roomId: widget.roomId,
          userId: user.id,
          username: user.name,
        );
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    // Close the room and dispose resources
    debugPrint('🟣 RoomScreen.dispose room=${widget.roomId}');
    AudioController.instance.deactivate();

    _audioPlayer.dispose();  // ✅ ADD
    _roomImageCtrl.dispose();
    _bgImageCtrl.dispose();
    _socketErrSub?.cancel();
    _joinDeniedSub?.cancel();
    _giftSocket.dispose();
    _audioService.dispose();
    _seatVideoController?.dispose();
    _externalTextController.dispose(); // Dispose the external controller
    _chatController.dispose();
    _chatFocus.dispose();
    _topChatFocus.dispose();
    _seatEffectSub?.cancel();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  void _sendText() {
    if (_externalTextController.text.isNotEmpty) {
      // Handle sending the message here
      debugPrint('Message sent: ${_externalTextController.text}');
      _externalTextController.clear(); // Clear the text field after sending
    }
  }
  bool _audioReady = false;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickAndUploadRoomImage(_RoomImageType type) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (picked == null) return;

    final url = await _uploadImageToServerFromXFile(picked);
    if (url == null) return;

    // If you still want to apply locally:
    if (type == _RoomImageType.roomImage) {
      ref.read(roomControllerProvider(widget.roomId).notifier).setRoomImageUrlLocal(url);
    } else {
      ref.read(roomControllerProvider(widget.roomId).notifier).setRoomBackgroundUrlLocal(url);
    }
  }

  Future<String?> _uploadImageToServer(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final filename = file.path.split('/').last;
      return await _uploadBytesToServer(bytes, filename);
    } catch (e) {
      debugPrint("❌ UPLOAD ERROR: $e");
      return null;
    }
  }

  Future<String?> _uploadImageToServerFromXFile(XFile xfile) async {
    try {
      final bytes = await xfile.readAsBytes();
      final filename = xfile.name.isNotEmpty ? xfile.name : 'image.jpg';
      return await _uploadBytesToServer(bytes, filename);
    } catch (e) {
      debugPrint("❌ UPLOAD ERROR: $e");
      return null;
    }
  }

  Future<String?> _uploadBytesToServer(Uint8List bytes, String filename) async {
    try {
      final form = FormData.fromMap({
        'image': MultipartFile.fromBytes(bytes, filename: filename),
      });
      final res = await DioClient.dio.post('/upload/image', data: form);
      final url = res.data?['imageUrl']?.toString();
      debugPrint("✅ Uploaded URL: $url");
      return url;
    } catch (e) {
      debugPrint("❌ UPLOAD ERROR: $e");
      return null;
    }
  }

  Future<void> _updateRoomImageInBackend(String imageUrl, {required bool isCover}) async {
    try {
      final dio = DioClient.dio;

      final body = isCover
          ? {"coverImageUrl": imageUrl}
          : {"backgroundImageUrl": imageUrl};

      await dio.patch(
        "/rooms/${widget.roomId}",   // ✅ REMOVE /api/v1
        data: body,
      );


      debugPrint("✅ Room image saved in database");
    } catch (e) {
      debugPrint("❌ Update room image failed: $e");
    }
  }

  /// #6: admin taps the room name/photo → dialog to edit the room name & cover.
  Future<void> _showEditRoomDialog() async {
    final current = ref.read(roomsProvider).findById(widget.roomId)?.name ?? '';
    final ctrl = TextEditingController(text: current);
    await showDialog(
      context: context,
      builder: (dctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E1347),
          title: const Text('تعديل الغرفة', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'اسم الغرفة',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                ),
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: () async {
                  Navigator.pop(dctx);
                  await _pickAndUploadRoomCover();
                },
                icon: const Icon(Icons.photo_camera, color: Color(0xFF4ECDC4)),
                label: const Text('تغيير صورة الغرفة', style: TextStyle(color: Color(0xFF4ECDC4))),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('إلغاء', style: TextStyle(color: Colors.white54))),
            TextButton(
              onPressed: () async {
                final newName = ctrl.text.trim();
                Navigator.pop(dctx);
                if (newName.isNotEmpty && newName != current) {
                  try {
                    await DioClient.dio.patch('/rooms/${widget.roomId}', data: {'name': newName});
                    await ref.read(roomControllerProvider(widget.roomId).notifier).loadRoomDetails();
                    if (mounted) setState(() {});
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر حفظ الاسم: $e')));
                    }
                  }
                }
              },
              child: const Text('حفظ', style: TextStyle(color: Color(0xFFFFD700))),
            ),
          ],
        ),
      ),
    );
  }

  /// Pick an image and set it as the room cover (used by the edit dialog).
  Future<void> _pickAndUploadRoomCover() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (picked == null) return;
      final uploaded = await _uploadImageToServerFromXFile(picked);
      if (uploaded != null && uploaded.isNotEmpty) {
        await _updateRoomImageInBackend(uploaded, isCover: true);
        await ref.read(roomControllerProvider(widget.roomId).notifier).loadRoomDetails();
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّر رفع الصورة: $e')));
      }
    }
  }


  /// Two ways to set a room background: pick from the store, or upload a file.
  Future<void> _openBackgroundChooser() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0E3E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text('تغيير خلفية الغرفة',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.storefront, color: Colors.amberAccent),
                title: const Text('اختيار من المتجر',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _openStoreBackgroundPicker();
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.upload_file, color: Colors.lightBlueAccent),
                title: const Text('رفع من الجهاز',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickUploadAndSaveRoomImage(isBackground: true);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Grid of store background products; tapping one sets it as the room bg.
  Future<void> _openStoreBackgroundPicker() async {
    List<dynamic> backgrounds = [];
    try {
      final res = await DioClient.dio.get('/store/products');
      final data = res.data?['data'];
      if (data is List) {
        backgrounds = data
            .where((p) => (p['type']?.toString() ?? '') == 'background')
            .toList();
      }
    } catch (e) {
      _showRoomSnack('تعذر تحميل الخلفيات: $e', error: true);
      return;
    }
    if (!mounted) return;
    if (backgrounds.isEmpty) {
      _showRoomSnack('لا توجد خلفيات في المتجر بعد', error: true);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0E3E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.6,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text('خلفيات المتجر',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.7,
                  ),
                  itemCount: backgrounds.length,
                  itemBuilder: (_, i) {
                    final p = backgrounds[i] as Map;
                    final url =
                        (p['preview_url'] ?? p['file_url'])?.toString() ?? '';
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        _setRoomBackgroundFromUrl(url);
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(fit: StackFit.expand, children: [
                          if (url.isNotEmpty)
                            Image.network(url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                    color: Colors.white10,
                                    child: const Icon(Icons.image,
                                        color: Colors.white30)))
                          else
                            Container(color: Colors.white10),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              color: Colors.black54,
                              child: Text((p['name']?.toString() ?? ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                            ),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setRoomBackgroundFromUrl(String url) async {
    if (url.isEmpty) return;
    try {
      await _api.updateRoomBackground({
        'roomId': widget.roomId,
        'room_id': widget.roomId,
        'backgroundImageUrl': url,
      });
      ref
          .read(roomControllerProvider(widget.roomId).notifier)
          .setRoomBackgroundUrlLocal(url);
      _showRoomSnack('تم تعيين خلفية الغرفة');
    } catch (e) {
      _showRoomSnack('تعذر تعيين الخلفية: $e', error: true);
    }
  }

  Future<void> _pickUploadAndSaveRoomImage({
    required bool isBackground,
  }) async {
    try {
      // Uploading a custom background from the device costs 20,000 coins.
      if (isBackground) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF2A1A5E),
            title: const Text('خلفية مخصصة', style: TextStyle(color: Colors.white)),
            content: const Text('سيتم خصم 20,000 كوينز لرفع خلفية من جهازك. متابعة؟',
                style: TextStyle(color: Colors.white70)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('متابعة')),
            ],
          ),
        );
        if (ok != true) return;
      }

      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (picked == null) return;

      // 1️⃣ Upload image (bytes-based, works on web + mobile)
      final uploadedUrl = await _uploadImageToServerFromXFile(picked);
      if (uploadedUrl == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upload failed')),
          );
        }
        return;
      }

      // 2️⃣ Save in database. Backgrounds go through the room-admin endpoint
      // (persists + broadcasts room_background_changed + works for admins, not
      // just the owner). Cover image still uses the owner PATCH.
      if (isBackground) {
        await _api.updateRoomBackground({
          'roomId': widget.roomId,
          'room_id': widget.roomId,
          'backgroundImageUrl': uploadedUrl,
          'chargeUpload': true,
        });
      } else {
        await _updateRoomImageInBackend(uploadedUrl, isCover: true);
      }

      // 3️⃣ Update local UI
      final notifier =
      ref.read(roomControllerProvider(widget.roomId).notifier);

      if (isBackground) {
        notifier.setRoomBackgroundUrlLocal(uploadedUrl);
      } else {
        notifier.setRoomImageUrlLocal(uploadedUrl);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isBackground
                  ? 'Background updated successfully'
                  : 'Room image updated successfully',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _openMessagesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6, // ✅ 60% height
          minChildSize: 0.35,    // collapsed
          maxChildSize: 0.95,    // expanded
          expand: false,
          builder: (context, scrollController) {
            return BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0F0F12),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
              ),
              child: Column(
                children: [
                  // ===== Drag Handle =====
                  const SizedBox(height: 10),
                  Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ===== Header =====
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.message, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          "الرسائل",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 11),

                  // ===== CONTENT =====
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(22),
                      ),
                      child: StatefulBuilder(
                        builder: (context, setModalState) {
                          // 👇 if chat is opened
                          if (_activeConversationId != null) {
                            return ChatScreen(
                              partnerId: _activeUserId!,
                              partnerName: _activeUserName!,
                              partnerAvatarUrl: _activeAvatar,
                              onBack: () {
                                setModalState(() {
                                  _activeConversationId = null;
                                });
                              },
                            );
                          }

                          // 👇 otherwise show conversations list
                          return MessagesScreen(
                            onOpenChat: (c) {
                              setModalState(() {
                                _activeConversationId = c.conversationId;
                                _activeUserId = c.partnerId;
                                _activeUserName = c.partnerName;
                                _activeAvatar = c.partnerAvatar;
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
                )
            );
          },
        );
      },
    );
  }

  void _openUsersList(BuildContext context, state) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141418),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        final users = state.onlineUsers.values.toList();

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (_, index) {
            final user = users[index];

            SeatData? seat;
            for (final s in state.seats.values) {
              if (s.userId == user.id) {
                seat = s;
                break;
              }
            }

            final isOnSeat = seat != null;

            return ListTile(
              leading: CircleAvatar(
                backgroundImage: user.avatarUrl != null
                    ? NetworkImage(user.avatarUrl!)
                    : null,
                child: user.avatarUrl == null
                    ? const Icon(Icons.person)
                    : null,
              ),
              title: Text(user.name, style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                isOnSeat
                    ? 'On seat #${seat.seatNumber}'
                    : 'Listener',
                style: TextStyle(
                  color: isOnSeat ? Colors.greenAccent : Colors.white54,
                ),
              ),
              trailing: Icon(
                isOnSeat ? Icons.mic : Icons.headphones,
                color: isOnSeat ? Colors.green : Colors.grey,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveRoomImagesFromBottomBar({
    required _RoomImageType type,
    required String url,
  }) async {
    await _roomReady.future;

    final notifier = ref.read(roomControllerProvider(widget.roomId).notifier);

    try {
      if (type == _RoomImageType.roomImage) {
        (notifier as dynamic).setRoomImageUrlLocal(url);
      } else {
        (notifier as dynamic).setRoomBackgroundUrlLocal(url);
      }
    } catch (e) {
      debugPrint('⚠️ Missing notifier methods for room images: $e');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(type == _RoomImageType.roomImage
              ? 'Room image updated'
              : 'Background updated'),
        ),
      );
    }
  }

  void _openGamesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6, // ✅ 60% height
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0F0F12),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),

                  // drag handle
                  Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // header
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.sports_esports, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          "الألعاب",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // ✅ GAME SCREEN
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(22),
                      ),
                      child: const GamesHubScreen(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openMoreMenu(BuildContext context) {
    final auth = ref.read(authStateProvider);
    final state = ref.read(roomControllerProvider(widget.roomId));

    final userId = auth.user?.id;

    final room = ref.read(roomsProvider).findById(widget.roomId);
    final restOwnerId = room?.ownerId ?? room?.owner?.id ?? 0;

    final isAdmin = userId != null &&
        (userId == state.ownerId ||
            state.adminIds.contains(userId) ||
            userId == restOwnerId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            decoration: const BoxDecoration(
              color: Color(0xFF2A1655),
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                // 🔘 handle
                Container(
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),

                const SizedBox(height: 20),

                // =======================
                // ⭐ POPULAR
                // =======================
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "الوظائف شائعة الاستخدام",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _menuItem(Icons.flag, "مركز الفعاليات", Colors.amber, () {
                      Navigator.pop(context);
                      _openEventsCenter(this.context);
                    }),
                    _menuItem(Icons.backpack, "حقيبة الظهر", Colors.lightBlueAccent, () {
                      Navigator.pop(context);
                      _openBackpackSheet(this.context);
                    }),
                  ],
                ),



                const SizedBox(height: 16),

                if (isAdmin) ...[

                  // =======================
                  // 🛠 ADMIN
                  // =======================
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      "إدارة الغرفة",
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 🔥 ROW 1
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Consumer(builder: (ctx, wref, _) {
                        final locked = wref
                                .watch(roomsProvider)
                                .findById(widget.roomId)
                                ?.isRoomLocked ??
                            false;
                        return _menuItem(
                          locked ? Icons.lock_open : Icons.lock,
                          locked ? "فتح الغرفة" : "قفل الغرفة",
                          Colors.white70,
                          () {
                            Navigator.pop(context);
                            _toggleRoomLock();
                          },
                        );
                      }),
                      _menuItem(Icons.admin_panel_settings, "مسؤول الغرفة", Colors.white70, () {
                        Navigator.pop(context);
                        _openManageAdminsDialog(this.context);
                      }),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // 🔥 ROW 2
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _menuItem(Icons.bar_chart, "نمط الميكروفون", Colors.white70, () {
                        Navigator.pop(context);
                        _openSeatCountDialog(this.context);
                      }),
                      _menuItem(Icons.image, "خلفية الغرفة", Colors.white70, () {
                        Navigator.pop(context);
                        _openBackgroundChooser();
                      }),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // 🔥 ROW 3
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _menuItem(Icons.block, "قائمة الحظر", Colors.white70, () {
                        Navigator.pop(context);
                        _openBanListDialog(this.context);
                      }),
                      _menuItem(Icons.delete_outline, "حذف الدردشة", Colors.redAccent, () {
                        Navigator.pop(context);
                        _clearRoomChat();
                      }),
                    ],
                  ),

                  const SizedBox(height: 22),
                ],

                const SizedBox(height: 22),

                // =======================
                // ⚙️ MAIN GRID (LIKE IMAGE)
                // =======================
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "الوظائف الأساسية",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),

                const SizedBox(height: 16),

                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 5,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.75,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [

                    _menuItem(Icons.music_note, "موسيقى",
                        _musicOn ? Colors.greenAccent : Colors.white70, () {
                          Navigator.pop(context);
                          _toggleMusicSetting();
                        }),

                    _menuItem(Icons.hearing, "تقليل الضوضاء",
                        _noiseReduction ? Colors.greenAccent : Colors.white70, () {
                          Navigator.pop(context);
                          _toggleNoiseReduction();
                        }),

                    _menuItem(Icons.volume_up, "مستوى الصوت", Colors.white70, () {
                      Navigator.pop(context);
                      _openVolumeDialog(this.context);
                    }),

                    _menuItem(Icons.multitrack_audio, "مؤثرات صوتية", Colors.white70, () {
                      Navigator.pop(context);
                      _openSoundEffectsDialog(this.context);
                    }),

                    _menuItem(Icons.mic, "ميكروفون", Colors.white70, () async {
                      Navigator.pop(context);
                      await _toggleMicFromMenu();
                    }),

                    _menuItem(Icons.share, "مشاركة", Colors.white70, () {
                      Navigator.pop(context);
                      _shareRoom();
                    }),

                    _menuItem(Icons.report, "إبلاغ", Colors.white70, () {
                      Navigator.pop(context);
                      _openReportDialog(this.context);
                    }),

                    _menuItem(Icons.delete, "حذف الدردشة", Colors.white70, () {
                      Navigator.pop(context);
                      if (isAdmin) {
                        _clearRoomChat();
                      } else {
                        _showRoomSnack('مسح الدردشة متاح للمسؤولين فقط', error: true);
                      }
                    }),

                    // #17-18: manual reset of the per-user 24h coin counter shown
                    // under each seat. Was buried inside the unrelated "Sound
                    // Effects" dialog, which is why the owner couldn't find it
                    // ("موضوع التصفير مش لاقيه") — it now lives as its own item
                    // here, next to the other admin actions.
                    _menuItem(Icons.restart_alt, "تصفير عدّاد الكوينزات", Colors.orangeAccent, () async {
                      Navigator.pop(context);
                      if (!isAdmin) {
                        _showRoomSnack('التصفير متاح لصاحب الغرفة أو المشرفين فقط', error: true);
                        return;
                      }
                      try {
                        await DioClient.dio.post('/room-admin/reset-earnings', data: {
                          'roomId': widget.roomId,
                          'room_id': widget.roomId,
                        });
                        await ref.read(roomControllerProvider(widget.roomId).notifier).refreshSeatEarnings();
                        _showRoomSnack('تم تصفير العدّادات');
                      } catch (e) {
                        _showRoomSnack('تعذر التصفير: $e', error: true);
                      }
                    }),

                    _menuItem(Icons.settings, "إعدادات الصوت", Colors.white70, () {
                      Navigator.pop(context);
                      _openAudioSettingsDialog(this.context);
                    }),

                  ],
                ),

                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _startLocalMic() async {
    final userId = ref.read(authStateProvider).user?.id;
    if (userId == null) return;

    final ok = await _ensureMicPermission();
    if (!ok) {
      debugPrint('❌ Mic permission denied');
      return;
    }


    debugPrint('🎧 unmute audio...');
    await _audioService.unmuteAudio();
  }



  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final state = ref.watch(roomControllerProvider(widget.roomId));
    final userId = auth.user?.id;

    // Step 10: when an admin force-mutes me, cut my live mic immediately.
    ref.listen(roomControllerProvider(widget.roomId), (prev, next) {
      final me = ref.read(authStateProvider).user?.id;
      if (me == null) return;
      final wasForced = prev?.seats.values
          .any((s) => s.userId == me && s.forceMuted) ?? false;
      final isForced = next.seats.values
          .any((s) => s.userId == me && s.forceMuted);
      if (isForced && !wasForced) {
        AudioController.instance.setMicEnabled(false);
        if (_audioReady) _audioService.muteAudio();
        _showRoomSnack('تم كتمك من قبل المشرف');
      }
    });

    final room = ref.watch(roomsProvider).findById(widget.roomId);
    final restOwnerId = room?.ownerId ?? room?.owner?.id ?? 0;
    final roomName = (room?.name ?? '').trim();

    final isAdmin = userId != null &&
        (userId == state.ownerId || state.adminIds.contains(userId) || userId == restOwnerId);

    final size = MediaQuery.of(context).size;
    final kb = MediaQuery.of(context).viewInsets.bottom;




    // ✅ main sizes
    const bottomBarH = 64.0;
    final chatH = size.height * 0.30;

    // ✅ Activity should be 30% of chat height
    final activityH = chatH * 0.30;

    // ✅ Right side chat width (like you had)
    final chatW = size.width * 0.62;

    // ✅ Activity panel is left next to chat => use remaining width
    final activityW = (size.width - chatW - 8 - 8 - 8).clamp(120.0, size.width);
    // 8 left margin + 8 gap + 8 right padding feel

    // Find my seat
    int? mySeatNumber;
    bool mySeatMuted = true;
    for (final seat in state.seats.values) {
      if (seat.userId != null &&
          seat.userId.toString() == userId.toString()) {
        mySeatNumber = seat.seatNumber;
        mySeatMuted = seat.isMuted;
        break;
      }
    }

    Widget _buildPip() {
      final state = ref.watch(roomControllerProvider(widget.roomId));

      // find if I'm on a seat (for mic glow)
      final userId = ref.read(authStateProvider).user?.id;
      final onSeat = state.seats.values.any((s) => s.userId == userId);

      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // ── semi-transparent full bg so taps outside work ──
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _isMinimized = false),
                child: Container(color: Colors.black.withOpacity(0.01)),
              ),
            ),

            // ── draggable pip bubble ──
            Positioned(
              left: _pipOffset.dx,
              top: _pipOffset.dy,
              child: GestureDetector(
                onPanUpdate: (d) => setState(() {
                  _pipOffset += d.delta;
                }),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 90,
                    height: 110,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2A1655), Color(0xFF6B4CE6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6B4CE6).withOpacity(0.5),
                          blurRadius: 18,
                          spreadRadius: 2,
                        )
                      ],
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [

                        // room image
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: onSeat && !_currentSeatMuted
                                  ? Colors.greenAccent
                                  : Colors.white24,
                              width: onSeat && !_currentSeatMuted ? 2.5 : 1,
                            ),
                            image: (state.roomImageUrl ?? '').trim().isNotEmpty
                                ? DecorationImage(
                              image: NetworkImage(state.roomImageUrl!.trim()),
                              fit: BoxFit.cover,
                            )
                                : null,
                          ),
                          child: (state.roomImageUrl ?? '').trim().isEmpty
                              ? const Icon(Icons.mic, color: Colors.white, size: 22)
                              : null,
                        ),

                        const SizedBox(height: 6),

                        // room name
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            (ref.watch(roomsProvider).findById(widget.roomId)?.name ?? 'Room').trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        const SizedBox(height: 6),

                        // action row: expand + leave
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // expand
                            GestureDetector(
                              onTap: () => setState(() => _isMinimized = false),
                              child: const Icon(Icons.open_in_full, color: Colors.white70, size: 16),
                            ),
                            // leave room
                            GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: const Icon(Icons.close, color: Colors.redAccent, size: 16),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final ready = _roomReady.isCompleted;

    // Handle seat/mute changes after each build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentSeatNumber != mySeatNumber || _currentSeatMuted != mySeatMuted) {
        _handleSeatChange(mySeatNumber, mySeatMuted);
      }
    });

    // ✅ compute seats height so it doesn't fill the screen
    // header ~ 70, padding ~ 24 => keep safe and stable
    const headerApproxH = 72.0;
    const topPaddingApproxH = 16.0;
    final overlaysTotalH = bottomBarH + chatH + 16; // bottom bar + panels area + gap

    final availableForSeats = (size.height - headerApproxH - topPaddingApproxH - overlaysTotalH)
        .clamp(180.0, size.height);
    bool isKeyboardVisible = kb > 0;  // Check if the keyboard is visible

    final bottomMargin = size.height * 0.09; // 5% bottom margin
    final seatsH = size.height * 0.50;

    final onlineCount = state.onlineUsers.length;

    if (_isMinimized) return _buildPip();

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Stack(
          key: _overlayKey,
          children: [
            // ===== Background image =====
            if ((state.roomBackgroundUrl ?? '').trim().isNotEmpty)
              Positioned.fill(
                child: Image.network(
                  state.roomBackgroundUrl!.trim(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),

            if (_showGlow)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _showGlow ? 0.6 : 0,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            _glowColor.withOpacity(0.8),
                            Colors.transparent,
                          ],
                          radius: 0.8,
                        ),
                      ),
                    ),
                  ),
                ),
              ),


// ===== Seat video overlay =====
            if (_showSeatVideo && _seatVideoController != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 400),
                    opacity: _showSeatVideo ? 1 : 0,
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 600),
                      tween: Tween(begin: 1.2, end: 1.0), // 🔥 zoom out effect
                      builder: (context, scale, child) {
                        return Transform.scale(
                          scale: scale,
                          child: child,
                        );
                      },
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _seatVideoController!.value.size.width,
                          height: _seatVideoController!.value.size.height,
                          child: VideoPlayer(_seatVideoController!),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // dark overlay
            Positioned.fill(
              child: IgnorePointer(
                child: Container(color: Colors.black.withOpacity(0.45)),
              ),
            ),



            // ===== Main content =====
            Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: isAdmin ? _showEditRoomDialog : null,
                        child: CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.deepPurple,
                        backgroundImage: (state.roomImageUrl ?? '').trim().isNotEmpty
                            ? NetworkImage(state.roomImageUrl!.trim())
                            : null,
                        child: (state.roomImageUrl ?? '').trim().isNotEmpty
                            ? null
                            : const Icon(Icons.mic, color: Colors.white),
                      ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: isAdmin ? _showEditRoomDialog : null,
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              roomName.isNotEmpty ? roomName : 'Room #${widget.roomId}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Builder(builder: (_) {
                              final ownerDid = room?.owner?.publicDisplayId;
                              if (ownerDid == null || ownerDid == 0) return const SizedBox.shrink();
                              return Text(
                                'ID: $ownerDid',
                                style: const TextStyle(color: Colors.white60, fontSize: 11),
                              );
                            }),
                          ],
                        ),
                        ),
                      ),

                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => _openUsersList(context, state),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.remove_red_eye, color: Colors.white70, size: 16),
                                const SizedBox(width: 5),
                                Text('${state.voiceUserIds.length}'),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(width: 6),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _showModerationSheet(context),
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(Icons.gavel, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),

                      // ✅ ADD before the close IconButton in the header Row
                      if (!_isMinimized)
                        IconButton(
                          icon: const Icon(Icons.picture_in_picture_alt, color: Colors.white70, size: 20),
                          onPressed: () {
                            final state = ref.read(roomControllerProvider(widget.roomId));
                            ref.read(pipProvider.notifier).activate(
                              roomId: widget.roomId,
                              roomName: ref.read(roomsProvider).findById(widget.roomId)?.name,
                              roomImageUrl: state.roomImageUrl,
                            );
                            Navigator.of(context).pop(); // ✅ pop room screen, pip stays floating
                          },
                        ),

                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF2A1655),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              title: const Text(
                                'مغادرة الغرفة',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.right,
                              ),
                              content: const Text(
                                'هل أنت متأكد أنك تريد مغادرة الغرفة؟',
                                style: TextStyle(color: Colors.white70),
                                textAlign: TextAlign.right,
                              ),
                              actionsAlignment: MainAxisAlignment.start,
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text(
                                    'إلغاء',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(ctx); // close dialog
                                    Navigator.of(context).pop(); // leave room
                                  },
                                  child: const Text(
                                    'مغادرة',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),


                // ✅ Seats area NOT full screen (fixed height)
                SizedBox(
                  height: seatsH,
                  child: ClipPath(
                    clipper: BottomWaveClipper(depth: 40), // 👈 ADD THIS
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SeatsGrid(
                        seats: state.seats,
                        seatCount: state.seatCount,
                        seatKeys: _seatKeys,
                        myUserId: userId ?? 0,
                        isAdmin: isAdmin,
                        lockedSeats: state.lockedSeats,
                        mutedSeats: state.mutedSeats,
                        ownerId: state.ownerId,
                        adminIds: state.adminIds,
                        seatEarnings: state.seatEarnings24h,
                          onSeatTap: (seatNumber, seat) {
                            _onSeatTap(context, seatNumber, seat, userId ?? 0, isAdmin);
                          }
                      ),
                    ),
                  ),
                ),

                // ✅ leave some air under seats so panels don't feel stuck
                const SizedBox(height: 12),

                // Remaining space (empty / background)
                const Expanded(child: SizedBox()),
              ],
            ),




            // ==========================================================
            // ✅ Bottom panels: Activity LEFT next to Chat (horizontal)
            // Activity height = 30% of chat height, showing ~3 lines
            // ==========================================================
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomBarH + 10,
              child: Center(
                child: Transform.translate(
                  offset: const Offset(0, -55), // 🔥 deeper overlap
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.90,
                    height: MediaQuery.of(context).size.height * 0.30,
                    child: RoomChatPanel(roomId: widget.roomId),
                  ),
                ),
              ),
            ),


            if (_showChatPanel)
              Positioned(
                left: 8,
                right: 8,
                bottom: kb > 0 ? kb : _bottomBarH + 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _externalTextController,
                          focusNode: _topChatFocus,
                          autofocus: true,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) {
                            _sendText();
                            _closeChat();
                          },
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'اكتب رسالتك...',
                            hintStyle: TextStyle(color: Colors.white54),
                            border: InputBorder.none,
                          ),
                        )
                      ),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: () {
                            final text = _externalTextController.text.trim();
                            if (text.isEmpty) return;

                            ref.read(roomControllerProvider(widget.roomId).notifier)
                                .sendRoomMessage(message: text);

                            _externalTextController.clear();

                            _closeChat();

                            // ✅ ADD THIS
                            _topChatFocus.unfocus();

                            // ✅ AND THIS (optional but cleaner)
                            setState(() {
                              _showChatPanel = false;
                            });
                          }
                      )
                    ],
                  ),
                ),
              ),

            // ===== Bottom bar =====
            // ===== NEW MODERN BOTTOM BAR =====
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                  child: SizedBox(
                      height: 52,
                      child: Row(
                      children: [

                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(100),
                              onTap: () {
                                setState(() {
                                  _showChatPanel = true;
                                });

                                // 🔥 FORCE rebuild + focus properly
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  _topChatFocus.requestFocus();
                                });
                              },
                              child: Container(
                                height: double.infinity,
                                margin: const EdgeInsets.symmetric(horizontal: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                    color: Colors.deepPurpleAccent,
                                    width: 1.5,
                                  ),
                                ),
                                alignment: Alignment.centerLeft,
                                child: const Row(
                                  children: [
                                    Icon(Icons.chat_bubble_outline,
                                        color: Colors.white54, size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      "تكلم  ...",
                                      style: TextStyle(color: Colors.white54),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // 🎁 GIFT
                        GestureDetector(
                          onTap: () {
                            final state = ref.read(roomControllerProvider(widget.roomId));
                            final auth = ref.read(authStateProvider);
                            final me = auth.user;
                            if (me == null) return;
                            // Collect all room users (incl. seated + online), self always included.
                            final ids = <int>{};
                            final list = <GiftRecipient>[];
                            void add(int id, String name, String? avatarUrl, {int? seatNumber}) {
                              if (ids.add(id)) {
                                list.add(GiftRecipient(id: id, name: name, avatarUrl: avatarUrl, seatNumber: seatNumber));
                              }
                            }
                            // Self first
                            add(me.id, me.name ?? 'أنا', me.avatarUrl);
                            // Seated users
                            for (final s in state.seats.values) {
                              if (s.userId != null) {
                                add(s.userId!, s.username ?? 'User #${s.userId}', s.avatarUrl, seatNumber: s.seatNumber);
                              }
                            }
                            // Other online users
                            for (final u in state.onlineUsers.values) {
                              add(u.id, u.name ?? 'User #${u.id}', u.avatarUrl);
                            }
                            GiftPickerSheet.show(
                              context,
                              repository: _giftRepository,
                              recipients: list,
                              roomId: widget.roomId,
                              balance: me.coinsBalance ?? me.coins ?? 0,
                              onBalanceChanged: (_) {},
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(Icons.card_giftcard, color: Colors.purpleAccent),
                          ),
                        ),

                        Consumer(
                          builder: (context, ref, _) {
                            final unread = ref.watch(unreadCountProvider);

                            return GestureDetector(
                              onTap: () {
                                _openMessagesSheet(context);
                              },
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  const Icon(Icons.message, color: Colors.white),

                                  if (unread > 0)
                                    Positioned(
                                      right: -6,
                                      top: -6,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                        child: Text(
                                          unread > 99 ? '99+' : '$unread',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),

                        if (_currentSeatNumber != null)
                          GestureDetector(
                            onTap: () async {
                              final userId = ref.read(authStateProvider).user?.id;
                              if (userId == null) return;
                              final isMicTurningOn = _currentSeatMuted;
                              await AudioController.instance.setMicEnabled(isMicTurningOn);

                              ref.read(roomControllerProvider(widget.roomId).notifier).toggleMute(
                                seatNumber: _currentSeatNumber!,
                                isMuted: !_currentSeatMuted,
                                targetUserId: userId,
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Icon(
                                _currentSeatMuted ? Icons.mic_off : Icons.mic,
                                color: _currentSeatMuted ? Colors.red : Colors.greenAccent,
                              ),
                            ),
                          ),

                        GestureDetector(
                          onTap: () {
                            _openGamesSheet(context);
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(
                              Icons.sports_esports,
                              color: Colors.greenAccent,
                            ),
                          ),
                        ),

                        GestureDetector(
                          onTap: () {
                            _openMoreMenu(context); // 👈 we create this next
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(
                              Icons.grid_view_rounded, // 🔥 THIS IS THE SAME STYLE
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),

                      ],
                    )
                  )
                ),
              ),
            ),

            // ===== Gift flight overlay (rendered LAST so it paints ABOVE seats) =====
            Positioned.fill(
              child: GiftAnimationOverlay(
                socket: _giftSocket,
                resolvePosition: _getSeatPositionByUser,
              ),
            ),

            // ===== Group 12: user entrance banner (slides in → pause → out) =====
            Positioned.fill(
              child: EntranceBannerLayer(roomId: widget.roomId),
            ),
          ],
        ),
      ),
    );
  }


  /// Handle seat changes to initialize or dispose audio and emit socket events.
  Future<void> _handleSeatChange(int? newSeatNumber, bool newMuted) async {
    final prevSeat = _currentSeatNumber;

    final userId = ref.read(authStateProvider).user?.id;
    if (userId == null) return;


    final prevMuted = _currentSeatMuted;

    // Update tracking FIRST to prevent duplicate async calls on rebuilds
    _currentSeatNumber = newSeatNumber;
    _currentSeatMuted = newMuted;

    debugPrint('🎧 seatChange room=${widget.roomId} prevSeat=$prevSeat prevMuted=$prevMuted -> newSeat=$newSeatNumber newMuted=$newMuted');

// Sit down (with mic permission)
    if (prevSeat == null && newSeatNumber != null) {



      final ok = await _ensureMicPermission();
      if (!ok) {
        debugPrint('❌ Mic permission denied');
        return;
      }



// ✅ Respect seat mute state when sitting
      if (prevSeat == null && newSeatNumber != null) {
        final ok = await _ensureMicPermission();
        if (!ok) {
          debugPrint('❌ Mic permission denied');
          return;
        }
        if (!_audioReady) {
        await _audioService.initialize(
          roomId: widget.roomId,
          userId: userId,
          listenOnly: true, // ✅ listen-only before taking a seat
        );
        _audioReady = true;
        }

        // ✅ Respect seat mute state when sitting
        if (newMuted) {
          await _audioService.muteAudio();   // speaker ON (listening)
        } else {
          await _audioService.unmuteAudio(); // earpiece (talking)
        }

        // Step 5: seated speaker — report perfect-mic status to the room.
        SocketService().reportMicStatus(
          roomId: widget.roomId,
          ok: _audioService.micHealthy,
        );

        return;
      }

    }


// Leave seat
    if (prevSeat != null && newSeatNumber == null) {
      await _audioService.muteAudio();
      return;
    }


    // Still seated, mute changed
    if (newSeatNumber != null && prevMuted != newMuted) {
      debugPrint('🎧 mute changed while seated room=${widget.roomId} seat=$newSeatNumber muted=$newMuted');
      if (newMuted) {
        _audioService.muteAudio();
      } else {
        _audioService.unmuteAudio();
      }
    }
  }

  void _openGiftSheetToUser(BuildContext context, _Recipient r) {
    final auth = ref.read(authStateProvider);
    if (auth.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login first')),
      );
      return;
    }
    final me = auth.user!;
    final state = ref.read(roomControllerProvider(widget.roomId));
    final ids = <int>{};
    final list = <GiftRecipient>[];
    void add(int id, String name, String? avatarUrl, {int? seatNumber}) {
      if (ids.add(id)) list.add(GiftRecipient(id: id, name: name, avatarUrl: avatarUrl, seatNumber: seatNumber));
    }
    // Pre-selected user first, self, then everyone else
    add(r.id, r.name, r.avatarUrl);
    add(me.id, me.name ?? 'أنا', me.avatarUrl);
    for (final s in state.seats.values) {
      if (s.userId != null) add(s.userId!, s.username ?? 'User #${s.userId}', s.avatarUrl, seatNumber: s.seatNumber);
    }
    for (final u in state.onlineUsers.values) {
      add(u.id, u.name ?? 'User #${u.id}', u.avatarUrl);
    }

    GiftPickerSheet.show(
      context,
      repository: _giftRepository,
      recipients: list,
      initialRecipientIds: [r.id],
      roomId: widget.roomId,
      balance: auth.user?.coinsBalance ?? auth.user?.coins ?? 0,
      onBalanceChanged: (_) {},
    );
  }


  Future<void> _openDirectChat(_Recipient r) async {
    if (!mounted) return;

    final convo = await MessageRepository().getOrCreateConversation(r.id);
    if (!mounted) return;

    Navigator.of(context).pushNamed(
      '/chat',
      arguments: {
        'conversationId': convo.conversationId, // ✅ IMPORTANT
        'partnerId': convo.partnerId,
        'partnerName': convo.partnerName,
      },
    );
  }

  void _openMessageSheetToUser(BuildContext context, _Recipient r) {
    final ctrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0F0F12),
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundImage: r.avatarUrl != null ? NetworkImage(r.avatarUrl!) : null,
                        child: r.avatarUrl == null
                            ? const Icon(Icons.person, color: Colors.white, size: 18)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Message to ${r.name}',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 3,
                    minLines: 1,
                    decoration: InputDecoration(
                      hintText: 'Type message...',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.send),
                          label: const Text('Send'),
                          onPressed: () async {
                            final text = ctrl.text.trim();
                            if (text.isEmpty) return;

                            Navigator.pop(context);

                            // ✅ IMPORTANT:
                            // You MUST wire this to YOUR chat/socket method.
                            // This dynamic call will compile even if you rename methods.
                            try {
                              // Option A (if you already have something similar)
                              (ref.read(roomControllerProvider(widget.roomId).notifier) as dynamic)
                                  .sendRoomMessage(toUserId: r.id, message: text);
                            } catch (_) {
                              try {
                                // Option B (if SocketService has a chat emit method)
                                (SocketService() as dynamic).sendRoomMessage(
                                  roomId: widget.roomId,
                                  toUserId: r.id,
                                  message: text,
                                );
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Wire message send method first: $e')),
                                  );
                                }
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Show seat actions for admins/occupants
  void _onSeatTap(
      BuildContext context,
      int seatNumber,
      SeatData seat,
      int myUserId,
      bool isAdmin,
      ) {

    debugPrint("👉 SEAT FRAME URL: ${seat.avatarFrameUrl}");

    final isLocked = ref.read(roomControllerProvider(widget.roomId)).lockedSeats.contains(seatNumber);

    if (seat.userId == null && isLocked && !isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This seat is locked 🔒')),
      );
      return;
    }

    // ==========================
    // EMPTY SEAT → TAKE SEAT
    // ==========================

    if (seat.userId == null) {

      // NOTE: compute whether the tapper is already seated BEFORE the admin
      // shortcut, so a seated admin/owner can still move to the empty seat.
      // (Previously admins were routed straight to the lock/mute sheet and
      // could never move — that was #10 "seat move option doesn't work".)
      int? myCurrentSeat;
      final state = ref.read(roomControllerProvider(widget.roomId));

      for (final s in state.seats.values) {
        if (s.userId != null &&
            s.userId.toString() == myUserId.toString()) {
          myCurrentSeat = s.seatNumber;
          break;
        }
      }

      // Admin/owner → full seat controls (lock / mute / invite / sit / move).
      // This must come BEFORE the move-only sheet so admins don't lose access
      // to the moderation options (that regression was #11/#12 not opening).
      if (isAdmin) {
        _showEmptySeatAdminSheet(context, seatNumber, myCurrentSeat: myCurrentSeat);
        return;
      }

      // ==========================
      // 🟣 USER ALREADY ON SEAT → SHOW SIMPLE MODAL
      // ==========================
      if (myCurrentSeat != null) {

        showModalBottomSheet(
          context: context,
          backgroundColor: const Color(0xFF2A1655),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          builder: (_) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    const Text(
                      "تبديل مقعد الميكروفون",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 20),

                    Divider(color: Colors.white.withOpacity(0.2)),

                    const SizedBox(height: 10),

                    // ✅ CONFIRM BUTTON
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);

                        ref.read(roomControllerProvider(widget.roomId).notifier)
                            .moveSeat(
                          fromSeat: myCurrentSeat!,
                          toSeat: seatNumber,
                        );
                      },
                      child: const Text(
                        "تأكيد",
                        style: TextStyle(color: Colors.greenAccent),
                      ),
                    ),

                    // ❌ CANCEL (no movement)
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        "إلغاء",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                        ),
                      ),
                    ),

                  ],
                ),
              ),
            );
          },
        );

        return;
      }

      // ==========================
      // 🟢 USER NOT SEATED → TAKE SEAT
      // ==========================
      ref.read(roomControllerProvider(widget.roomId).notifier)
          .takeSeat(seatNumber: seatNumber);

      return;
    }

    final isMine = seat.userId == myUserId;

    // Relation-seat leave has its own special sheet
    if (isMine && seat.relationPartner != null) {
      _showLeaveSeatSheet(context, seatNumber, seat);
      return;
    }

    // ── Unified profile dialog (self / admin / regular user) ──
    // Fetched once, outside the builder, so sheet-internal rebuilds (e.g.
    // OnlineDot ticking) don't refire the request. Only real user data is
    // ever shown here — age/gender/country/agency-role/family/medals stay
    // hidden until this resolves rather than showing placeholders.
    final profileFuture = UserRepository().getUserProfile(seat.userId!);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        // Capped at 50% of the screen — this card must never take over the
        // whole view.
        final maxHeight = MediaQuery.of(context).size.height * 0.5;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E1347), Color(0xFF2B1760), Color(0xFF1A1040)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  // HANDLE
                  Container(
                    width: 50, height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 18),



                  // ── BANNER HEADER ──
                  // Artwork background + right-aligned identity block, with
                  // the avatar overlapping the top-right corner. Matches the
                  // reference card layout. When no card artwork asset exists
                  // yet the gradient below stands in for it, so the layout is
                  // final and only the image drops in later.
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 150),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          // Gradient shows through if the asset is missing, so
                          // the card degrades to a solid look instead of a
                          // broken-image box.
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4C1D95), Color(0xFF6D28D9), Color(0xFF3B1173)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          image: DecorationImage(
                            image: const AssetImage(_profileCardBackground),
                            fit: BoxFit.cover,
                            onError: (_, __) {},
                            colorFilter: ColorFilter.mode(
                              Colors.black.withOpacity(0.15),
                              BlendMode.darken,
                            ),
                          ),
                        ),
                        child: Padding(
                          // Right padding leaves room for the overlapping avatar.
                          padding: const EdgeInsets.fromLTRB(14, 22, 104, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // NAME + flag
                              FutureBuilder<Result<User>>(
                                future: profileFuture,
                                builder: (context, snapshot) {
                                  final profile =
                                      snapshot.data?.isSuccess == true ? snapshot.data!.data : null;
                                  final flag = countryFlagEmoji(profile?.countryCode);
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (flag != null) ...[
                                        Text(flag, style: const TextStyle(fontSize: 20)),
                                        const SizedBox(width: 6),
                                      ],
                                      Flexible(
                                        child: Text(
                                          seat.username ?? 'Unknown',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            shadows: [
                                              Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 2)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 8),

                              // BADGE ROWS — level/ID/VIP render instantly from
                              // live seat data; age/gender/agency/family fill in
                              // when the profile fetch resolves. Nothing is ever
                              // a placeholder: each chip is omitted until real.
                              FutureBuilder<Result<User>>(
                                future: profileFuture,
                                builder: (context, snapshot) {
                                  final profile =
                                      snapshot.data?.isSuccess == true ? snapshot.data!.data : null;
                                  final genderSymbol = profile?.gender == 'female'
                                      ? '♀'
                                      : profile?.gender == 'male'
                                          ? '♂'
                                          : null;

                                  return Wrap(
                                    alignment: WrapAlignment.end,
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      if (profile?.age != null || genderSymbol != null)
                                        _badgePill(
                                          [
                                            if (profile?.age != null) '${profile!.age}',
                                            if (genderSymbol != null) genderSymbol,
                                          ].join(' '),
                                          const Color(0xFF3B82F6),
                                          profile?.gender == 'female' ? Icons.female : Icons.male,
                                        ),
                                      _badgePill('${seat.level}', const Color(0xFF10B981), Icons.terrain),
                                      if (seat.vipLevel > 0) VipBadge(level: seat.vipLevel),
                                      _badgePill(
                                        '#${seat.displayId ?? seat.userId ?? ''}',
                                        const Color(0xFFF59E0B),
                                        Icons.badge_outlined,
                                      ),
                                      if (profile?.agencyRole != null)
                                        _badgePill(
                                          profile!.agencyRole == 'agent' ? 'وكيل' : 'مضيف',
                                          profile.agencyRole == 'agent'
                                              ? const Color(0xFFF59E0B)
                                              : const Color(0xFF14B8A6),
                                          Icons.workspace_premium,
                                        ),
                                      if (profile?.familyName != null && profile!.familyName!.isNotEmpty)
                                        _badgePill(
                                            profile.familyName!, const Color(0xFF8B5CF6), Icons.shield),
                                      MicPerfectBadge(userId: seat.userId),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),

                      // CROWN — ornament across the banner's top edge. Sits
                      // behind the avatar in the stack so the avatar stays
                      // fully visible over it.
                      Positioned(
                        top: -18,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Image.asset(
                            _profileCardCrown,
                            height: 54,
                            fit: BoxFit.fitWidth,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ),
                      ),

                      // AVATAR — overlaps the banner's top-right corner.
                      Positioned(
                        top: -14,
                        right: 10,
                        child: GestureDetector(
                          onTap: isMine
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  final roomState = ref.read(roomControllerProvider(widget.roomId));
                                  ref.read(pipProvider.notifier).activate(
                                        roomId: widget.roomId,
                                        roomName: ref.read(roomsProvider).findById(widget.roomId)?.name,
                                        roomImageUrl: roomState.roomImageUrl,
                                      );
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ProfileScreen(userId: seat.userId!),
                                    ),
                                  );
                                },
                          child: SizedBox(
                            width: 96,
                            height: 96,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (seat.avatarFrameUrl != null && seat.avatarFrameUrl!.isNotEmpty)
                                  FramedAvatar(
                                    size: 96,
                                    avatarSize: 58,
                                    frame: AvatarFrame.fromUrl(seat.avatarFrameUrl!),
                                    imageUrl: seat.avatarUrl,
                                    fallbackText: seat.username,
                                    glow: false,
                                  )
                                else
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2.5),
                                    ),
                                    child: CircleAvatar(
                                      radius: 34,
                                      backgroundImage:
                                          seat.avatarUrl != null ? NetworkImage(seat.avatarUrl!) : null,
                                      child: seat.avatarUrl == null
                                          ? const Icon(Icons.person, color: Colors.white, size: 30)
                                          : null,
                                    ),
                                  ),
                                Positioned(
                                  right: 6,
                                  bottom: 6,
                                  child: OnlineDot(userId: seat.userId, size: 16),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── MEDALS BAR (الميداليات) ──
                  // Hidden entirely when the user has unlocked nothing — an
                  // empty medal rail would just be decoration pretending to be
                  // data.
                  FutureBuilder<Result<User>>(
                    future: profileFuture,
                    builder: (context, snapshot) {
                      final profile = snapshot.data?.isSuccess == true ? snapshot.data!.data : null;
                      final medals = profile?.achievements ?? const <AchievementBadge>[];
                      if (medals.isEmpty) return const SizedBox.shrink();

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.28),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withOpacity(0.10)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.arrow_back_ios, size: 13, color: Colors.white38),
                            const SizedBox(width: 6),
                            Expanded(
                              child: SizedBox(
                                height: 38,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  reverse: true,
                                  itemCount: medals.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                                  itemBuilder: (_, i) {
                                    final m = medals[i];
                                    return Tooltip(
                                      message: m.name,
                                      child: Image.network(
                                        m.iconUrl,
                                        width: 34,
                                        height: 34,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => const Icon(
                                            Icons.emoji_events,
                                            color: Colors.white24,
                                            size: 26),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('الميداليات',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // ACTIONS — role-based
                  if (isMine) ...[
                    // Own seat: leave button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.logout, color: Colors.white),
                        label: const Text('مغادرة المقعد', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                        onPressed: () {
                          Navigator.pop(context);
                          _emitLeaveSeat(seatNumber);
                        },
                      ),
                    ),
                  ] else ...[
                    // Other user: 4 equal circular buttons — same handlers as
                    // before, just restyled (icon + label, matching reference).
                    Row(children: [
                      Expanded(
                        child: _circleActionBtn(Icons.alternate_email_rounded, '@', const Color(0xFF4ADE80), () {
                          Navigator.pop(context);
                          setState(() => _showChatPanel = true);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _topChatFocus.requestFocus();
                            final mention = '@${seat.username ?? 'user'} ';
                            _externalTextController.text = mention;
                            _externalTextController.selection = TextSelection.fromPosition(
                                TextPosition(offset: _externalTextController.text.length));
                          });
                        }),
                      ),
                      Expanded(
                        child: _circleActionBtn(Icons.favorite, 'متابعة', const Color(0xFF22D3EE), () {
                          Navigator.pop(context);
                          unawaited(_handleFollowFromRoom(seat.userId!));
                        }),
                      ),
                      Expanded(
                        child: _circleActionBtn(Icons.chat_bubble_rounded, 'الدردشة', const Color(0xFFF472B6), () {
                          Navigator.pop(context);
                          _openDirectChat(_Recipient(id: seat.userId!, name: seat.username ?? '', avatarUrl: seat.avatarUrl));
                        }),
                      ),
                      Expanded(
                        child: _circleActionBtn(Icons.card_giftcard, 'إرسال هدية', const Color(0xFFDB2777), () {
                          Navigator.pop(context);
                          _openGiftSheetToUser(context, _Recipient(
                              id: seat.userId!, name: seat.username ?? '', avatarUrl: seat.avatarUrl));
                        }),
                      ),
                    ]),
                    // Admin-only controls below
                    if (isAdmin) ...[
                      const SizedBox(height: 14),
                      Divider(color: Colors.white.withOpacity(0.12)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _adminChipBtn(seat.forceMuted ? Icons.mic : Icons.mic_off,
                              seat.forceMuted ? 'فك كتم المايك' : 'منع من المايك',
                              Colors.orange, () async {
                            Navigator.pop(context);
                            await _forceMute(seat.userId, !seat.forceMuted);
                          }),
                          _adminChipBtn(Icons.remove_circle_outline, 'إزالة من المايك', Colors.red, () {
                            Navigator.pop(context);
                            ref.read(roomControllerProvider(widget.roomId).notifier)
                                .removeSeat(seatNumber: seatNumber, targetUserId: seat.userId!);
                            SocketService().emit('remove_from_seat', {
                              'roomId': widget.roomId,
                              'seatNumber': seatNumber,
                              'targetUserId': seat.userId,
                            });
                            _showRoomSnack('تم إزالة المستخدم من الميكروفون');
                          }),
                          _adminChipBtn(Icons.block, 'منع من المقعد', Colors.deepOrange, () async {
                            Navigator.pop(context);
                            await _setSeatBlock(seat.userId, true);
                          }),
                          _adminChipBtn(Icons.exit_to_app, 'طرد من الغرفة', Colors.redAccent, () async {
                            Navigator.pop(context);
                            await _promptKickUser(seat.userId);
                          }),
                          Builder(builder: (ctx) {
                            final isSeatLocked = ref.read(roomControllerProvider(widget.roomId))
                                .lockedSeats.contains(seatNumber);
                            return _adminChipBtn(
                              isSeatLocked ? Icons.lock_open : Icons.lock_outline,
                              isSeatLocked ? 'فك قفل المقعد' : 'قفل المقعد',
                              isSeatLocked ? Colors.lightGreen : Colors.amber,
                              () {
                                Navigator.pop(context);
                                final newLocked = !isSeatLocked;
                                ref.read(roomControllerProvider(widget.roomId).notifier)
                                    .toggleSeatLock(seatNumber: seatNumber, locked: newLocked);
                                _showRoomSnack(newLocked ? 'تم قفل المقعد $seatNumber' : 'تم فك قفل المقعد $seatNumber');
                              },
                            );
                          }),
                          _adminChipBtn(Icons.shield_moon_outlined, 'تعيين مشرف', Colors.cyan, () async {
                            Navigator.pop(context);
                            await _appointSupervisor(seat.userId);
                          }),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _adminChipBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _showLeaveSeatSheet(BuildContext context, int seatNumber, SeatData seat) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.90,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF8B0050), Color(0xFF4A0080), Color(0xFF2E004F)],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            child: Stack(
              children: [
                // ── rose petal background decoration ──
                Positioned.fill(
                  child: CustomPaint(painter: _RosePetalPainter()),
                ),

                // ── couple photo at top ──
                Positioned(
                  top: 0, left: 0, right: 0,
                  height: 280,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // gradient background instead of image
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFFFF85A1), Color(0xFFFF4081), Color(0xFF8B0050)],
                          ),
                        ),
                      ),
                      // fade to bg at bottom
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        height: 100,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, const Color(0xFF4A0080).withOpacity(0.95)],
                            ),
                          ),
                        ),
                      ),
                      // title text
                      const Positioned(
                        top: 40,
                        left: 0, right: 0,
                        child: Text(
                          'إرتباط',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            fontFamily: 'Georgia',
                            shadows: [
                              Shadow(color: Color(0xFFFF4081), blurRadius: 20),
                              Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
                            ],
                          ),
                        ),
                      ),
                      // "قواعد" button
                      Positioned(
                        top: 40, right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF4081).withOpacity(0.85),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white30),
                          ),
                          child: const Text('قواعد', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── main scrollable content ──
                SafeArea(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        // handle
                        Container(width: 40, height: 4,
                            decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(2))),

                        // space for the top image
                        const SizedBox(height: 200),

                        // ── floral heart frame with two avatars ──
                        SizedBox(
                          height: 180,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // outer glow ring
                              Container(
                                width: 260, height: 160,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(80),
                                  gradient: RadialGradient(colors: [
                                    Colors.pinkAccent.withOpacity(0.3),
                                    Colors.transparent,
                                  ]),
                                  border: Border.all(color: Colors.pinkAccent.withOpacity(0.4), width: 2),
                                  boxShadow: [
                                    BoxShadow(color: Colors.pinkAccent.withOpacity(0.3), blurRadius: 20, spreadRadius: 4),
                                  ],
                                ),
                              ),
                              // avatars row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // left avatar (partner)
                                  _framedCpAvatar(seat.relationPartner?.avatarUrl, 50, isLeft: true),
                                  const SizedBox(width: 16),
                                  // heart icon center
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.favorite, color: Colors.red, size: 32),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.pinkAccent.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Text('❤️', style: TextStyle(fontSize: 14)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 16),
                                  // right avatar (seat user)
                                  _framedCpAvatar(seat.avatarUrl, 50, isLeft: false),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // ── couple names ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            '❤️ ${seat.username ?? ''} & ${seat.relationPartner?.name ?? '...'} ❤️',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(color: Colors.pinkAccent, blurRadius: 8)],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── skill points cards ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              Expanded(child: _cpSkillCard('تصنيف نقاط المهارة', '0', const Color(0xFFFF69B4))),
                              const SizedBox(width: 12),
                              Expanded(child: _cpSkillCard('مكافأة نقاط المهارة', '0', const Color(0xFFBA55D3))),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── weekly ranking section ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6A0080), Color(0xFF4A0060)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.pinkAccent.withOpacity(0.4)),
                              boxShadow: [BoxShadow(color: Colors.pinkAccent.withOpacity(0.2), blurRadius: 12)],
                            ),
                            child: Column(
                              children: [
                                // header
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  width: double.infinity,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFFFF4081), Color(0xFFAD1457)],
                                    ),
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                  ),
                                  child: const Text(
                                    'ترتيب هذا الأسبوع',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      // countdown
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.pinkAccent.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.pinkAccent.withOpacity(0.3)),
                                        ),
                                        child: const Text(
                                          '01Days 01:04:30',
                                          style: TextStyle(color: Colors.white70, fontSize: 13),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      // rank row
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [Colors.pinkAccent.withOpacity(0.2), Colors.purpleAccent.withOpacity(0.1)],
                                          ),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: Colors.pinkAccent.withOpacity(0.3)),
                                        ),
                                        child: Row(
                                          children: [
                                            // rank number
                                            Container(
                                              width: 32, height: 32,
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient: LinearGradient(colors: [Color(0xFFFF4081), Color(0xFFFF80AB)]),
                                              ),
                                              child: const Center(
                                                child: Text('1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            // two avatars overlapping
                                            SizedBox(
                                              width: 56, height: 36,
                                              child: Stack(
                                                children: [
                                                  CircleAvatar(
                                                    radius: 18,
                                                    backgroundImage: seat.avatarUrl != null ? NetworkImage(seat.avatarUrl!) : null,
                                                    backgroundColor: Colors.pinkAccent,
                                                  ),
                                                  Positioned(
                                                    right: 0,
                                                    child: CircleAvatar(
                                                      radius: 18,
                                                      backgroundImage: seat.relationPartner?.avatarUrl != null
                                                          ? NetworkImage(seat.relationPartner!.avatarUrl!)
                                                          : null,
                                                      backgroundColor: Colors.purpleAccent,
                                                      child: const Icon(Icons.favorite, size: 14, color: Colors.white),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    seat.username ?? '',
                                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  if (seat.relationPartner?.name != null)
                                                    Text(
                                                      seat.relationPartner!.name,
                                                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const Text(
                                              '67.00M',
                                              style: TextStyle(color: Color(0xFFFF80AB), fontSize: 15, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ── leave seat button ──
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              _emitLeaveSeat(seatNumber);
                            },
                            child: Container(
                              width: double.infinity,
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [Color(0xFFFF4081), Color(0xFFAD1457)]),
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [BoxShadow(color: Colors.pinkAccent.withOpacity(0.4), blurRadius: 12)],
                              ),
                              child: const Center(
                                child: Text('مغادرة المقعد', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),

                // ── close button ──
                Positioned(
                  top: 15, right: 15,
                  child: SafeArea(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Icon(Icons.close, color: Colors.white70, size: 18),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _emitLeaveSeat(int seatNumber) {
    ref.read(roomControllerProvider(widget.roomId).notifier).leaveSeat(seatNumber: seatNumber);
  }

  Widget _framedCpAvatar(String? url, double radius, {required bool isLeft}) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: [Color(0xFFFF4081), Color(0xFFFF80AB)]),
        boxShadow: [BoxShadow(color: Colors.pinkAccent.withOpacity(0.6), blurRadius: 14, spreadRadius: 2)],
      ),
      padding: const EdgeInsets.all(3),
      child: CircleAvatar(
        radius: radius,
        backgroundImage: url != null ? NetworkImage(url) : null,
        backgroundColor: Colors.grey[800],
        child: url == null ? const Icon(Icons.person, color: Colors.white) : null,
      ),
    );
  }

  Widget _adminSeatOption({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: color == Colors.white54 ? Colors.white54 : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cpSkillCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.8), color.withOpacity(0.4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.6), width: 1.5),
        boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Text(title, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _badgePill(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _statCard(String num, String label, Color c1, Color c2, Color accent, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(0.3)),
      ),
      child: Column(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withOpacity(0.2)),
          child: Icon(icon, color: accent, size: 18),
        ),
        const SizedBox(height: 6),
        Text(num, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: accent, height: 1)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.09),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  /// Circular icon button with a label underneath — the profile card's
  /// action row (@ / متابعة / الدردشة / إرسال هدية).
  Widget _circleActionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.18),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }


  Future<void> _applyRoomImage({required _RoomImageType type, required String url}) async {
    await _roomReady.future;

    final notifier = ref.read(roomControllerProvider(widget.roomId).notifier);

    if (type == _RoomImageType.roomImage) {
      notifier.setRoomImageUrlLocal(url);
      await _updateRoomImageInBackend(url, isCover: true);
    } else {
      notifier.setRoomBackgroundUrlLocal(url);
      // Persist + broadcast to everyone in the room (room_background_changed).
      try {
        await _api.updateRoomBackground({
          'roomId': widget.roomId,
          'room_id': widget.roomId,
          'backgroundImageUrl': url,
        });
      } catch (e) {
        _showRoomSnack('تعذر حفظ الخلفية: $e', error: true);
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(type == _RoomImageType.roomImage
              ? 'Room image updated'
              : 'Background updated'),
        ),
      );
    }
  }
  void _openAdminSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (context, scrollCtrl) {
            return Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0F0F12),
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: ListView(
                controller: scrollCtrl,
                padding: EdgeInsets.fromLTRB(
                  16, 12, 16,
                  18 + MediaQuery.of(context).viewInsets.bottom,
                ),
                children: [
                  Center(
                    child: Container(
                      width: 46, height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'إدارة الغرفة',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _AdminActionCard(
                          title: 'صورة الغرفة',
                          subtitle: 'رفع صورة من الهاتف',
                          icon: Icons.image,
                          onTap: () => _pickUploadAndSaveRoomImage(isBackground: false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _AdminActionCard(
                          title: 'خلفية الغرفة',
                          subtitle: 'رفع خلفية من الهاتف',
                          icon: Icons.wallpaper,
                          onTap: () => _pickUploadAndSaveRoomImage(isBackground: true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- HELPER METHODS (Add these to your _RoomScreenState class) ---

  Widget _cpAvatar(String? url, double radius) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.pinkAccent, width: 2),
        boxShadow: [BoxShadow(color: Colors.pinkAccent.withOpacity(0.5), blurRadius: 10)],
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundImage: url != null ? NetworkImage(url) : null,
        backgroundColor: Colors.grey[800],
        child: url == null ? const Icon(Icons.person, color: Colors.white) : null,
      ),
    );
  }

/*  Widget _cpMiniAvatar(String? url1, String? url2) {
    return SizedBox(
      width: 50, height: 35,
      child: Stack(
        children: [
          CircleAvatar(radius: 15, backgroundImage: url1 != null ? NetworkImage(url1) : null),
          Positioned(
            right: 0,
            child: CircleAvatar(radius: 15, backgroundImage: url2 != null ? NetworkImage(url2) : null),
          ),
        ],
      ),
    );
  }*/

  Widget _skillCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }




  /// Open the gift sheet for sending gifts
  void _openGiftSheet(BuildContext context) {
    final auth = ref.read(authStateProvider);
    final myId = auth.user?.id;

    if (myId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login first')),
      );
      return;
    }

    final me = auth.user!;
    final state = ref.read(roomControllerProvider(widget.roomId));

    // All room users (incl. self). Self listed first.
    final ids = <int>{};
    final recipients = <GiftRecipient>[];
    void add(int id, String name, String? avatarUrl) {
      if (ids.add(id)) recipients.add(GiftRecipient(id: id, name: name, avatarUrl: avatarUrl));
    }
    add(me.id, me.name ?? 'أنا', me.avatarUrl);
    for (final s in state.seats.values) {
      if (s.userId != null) add(s.userId!, s.username ?? 'User #${s.userId}', s.avatarUrl);
    }
    for (final u in state.onlineUsers.values) {
      add(u.id, u.name ?? 'User #${u.id}', u.avatarUrl);
    }

    GiftPickerSheet.show(
      context,
      repository: _giftRepository,
      recipients: recipients,
      roomId: widget.roomId,
      balance: auth.user?.coinsBalance ?? auth.user?.coins ?? 0,
      onBalanceChanged: (_) {},
    );
  }
}

class _Recipient {
  final int id;
  final String name;
  final String? avatarUrl;
  _Recipient({required this.id, required this.name, this.avatarUrl});
}

class _AdminActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _AdminActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.lightBlueAccent),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 26),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

Widget _levelChip(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.2),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.bold),
    ),
  );
}

Widget _statCard({
  required String title,
  required String subtitle,
  required Color color,
}) {
  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.2),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

Widget _circleAction(IconData icon, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white10,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: Icon(icon, color: Colors.white),
    ),
  );
}

Widget _menuItem(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
    ) {
  return GestureDetector(
    onTap: onTap,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 26),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 70,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _badge(IconData icon, Color color) {
  return Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.2),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: color, size: 16),
  );
}

Widget _gradientStat(String title, String subtitle, Color color) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [color.withOpacity(0.7), color],
      ),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.4),
          blurRadius: 10,
        )
      ],
    ),
    child: Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

// Legacy _GlobalGiftBroadcastOverlay removed — new system renders
// broadcast banners via BroadcastBannerLayer inside GiftAnimationOverlay.

class _RosePetalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final positions = [
      Offset(size.width * 0.1, size.height * 0.15),
      Offset(size.width * 0.85, size.height * 0.12),
      Offset(size.width * 0.05, size.height * 0.5),
      Offset(size.width * 0.9, size.height * 0.45),
      Offset(size.width * 0.2, size.height * 0.8),
      Offset(size.width * 0.75, size.height * 0.75),
    ];
    for (int i = 0; i < positions.length; i++) {
      paint.color = (i % 2 == 0 ? Colors.pinkAccent : Colors.purpleAccent).withOpacity(0.08);
      canvas.drawCircle(positions[i], 40 + (i * 8.0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 5-digit numeric PIN dialog used for locking/entering a locked room.
/// Owns its [TextEditingController] so it lives exactly as long as the dialog
/// route (disposing it manually after `showDialog` returns crashes mid-transition).
class _PinDialog extends StatefulWidget {
  const _PinDialog({
    required this.title,
    required this.hint,
    required this.confirmLabel,
    this.initial,
  });

  final String title;
  final String hint;
  final String confirmLabel;
  final String? initial;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial ?? '');
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text.trim();
    if (!RegExp(r'^\d{5}$').hasMatch(v)) {
      setState(() => _error = 'يجب أن يكون 5 أرقام');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.hint,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 5,
              textAlign: TextAlign.center,
              onSubmitted: (_) => _submit(),
              style: const TextStyle(
                  color: Colors.white, fontSize: 26, letterSpacing: 10),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                counterText: '',
                errorText: _error,
                hintText: '•••••',
                hintStyle:
                    const TextStyle(color: Colors.white24, letterSpacing: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child:
                const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: _submit,
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}