import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../providers/auth_provider.dart';
import '../providers/room_provider.dart';
import '../providers/localization_provider.dart';
import '../services/dio_client.dart';
import 'room_screen.dart';
import 'user_profile_screen.dart';
import 'create_room_dialog.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SearchResult> _results = [];
  bool _isSearching = false;

  Future<void> _showCreateRoomDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const CreateRoomDialog(),
    );

    // 🔥 AFTER DIALOG CLOSE → RELOAD ROOMS
    await ref.read(roomsProvider.notifier).loadRooms();
  }

  static const _bg0 = Color(0xFF0D0620);
  static const _bg1 = Color(0xFF1A0E3E);
  static const _bg2 = Color(0xFF2A1A5E);

  static const _brand = Color(0xFF6B4CE6);
  static const _brandGlow = Color(0xFFB55CFF);
  static const _gold = Color(0xFFFFD36E);
  static const _live = Color(0xFFFF2D55);

  late final AnimationController _pulseCtrl;

  void _onChanged() {
    _debounce?.cancel();
    final q = _controller.text.trim();

    if (q.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (!mounted) return;
    setState(() => _isSearching = true);

    try {
      final parsed = await _searchWithFallback(q);

      if (!mounted) return;
      setState(() {
        _results = parsed;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  Future<List<SearchResult>> _searchWithFallback(String q) async {
    final rows = <Map<String, dynamic>>[];

    try {
      final usersResp = await DioClient.dio.get(
        '/users/search',
        queryParameters: {'query': q},
      );
      final usersRaw = (usersResp.data is Map)
          ? ((usersResp.data['users'] as List?) ?? const [])
          : const [];
      rows.addAll(usersRaw.whereType<Map>().map((m) => {
            'type': 'user',
            'id': m['id'],
            'name': m['name'],
            'imageUrl': m['avatarUrl'],
            'subtitle': m['displayId'] != null ? '#${m['displayId']}' : null,
          }));
    } catch (_) {}

    final numericId = int.tryParse(q);
    if (numericId != null && numericId > 0) {
      try {
        final u = await DioClient.dio.get('/users/$numericId');
        final payload = u.data;
        final user = payload is Map ? (payload['user'] ?? payload) : null;
        if (user is Map) {
          rows.add({
            'type': 'user',
            'id': user['id'],
            'name': user['name'],
            'imageUrl': user['avatarUrl'],
            'subtitle': user['displayId'] != null ? '#${user['displayId']}' : null,
          });
        }
      } catch (_) {}
    }

    try {
      final roomsResp = await DioClient.dio.get('/rooms', queryParameters: {'limit': 100});
      final roomsRaw = (roomsResp.data is Map)
          ? ((roomsResp.data['rooms'] as List?) ?? const [])
          : const [];
      final queryLower = q.toLowerCase();
      rows.addAll(
        roomsRaw.whereType<Map>().where((r) {
          final name = (r['name'] ?? '').toString().toLowerCase();
          final id = (r['id'] ?? '').toString();
          return name.contains(queryLower) || id == q;
        }).map((r) => {
              'type': 'room',
              'id': r['id'],
              'name': r['name'],
              'imageUrl': r['coverImageUrl'],
              'subtitle': null,
            }),
      );
    } catch (_) {}

    try {
      final convResp = await DioClient.dio.get('/messages/conversations');
      final raw = (convResp.data is Map)
          ? ((convResp.data['data'] as List?) ??
              (convResp.data['conversations'] as List?) ??
              const [])
          : const [];
      final ql = q.toLowerCase();
      rows.addAll(
        raw.whereType<Map>().where((m) {
          final name = (m['partnerName'] ?? m['name'] ?? '').toString().toLowerCase();
          return name.contains(ql);
        }).map((m) => {
              'type': 'user',
              'id': m['partnerId'] ?? m['userId'] ?? m['id'],
              'name': m['partnerName'] ?? m['name'],
              'imageUrl': m['partnerAvatarUrl'] ?? m['avatarUrl'],
              'subtitle': null,
            }),
      );
    } catch (_) {}

    final dedup = <String, SearchResult>{};
    for (final row in rows) {
      final result = SearchResult.fromJson(row);
      if (result.id == 0 || result.name.isEmpty) continue;
      dedup['${result.type}:${result.id}'] = result;
    }
    return dedup.values.toList();
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final roomsState = ref.watch(roomsProvider);
    final strings = ref.watch(appStringsProvider);
    final isSearchMode = _controller.text.trim().isNotEmpty;

    final rooms = List.of(roomsState.rooms);
    rooms.shuffle(Random(7));

    final w = MediaQuery.of(context).size.width;
    final crossAxisCount = w >= 900 ? 4 : (w >= 520 ? 3 : 3);

    final userId = authState.user?.id;

    debugPrint("========== DEBUG ==========");
    debugPrint("USER ID: $userId");
    debugPrint("ROOMS COUNT: ${roomsState.rooms.length}");

    for (var r in roomsState.rooms) {
      debugPrint("ROOM: ${r.name} | OWNER: ${r.ownerId}");
    }
    debugPrint("===========================");

// ✅ REPLACE the userRoom block with this:
    dynamic userRoom;
    if (userId != null) {
      try {
        userRoom = roomsState.rooms.firstWhere(
              (room) => room.owner?.id == userId,
        );
      } catch (_) {
        userRoom = null;
      }
    }

    debugPrint("🔥 userRoom found: ${userRoom?.id} | userId: $userId | ownerId check: ${roomsState.rooms.map((r) => '${r.id}:${r.ownerId}').join(', ')}");
    debugPrint("🔥 RAW ownerId values: ${rooms.map((r) => r.ownerId).toList()}");

    return Scaffold(
      backgroundColor: _bg1,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bg2, _bg1, _bg0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              RefreshIndicator(
                onRefresh: () async {
                  await ref.read(roomsProvider.notifier).loadRooms();
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                        child: _TopHeader(
                          appName: strings.appName,
                          welcomeLine: '${strings.welcomeBack}, ${authState.user?.name ?? strings.guest}',
                          pulse: _pulseCtrl,
                          onTapNotifications: () => Navigator.pushNamed(context, '/notifications'),
                          onTapLeaderboard: () => Navigator.pushNamed(context, '/leaderboard'),
                        ),


                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: 'ابحث بالاسم أو الرقم...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _isSearching
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                : (_controller.text.isNotEmpty
                                    ? IconButton(
                                        onPressed: () => _controller.clear(),
                                        icon: const Icon(Icons.close),
                                      )
                                    : null),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.08),
                          ),
                        ),
                      ),
                    ),

                    // 🔥 ADD HERE
                    SliverToBoxAdapter(child: SizedBox(height: 10)),
                    SliverToBoxAdapter(child: _AdsSlider()),
                    SliverToBoxAdapter(child: SizedBox(height: 10)),
                    // ✅ removed the top bubbles row (plus icon + people icons)

                    if (isSearchMode)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
                        sliver: _results.isNotEmpty
                            ? SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => SearchResultTile(result: _results[index]),
                                  childCount: _results.length,
                                ),
                              )
                            : const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.only(top: 24),
                                  child: Center(
                                    child: Text(
                                      'لا توجد نتائج',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ),
                                ),
                              ),
                      )
                    else
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          children: [
                            Text(
                              strings.topRooms, // ✅ no hardcoded
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.white.withOpacity(0.10)),
                              ),
                              child: Text(
                                '${rooms.length}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (!isSearchMode && roomsState.isLoading && roomsState.rooms.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: CircularProgressIndicator(color: _brand),
                        ),
                      )
                    else if (!isSearchMode && roomsState.error != null && roomsState.rooms.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _ErrorPanel(
                          title: strings.error,
                          error: roomsState.error ?? strings.somethingWentWrong,
                          retry: strings.retry,
                          onRetry: () => ref.read(roomsProvider.notifier).loadRooms(),
                        ),
                      )
                    else if (!isSearchMode && rooms.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyPanel(
                            title: strings.noRoomsAvailable,
                            subtitle: strings.createFirstRoom,
                          ),
                        )
                      else if (!isSearchMode)

                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 130),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate([

                              // 🦊 SamaFox + top rooms block
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final totalWidth = constraints.maxWidth;
                                  final spacing = 6.0;
                                  final itemWidth = (totalWidth - spacing * 2) / 3;

                                  if (rooms.length == 1) {
                                    return SizedBox(
                                      height: itemWidth * 2 + spacing,
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: itemWidth * 2 + spacing,
                                            height: double.infinity,
                                            child: _SamaFoxRoom(
                                              onTap: () {
                                                Navigator.pushNamed(context, '/room', arguments: "samafox");
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          SizedBox(
                                            width: itemWidth,
                                            height: itemWidth,
                                            child: _RoomTile(
                                              stringsOnline: strings.online,
                                              room: rooms[0],
                                              isFeatured: false,
                                              onTap: () => Navigator.pushNamed(context, '/room', arguments: rooms[0].id),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }

                                  return SizedBox(
                                    height: itemWidth * 2 + spacing,
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: itemWidth * 2 + spacing,
                                          height: double.infinity,
                                          child: _SamaFoxRoom(
                                            onTap: () {
                                              Navigator.pushNamed(context, '/room', arguments: "samafox");
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        SizedBox(
                                          width: itemWidth,
                                          child: Column(
                                            children: [
                                              SizedBox(
                                                height: itemWidth,
                                                child: _RoomTile(
                                                  stringsOnline: strings.online,
                                                  room: rooms[0],
                                                  isFeatured: false,
                                                  onTap: () => Navigator.pushNamed(context, '/room', arguments: rooms[0].id),
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              SizedBox(
                                                height: itemWidth,
                                                child: _RoomTile(
                                                  stringsOnline: strings.online,
                                                  room: rooms[1],
                                                  isFeatured: false,
                                                  onTap: () => Navigator.pushNamed(context, '/room', arguments: rooms[1].id),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 6),

                              // 📦 REST GRID (normal 3 columns)
                              GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: rooms.length > 2 ? rooms.length - 2 : 0,
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 6,
                                  crossAxisSpacing: 6,
                                  childAspectRatio: 1,
                                ),
                                itemBuilder: (context, index) {
                                  final room = rooms[index + 2];

                                  return _RoomTile(
                                    stringsOnline: strings.online,
                                    room: room,
                                    isFeatured: false,
                                    onTap: () => Navigator.pushNamed(context, '/room', arguments: room.id),
                                  );
                                },
                              ),
                            ]),
                          ),
                        ),


                  ],
                ),
              ),

              Positioned(
                left: 14,
                right: 14,
                bottom: 14,
                child: _GlassBottomBar(
                  homeLabel: strings.home,
                  searchLabel: strings.messages, // ✅ label becomes Messages (or put "الرسائل")
                  storeLabel: "المتجر",
                  shippingAgentsLabel: "وكلاء الشحن",
                  gamesLabel: "الألعاب",
                  profileLabel: strings.profile,

                  hasRoom: userRoom != null, // ✅ NEW
                  roomImageUrl: userRoom?.coverImageUrl,
                  onHome: () {},
                  onSearch: () => Navigator.pushNamed(context, '/messages'), // ✅ go MessagesScreen
                  onStore: () => Navigator.pushNamed(context, '/store'),
                  onShippingAgents: () => Navigator.pushNamed(context, '/charging-agent'),
                  onGames: () => Navigator.pushNamed(context, '/games'),
                  onProfile: () => Navigator.pushNamed(context, '/profile'),
                  onCenter: () {
                    if (userRoom != null) {
                      // ✅ open his room
                      Navigator.pushNamed(
                        context,
                        '/room',
                        arguments: userRoom.id,
                      );
                    } else {
                      // ➕ create new room
                      _showCreateRoomDialog();
                    }
                  },
                ),


              ),
            ],
          ),
        ),
      ),
    );
  }
}


class SearchResult {
  final String type;
  final String name;
  final int id;
  final String? imageUrl;
  final String? subtitle;
  final int? level;

  SearchResult({
    required this.type,
    required this.name,
    required this.id,
    this.imageUrl,
    this.subtitle,
    this.level,
  });

  factory SearchResult.fromJson(Map<String, dynamic> j) {
    return SearchResult(
      type: (j['type'] ?? '').toString(),
      id: (j['id'] as num?)?.toInt() ?? 0,
      name: (j['name'] ?? '').toString(),
      imageUrl: j['imageUrl']?.toString(),
      subtitle: j['subtitle']?.toString(),
      level: (j['level'] as num?)?.toInt(),
    );
  }
}

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({super.key, required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white.withOpacity(0.08),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: () {
          if (result.type == 'room') {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => RoomScreen(roomId: result.id)),
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => UserProfileScreen(userId: result.id)),
            );
          }
        },
        leading: CircleAvatar(
          backgroundColor: Colors.white24,
          backgroundImage: (result.imageUrl != null && result.imageUrl!.isNotEmpty)
              ? NetworkImage(result.imageUrl!)
              : null,
          child: (result.imageUrl == null || result.imageUrl!.isEmpty)
              ? Icon(
                  result.type == 'room' ? Icons.meeting_room : Icons.person,
                  color: Colors.white,
                )
              : null,
        ),
        title: Text(
          result.name,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        subtitle: result.subtitle == null
            ? null
            : Text(
                result.subtitle!,
                style: const TextStyle(color: Colors.white70),
              ),
      ),
    );
  }
}


// ===================== TOP HEADER =====================
class _AdsSlider extends StatefulWidget {
  const _AdsSlider();

  @override
  State<_AdsSlider> createState() => _AdsSliderState();
}

class _ProAdCard extends StatelessWidget {
  const _ProAdCard({
    required this.image,
    required this.index,
  });

  final String image;
  final int index;

  @override
  Widget build(BuildContext context) {


    return GestureDetector(
      onTap: () {
        debugPrint("Ad clicked: $index");
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6B4CE6).withOpacity(0.35),
              blurRadius: 25,
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  image,
                  fit: BoxFit.cover,
                ),
              ),
              Container(
                color: Colors.black.withOpacity(0.35),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset("assets/images/Ads.png", width: 30),
                        const SizedBox(width: 8),
                        const Text(
                          "SamaFox",
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Text(
                      "🔥 Fantasy Event",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}

class _AdsSliderState extends State<_AdsSlider> {
  late final PageController _controller;
  int _current = 0;

  final List<String> images = [
    "assets/images/Ads.png",
    "assets/images/Ads.png",
    "assets/images/Ads.png",
  ];

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.88);

    _autoSlide();
  }

  void _autoSlide() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 4));

      if (!mounted) return;

      _current++;
      if (_current >= images.length) _current = 0;

      _controller.animateToPage(
        _current,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 170,
          child: PageView.builder(
            controller: _controller,
            itemCount: images.length,
            onPageChanged: (index) {
              setState(() => _current = index);
            },
            itemBuilder: (context, index) {
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  double value = 1.0;

                  if (_controller.position.haveDimensions) {
                    value = _controller.page! - index;
                    value = (1 - (value.abs() * 0.25)).clamp(0.85, 1.0);
                  }

                  return Transform.scale(
                    scale: value,
                    child: child,
                  );
                },
                child: _ProAdCard(
                  image: images[index],
                  index: index,
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 10),

        // 🔘 DOTS INDICATOR
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(images.length, (index) {
            final isActive = index == _current;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: isActive ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFFB55CFF)
                    : Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
            );
          }),
        )
      ],
    );
  }
}

class _TopHeader extends StatelessWidget {
  const _TopHeader({
    required this.appName,
    required this.welcomeLine,
    required this.pulse,
    required this.onTapNotifications,
    required this.onTapLeaderboard,
  });

  final String appName;
  final String welcomeLine;
  final AnimationController pulse;
  final VoidCallback onTapNotifications;
  final VoidCallback onTapLeaderboard;

  static const _gold = Color(0xFFFFD36E);


  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      clipBehavior: Clip.hardEdge, // ✅ extra safety
      runSpacing: 10,
      children: [
        // LEFT: App name + welcome
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width - 16 - 16 - (44 + 10 + 44), // keep space for 2 pills
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: pulse,
                builder: (context, _) {
                  final t = pulse.value;
                  final scale = 0.98 + (t * 0.02);

                  return Transform.scale(
                    scale: scale,
                    alignment: Alignment.centerLeft,
                    child: FittedBox( // ✅ KEY: text will never overflow
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: ShaderMask(
                        shaderCallback: (rect) => const LinearGradient(
                          colors: [Color(0xFFFFD36E), Color(0xFFB55CFF), Color(0xFF6B4CE6)],
                        ).createShader(rect),
                        child: Text(
                          appName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 4),
              Text(
                welcomeLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12),
              ),
            ],
          ),
        ),

        // RIGHT: buttons
        // RIGHT: buttons (✅ can wrap, no overflow)
        Wrap(
          spacing: 10,
          children: [
            _IconPill(
              icon: Icons.emoji_events,
              color: _gold,
              onTap: onTapLeaderboard,
            ),
            _IconPill(
              icon: Icons.notifications_none_rounded,
              color: Colors.white,
              onTap: onTapNotifications,
            ),
          ],
        ),

      ],
    );
  }

}

class _IconPill extends StatelessWidget {
  const _IconPill({required this.icon, required this.color, required this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

// ===================== ROOM TILE =====================

class _RoomTile extends StatelessWidget {
  const _RoomTile({
    required this.stringsOnline,
    required this.room,
    required this.onTap,
    required this.isFeatured,
  });

  final String stringsOnline; // used instead of hardcoded "LIVE"
  final dynamic room; // Room
  final VoidCallback onTap;
  final bool isFeatured;

  static const _brand = Color(0xFF6B4CE6);
  static const _live = Color(0xFFFF2D55);

  @override
  Widget build(BuildContext context) {
    final cover = room.coverImageUrl as String?;

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
          boxShadow: isFeatured
              ? [
            BoxShadow(
              color: _brand.withOpacity(0.22),
              blurRadius: 20,
              spreadRadius: 1,
            )
          ]
              : null,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _brand.withOpacity(0.55),
              const Color(0xFF24124D).withOpacity(0.90),
            ],
          ),
        ),
        child: Stack(
          children: [
            if (cover != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.network(
                  cover,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.05),
                      Colors.black.withOpacity(0.78),
                    ],
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ✅ overflow-safe badges row
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.middle, // Correct named argument
                                  child: Icon(Icons.people, color: Colors.white, size: 14),
                                ),
                                WidgetSpan(
                                  child: SizedBox(width: 6), // Correct named argument
                                ),
                                TextSpan(
                                  text: '${room.totalMembersCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
              Text(
                room.name ?? '',  // Default room name text
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,       // White text color
                  fontWeight: FontWeight.w700, // Bold text
                  fontSize: 14,              // Larger font size
                  letterSpacing: 1.2,        // Slight space between letters
                  shadows: [
                    Shadow(
                      blurRadius: 10.0,       // Soft shadow
                      color: Colors.black.withOpacity(0.8),  // Shadow color
                      offset: Offset(2.0, 2.0),             // Shadow offset
                    ),
                  ],
                ),
              ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SamaFoxRoom extends StatelessWidget {
  const _SamaFoxRoom({required this.onTap});

  final VoidCallback onTap;

  static const _brand = Color(0xFF6B4CE6);
  static const _gold = Color(0xFFFFD36E);

  @override
  Widget build(BuildContext context) {


    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        height: 260,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
          gradient: const LinearGradient(
            colors: [
              Color(0xFFB55CFF),
              Color(0xFF6B4CE6),
              Color(0xFF24124D),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: _brand.withOpacity(0.35),
              blurRadius: 25,
              spreadRadius: 2,
            )
          ],
        ),
        child: Stack(
          children: [

            // Background logo
            Positioned.fill(
              child: Opacity(
                opacity: 0.18,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    "assets/images/logo.png",
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Row(
                    children: const [
                      Icon(Icons.shield, color: Color(0xFFFFD36E), size: 22),
                      SizedBox(width: 6),
                      Text(
                        "ADMIN ROOM",
                        style: TextStyle(
                          color: Color(0xFFFFD36E),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      )
                    ],
                  ),

                  const Spacer(),

                  Row(
                    children: [
                      Image.asset(
                        "assets/images/logo.png",
                        width: 36,
                        height: 36,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "غرفة سما فوكس",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    "الغرفة الرسمية للإدارة",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        color: Colors.white.withOpacity(0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          const Text(
            "👋 مرحباً بك",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            name,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 16),

          const Text(
            "يمكنك الانضمام إلى غرفة سما فوكس الرسمية أو استكشاف الغرف الأخرى.",
            style: TextStyle(
              color: Colors.white60,
              fontSize: 12,
            ),
          ),

          const Spacer(),

          const Row(
            children: [
              Icon(Icons.star, color: Colors.amber, size: 16),
              SizedBox(width: 6),
              Text(
                "غرفة مميزة",
                style: TextStyle(color: Colors.white70, fontSize: 12),
              )
            ],
          )
        ],
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({
    required this.seed,
    this.size = 22, // ✅ add this
  });

  final int seed;
  final double size; // ✅ add this

  @override
  Widget build(BuildContext context) {
    final r = Random(seed);
    final a = 0.12 + r.nextDouble() * 0.10;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(a),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Icon(
        Icons.person,
        size: size * 0.65, // scale icon with avatar
        color: Colors.white.withOpacity(0.85),
      ),
    );
  }
}


// ===================== GLASS BOTTOM BAR (big center button + labels) =====================

class _GlassBottomBar extends StatelessWidget {
  const _GlassBottomBar({
    required this.homeLabel,
    required this.searchLabel,
    required this.storeLabel,
    required this.shippingAgentsLabel,
    required this.gamesLabel,
    required this.profileLabel,
    required this.onHome,
    required this.onSearch,
    required this.onStore,
    required this.onShippingAgents,
    required this.onGames,
    required this.onProfile,
    required this.onCenter,
    required this.hasRoom,
    this.roomImageUrl,

  });

  final String homeLabel;
  final String searchLabel;
  final String storeLabel;
  final String shippingAgentsLabel;
  final String gamesLabel;
  final String profileLabel;
  final bool hasRoom;
  final VoidCallback onHome;
  final VoidCallback onSearch;
  final VoidCallback onStore;
  final VoidCallback onShippingAgents;
  final VoidCallback onGames;
  final VoidCallback onProfile;
  final VoidCallback onCenter;
  final String? roomImageUrl;

  static const _brand = Color(0xFF6B4CE6);

  void _showTestMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "عفوا هذه النسخة مخصصة لأختبار الغرف فقط",
          textAlign: TextAlign.center,
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 78,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _BarItem(
                      icon: Icons.home_rounded,
                      label: homeLabel,
                      onTap: onHome, // ✅
                      compact: true,
                    ),
                  ),

                  Expanded(
                    child: _BarItem(
                      icon: Icons.message_rounded, // ✅ was search
                      label: searchLabel, // label now messages
                      onTap: onSearch, // ✅ go messages
                      compact: true,
                    ),
                  ),

                  Expanded(
                    child: _BarItem(
                      icon: Icons.storefront_rounded,
                      label: storeLabel,
                      onTap: onStore, // ✅
                      compact: true,
                    ),
                  ),

                  const SizedBox(width: 74),

                  Expanded(
                    child: _BarItem(
                      icon: Icons.local_shipping_rounded,
                      label: shippingAgentsLabel,
                      onTap: onShippingAgents, // ✅ ChargingAgentScreen
                      compact: true,
                    ),
                  ),

                  Expanded(
                    child: _BarItem(
                      icon: Icons.videogame_asset_rounded,
                      label: gamesLabel,
                      onTap: onGames, // ✅
                      compact: true,
                    ),
                  ),

                  Expanded(
                    child: _BarItem(
                      icon: Icons.person_rounded,
                      label: profileLabel,
                      onTap: onProfile, // ✅
                      compact: true,
                    ),
                  ),
                ],
              ),



              Positioned(
                child: GestureDetector(
                  onTap: onCenter,
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [_brand, Color(0xFFB55CFF)]),
                      boxShadow: [
                        BoxShadow(color: _brand.withOpacity(0.35), blurRadius: 22, spreadRadius: 2),
                      ],
                    ),
                    child: hasRoom && roomImageUrl != null
                        ? ClipOval(
                      child: Image.network(
                        roomImageUrl!,
                        fit: BoxFit.cover,
                        width: 62,
                        height: 62,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.meeting_room,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    )
                        : Icon(
                      hasRoom ? Icons.meeting_room : Icons.add,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: SizedBox(
        height: 62,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: Colors.white.withOpacity(0.85),
              size: compact ? 20 : 22,
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: compact ? 9 : 10,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ===================== ERROR / EMPTY =====================

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.title,
    required this.error,
    required this.retry,
    required this.onRetry,
  });

  final String title;
  final String error;
  final String retry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 56),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6B4CE6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.voice_chat, color: Colors.white.withOpacity(0.30), size: 76),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(color: Colors.white.withOpacity(0.90), fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.60), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
