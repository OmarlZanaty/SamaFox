import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../services/follow_service.dart';
import '../services/notification_service.dart';
import '../services/relation_service.dart';
import '../services/socket_service.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _relationRequests = const [];
  List<Map<String, dynamic>> _notifications = const [];
  int _unreadCount = 0;
  StreamSubscription<Map<String, dynamic>>? _notificationSub;

  @override
  void initState() {
    super.initState();
    _load();
    _notificationSub = SocketService().notificationStream.listen((_) {
      _load();
    });
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await FollowService.getPendingRequests();
      final relationData = await RelationService.getPendingRelationRequests();
      final notificationsRes = await NotificationService.getNotifications();
      final notificationsRaw = ((notificationsRes['data'] as List?) ?? const []);
      if (mounted) {
        setState(() {
          _requests = data;
          _relationRequests = relationData;
          _notifications = notificationsRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          _unreadCount = (notificationsRes['unreadCount'] as num?)?.toInt() ?? 0;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(int followId, String action) async {
    await FollowService.respondToFollow(followId, action);
    await _load();
  }

  Future<void> _handleRelationResponse(int relationId, String action) async {
    await RelationService.respondToRelation(relationId, action);
    await _load();
  }

  Future<void> _markAllRead() async {
    await NotificationService.markAllRead();
    await _load();
  }

  Future<void> _markRead(int id) async {
    await NotificationService.markRead(id);
    await _load();
  }

  Future<void> _respondRelation(int relationId, String action) async {
    await RelationService.respondToRelation(relationId, action);
    await _load();
  }

  IconData _iconForType(String type) {
    if (type.contains('follow')) return Icons.person_add_alt_1_rounded;
    if (type.contains('relation')) return Icons.favorite_rounded;
    if (type.contains('gift')) return Icons.card_giftcard_rounded;
    if (type.contains('message')) return Icons.message_rounded;
    return Icons.notifications_active_rounded;
  }

  String _titleForNotification(Map<String, dynamic> item) {
    final type = (item['type'] as String? ?? '').toLowerCase();
    final title = (item['title'] as String? ?? '').trim();
    if (title.isNotEmpty && !_looksEnglish(title)) return title;

    if (type.contains('follow')) return 'طلب متابعة';
    if (type.contains('relation')) return 'طلب علاقة';
    if (type.contains('gift')) return 'هدية';
    if (type.contains('message')) return 'رسالة جديدة';
    return title.isNotEmpty ? title : 'إشعار';
  }

  String _bodyForNotification(Map<String, dynamic> item) {
    final type = (item['type'] as String? ?? '').toLowerCase();
    final body = (item['body'] as String? ?? '').trim();
    if (body.isNotEmpty && !_looksEnglish(body)) return body;

    if (type.contains('follow')) return 'لديك طلب متابعة جديد.';
    if (type.contains('relation')) return 'لديك طلب علاقة جديد.';
    if (type.contains('gift')) return 'تم استلام إشعار هدية جديد.';
    if (type.contains('message')) return 'لديك رسالة جديدة.';
    return body.isNotEmpty ? body : 'لا توجد تفاصيل إضافية.';
  }

  bool _looksEnglish(String value) {
    final latin = RegExp(r'[A-Za-z]');
    final arabic = RegExp(r'[\u0600-\u06FF]');
    return latin.hasMatch(value) && !arabic.hasMatch(value);
  }

  Future<void> _openNotification(Map<String, dynamic> item) async {
    final id = (item['id'] as num?)?.toInt() ?? 0;
    final type = (item['type'] as String?) ?? '';
    final data = (item['data'] is Map)
        ? Map<String, dynamic>.from(item['data'] as Map)
        : <String, dynamic>{};

    if (id > 0 && item['isRead'] != true) {
      await _markRead(id);
    }

    if (type.contains('message')) {
      final conversationId = (data['conversationId'] as num?)?.toInt();
      if (conversationId != null) {
        if (!mounted) return;
        Navigator.pushNamed(context, '/messages');
        return;
      }
    }

    if (type.contains('follow')) {
      if (!mounted) return;
      Navigator.pushNamed(context, '/notifications');
      return;
    }

    if (type.contains('relation')) {
      if (!mounted) return;
      Navigator.pushNamed(context, '/notifications');
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('الإشعارات ${_unreadCount > 0 ? "($_unreadCount)" : ""}'),
          actions: [
            TextButton(
              onPressed: _loading || _unreadCount == 0 ? null : _markAllRead,
              child: const Text('تحديد الكل كمقروء'),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'الإشعارات'),
              Tab(text: 'طلبات المتابعة'),
              Tab(text: 'طلبات العلاقة'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _notifications.isEmpty
                      ? const Center(child: Text('لا توجد إشعارات حالياً'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _notifications.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = _notifications[index];
                            final id = (item['id'] as num?)?.toInt() ?? 0;
                            final isRead = item['isRead'] == true;
                            final type = (item['type'] as String?) ?? 'system';
                            final data = Map<String, dynamic>.from((item['data'] as Map?) ?? const {});
                            final relationId = (data['relationId'] as num?)?.toInt() ?? 0;
                            final isRelationRequest = type == 'relation_request' && relationId > 0;
                            return Card(
                              color: isRead ? null : Colors.deepPurple.withOpacity(0.2),
                              child: ListTile(
                                onTap: () => _openNotification(item),
                                leading: Icon(_iconForType(type)),
                                title: Text(_titleForNotification(item)),
                                subtitle: Text(_bodyForNotification(item)),
                                trailing: isRelationRequest
                                    ? SizedBox(
                                        width: 170,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TextButton(
                                              onPressed: () => _respondRelation(relationId, 'accept'),
                                              child: const Text('قبول'),
                                            ),
                                            TextButton(
                                              onPressed: () => _respondRelation(relationId, 'reject'),
                                              child: const Text('رفض'),
                                            ),
                                          ],
                                        ),
                                      )
                                    : (isRead
                                        ? null
                                        : TextButton(
                                            onPressed: id == 0 ? null : () => _markRead(id),
                                            child: const Text('مقروء'),
                                          )),
                              ),
                            );
                          },
                        ),
                  _requests.isEmpty
                      ? const Center(child: Text('لا توجد طلبات متابعة حالياً'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _requests.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final req = _requests[index];
                            final follower = Map<String, dynamic>.from((req['follower'] as Map?) ?? {});
                            final followId = (req['id'] as num?)?.toInt() ?? 0;
                            return Card(
                              child: ListTile(
                                title: Text('${follower['name'] ?? 'مستخدم'} (@${follower['displayId'] ?? '-'}) يريد متابعتك'),
                                subtitle: Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => _respond(followId, 'accept'),
                                      child: const Text('قبول'),
                                    ),
                                    TextButton(
                                      onPressed: () => _respond(followId, 'reject'),
                                      child: const Text('رفض'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  _relationRequests.isEmpty
                      ? const Center(child: Text('لا توجد طلبات علاقة حالياً'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _relationRequests.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final req = _relationRequests[index];
                            final from = Map<String, dynamic>.from((req['user1'] as Map?) ?? {});
                            final relationId = (req['id'] as num?)?.toInt() ?? 0;
                            return Card(
                              child: ListTile(
                                title: Text('${from['name'] ?? 'مستخدم'} (@${from['displayId'] ?? '-'}) يريد علاقة معك'),
                                subtitle: Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => _handleRelationResponse(relationId, 'accept'),
                                      child: const Text('قبول'),
                                    ),
                                    TextButton(
                                      onPressed: () => _handleRelationResponse(relationId, 'reject'),
                                      child: const Text('رفض'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
      ),
    );
  }
}
