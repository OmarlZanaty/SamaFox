import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/dio_client.dart';
import 'profile_screen.dart';

/// C16 — أصدقاء / أتابعه / يتابعني / الزوار.
///
/// The client's complaint was that these lists "غير متفاعلة": the follow rows
/// existed in the database but nothing ever derived the four buckets, and the
/// profile just repeated the level and VIP counters underneath itself.
///
/// The three follow buckets arrive in ONE response. They are defined by each
/// other — a friend is someone who appears in both directions — so fetching
/// them separately lets the tabs briefly contradict themselves while the user
/// is looking at them.
///
/// الزوار is separate: it is gated on a level the admin sets from لوحة التحكم,
/// and the server answers `locked` with the required level rather than an empty
/// list, so the tab can explain itself instead of looking broken.
class RelationsScreen extends StatefulWidget {
  const RelationsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<RelationsScreen> createState() => _RelationsScreenState();
}

class _RelationsScreenState extends State<RelationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 4, vsync: this, initialIndex: widget.initialTab);

  late Future<_Relations> _future = _load();
  late Future<_Visitors> _visitorsFuture = _loadVisitors();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<_Relations> _load() async {
    final res = await DioClient.dio.get('/follow/relations');
    final data = (res.data is Map ? res.data['data'] : null) as Map? ?? const {};
    List<_Person> pick(String key) => ((data[key] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => _Person.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return _Relations(
      friends: pick('friends'),
      following: pick('following'),
      followers: pick('followers'),
    );
  }

  Future<_Visitors> _loadVisitors() async {
    final res = await DioClient.dio.get('/follow/visitors');
    final map = res.data is Map ? res.data as Map : const {};
    final rows = ((map['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return _Visitors(
      locked: map['locked'] == true,
      minLevel: (map['minLevel'] as num?)?.toInt() ?? 0,
      message: map['message']?.toString(),
      visits: rows
          .map((r) => _Visit(
                user: _Person.fromJson(Map<String, dynamic>.from(r['user'] as Map)),
                at: DateTime.tryParse(r['visitedAt']?.toString() ?? ''),
              ))
          .toList(),
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
      _visitorsFuture = _loadVisitors();
    });
  }

  Future<void> _act(Future<void> Function() action, String done) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      _reload();
    } catch (e) {
      if (!mounted) return;
      final msg = e is DioException && e.response?.data is Map
          ? (e.response!.data['message']?.toString() ?? 'تعذّر تنفيذ العملية')
          : 'تعذّر تنفيذ العملية';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _unfollow(int id) =>
      _act(() => DioClient.dio.delete('/follow/$id').then((_) {}), 'تم إلغاء المتابعة');

  Future<void> _followBack(int id) =>
      _act(() => DioClient.dio.post('/follow/$id').then((_) {}), 'تمت المتابعة');

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0620),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A0E3E),
          title: const Text('المتابعة والزوار'),
          bottom: TabBar(
            controller: _tabs,
            isScrollable: true,
            indicatorColor: const Color(0xFF4ECDC4),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            tabs: const [
              Tab(text: 'أصدقاء'),
              Tab(text: 'أتابعه'),
              Tab(text: 'يتابعني'),
              Tab(text: 'الزوار'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabs,
          children: [
            _followList(
              (r) => r.friends,
              badge: 'صديق',
              actionLabel: 'إلغاء المتابعة',
              onAction: _unfollow,
              empty: 'لا يوجد أصدقاء بعد — الصداقة متابعة متبادلة',
            ),
            _followList(
              (r) => r.following,
              badge: 'تتابعه',
              actionLabel: 'إلغاء المتابعة',
              onAction: _unfollow,
              empty: 'لا تتابع أحداً لم يتابعك بعد',
            ),
            _followList(
              (r) => r.followers,
              badge: 'يتابعك',
              actionLabel: 'رد المتابعة',
              onAction: _followBack,
              empty: 'لا أحد يتابعك دون رد بعد',
            ),
            _visitorsTab(),
          ],
        ),
      ),
    );
  }

  Widget _followList(
    List<_Person> Function(_Relations) select, {
    required String badge,
    required String actionLabel,
    required Future<void> Function(int) onAction,
    required String empty,
  }) {
    return FutureBuilder<_Relations>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return _message('تعذّر تحميل القائمة');
        final people = select(snap.data!);
        if (people.isEmpty) return _message(empty);

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: people.length,
            separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.06), height: 1),
            itemBuilder: (_, i) {
              final p = people[i];
              return ListTile(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ProfileScreen(userId: p.id)),
                ),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF2A1655),
                  backgroundImage: p.avatarUrl == null ? null : NetworkImage(p.avatarUrl!),
                  child: p.avatarUrl == null
                      ? const Icon(Icons.person, color: Colors.white54)
                      : null,
                ),
                title: Text(p.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  '$badge · ID ${p.displayId ?? p.id}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: TextButton(
                  onPressed: () => onAction(p.id),
                  child: Text(actionLabel, style: const TextStyle(color: Color(0xFF4ECDC4))),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _visitorsTab() {
    return FutureBuilder<_Visitors>(
      future: _visitorsFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return _message('تعذّر تحميل الزوار');
        final v = snap.data!;
        if (v.locked) {
          return _message(v.message ?? 'قائمة الزوار تظهر عند الوصول إلى المستوى ${v.minLevel}');
        }
        if (v.visits.isEmpty) return _message('لا يوجد زوار بعد');

        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: v.visits.length,
            separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.06), height: 1),
            itemBuilder: (_, i) {
              final visit = v.visits[i];
              final p = visit.user;
              return ListTile(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ProfileScreen(userId: p.id)),
                ),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF2A1655),
                  backgroundImage: p.avatarUrl == null ? null : NetworkImage(p.avatarUrl!),
                  child: p.avatarUrl == null
                      ? const Icon(Icons.person, color: Colors.white54)
                      : null,
                ),
                title: Text(p.name, style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                  _stamp(visit.at),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// "التاريخ والساعة و(ص/م)" — the client asked for the 12-hour form with the
  /// Arabic marker, not a locale default that could render AM/PM.
  String _stamp(DateTime? at) {
    if (at == null) return '';
    final d = at.toLocal();
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final marker = d.hour < 12 ? 'ص' : 'م';
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.year}/${d.month}/${d.day} — $hour12:$mm $marker';
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white38),
          ),
        ),
      );
}

class _Relations {
  const _Relations({
    required this.friends,
    required this.following,
    required this.followers,
  });

  final List<_Person> friends;
  final List<_Person> following;
  final List<_Person> followers;
}

class _Visitors {
  const _Visitors({
    required this.locked,
    required this.minLevel,
    required this.visits,
    this.message,
  });

  final bool locked;
  final int minLevel;
  final String? message;
  final List<_Visit> visits;
}

class _Visit {
  const _Visit({required this.user, this.at});

  final _Person user;
  final DateTime? at;
}

class _Person {
  const _Person({required this.id, required this.name, this.avatarUrl, this.displayId});

  final int id;
  final String name;
  final String? avatarUrl;
  final int? displayId;

  factory _Person.fromJson(Map<String, dynamic> j) => _Person(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: j['name']?.toString() ?? 'مستخدم',
        avatarUrl: (j['avatarUrl']?.toString().isNotEmpty ?? false)
            ? j['avatarUrl'].toString()
            : null,
        displayId: (j['displayId'] as num?)?.toInt(),
      );
}
