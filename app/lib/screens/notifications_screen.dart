import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'dart:convert';
import '../services/agency_service.dart';
import '../services/follow_service.dart';
import '../services/notification_service.dart';
import '../services/relation_service.dart';
import '../services/socket_service.dart';
import '../l10n/tr.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> with SingleTickerProviderStateMixin {
  bool _loading = true;
  List<Map<String, dynamic>> _requests = const [];
  List<Map<String, dynamic>> _relationRequests = const [];
  List<Map<String, dynamic>> _notifications = const [];
  int _unreadCount = 0;
  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
    _notificationSub = SocketService().notificationStream.listen((_) {
      _load();
    });
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    _tabController.dispose();
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
    try {
      await FollowService.respondToFollow(followId, action);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(action == 'accept' ? tr('تم قبول الطلب', 'Request accepted') : tr('تم رفض الطلب', 'Request rejected'))),
        );
      }
    } catch (e) {
      final message = agencyErrorMessage(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      await _load();
    }
  }

  Future<void> _handleRelationResponse(int relationId, String action) async {
    try {
      await RelationService.respondToRelation(relationId, action);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(action == 'accept' ? tr('تم قبول الطلب', 'Request accepted') : tr('تم رفض الطلب', 'Request rejected'))),
        );
      }
    } catch (e) {
      final message = agencyErrorMessage(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      await _load();
    }
  }

  Future<void> _markAllRead() async {
    await NotificationService.markAllRead();
    await _load();
  }

  Future<void> _markRead(int id) async {
    await NotificationService.markRead(id);
    await _load();
  }

  Future<void> _respondAgencyInvite(Map<String, dynamic> item, bool accept) async {
    try {
      var data = item['data'];
      if (data is String && data.isNotEmpty) data = jsonDecode(data);
      final inviteId = (data is Map ? (data['inviteId'] as num?) : null)?.toInt();
      if (inviteId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('تعذر تحديد الدعوة', 'Unable to identify invitation'))),
          );
        }
        return;
      }
      await AgencyService().respondInvite(inviteId, accept);
      final id = (item['id'] as num?)?.toInt() ?? 0;
      if (id != 0) await NotificationService.markRead(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(accept ? (_isBranchInvite(item) ? tr('✓ انضممت كفرع للوكالة', '✓ Joined the agency as a branch') : tr('✓ انضممت إلى الوكالة', '✓ Joined the agency')) : tr('تم رفض الدعوة', 'Invitation rejected'))),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        final msg = agencyErrorMessage(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
      await _load();
    }
  }

  IconData _iconForType(String type) {
    if (type.contains('follow')) return Icons.person_add_alt_1_rounded;
    if (type.contains('relation')) return Icons.favorite_rounded;
    if (type.contains('gift')) return Icons.card_giftcard_rounded;
    if (type.contains('message')) return Icons.message_rounded;
    return Icons.notifications_active_rounded;
  }

  String _titleForNotification(Map<String, dynamic> item) {
    if (_isBranchInvite(item)) return tr('دعوة لتكون فرعاً', 'Invitation to become a branch');
    if (item['type'] == 'AGENCY_INVITE') return tr('دعوة للانضمام إلى الوكالة', 'Invitation to join the agency');
    final type = (item['type'] as String? ?? '').toLowerCase();
    final title = (item['title'] as String? ?? '').trim();
    if (title.isNotEmpty && !_looksEnglish(title)) return title;

    if (type.contains('follow')) return tr('طلب متابعة', 'Follow request');
    if (type.contains('relation')) return tr('طلب علاقة', 'Relationship request');
    if (type.contains('gift')) return tr('هدية', 'Gift');
    if (type.contains('message')) return tr('رسالة جديدة', 'New message');
    return title.isNotEmpty ? title : tr('إشعار', 'Notification');
  }

  String _bodyForNotification(Map<String, dynamic> item) {
    if (_isBranchInvite(item)) return tr('دعوة لتكون فرعاً', 'Invitation to become a branch');
    if (item['type'] == 'AGENCY_INVITE') return tr('دعوة للانضمام إلى الوكالة', 'Invitation to join the agency');
    final type = (item['type'] as String? ?? '').toLowerCase();
    final body = (item['body'] as String? ?? '').trim();
    if (body.isNotEmpty && !_looksEnglish(body)) return body;

    if (type.contains('follow')) return tr('لديك طلب متابعة جديد.', 'You have a new follow request.');
    if (type.contains('relation')) return tr('لديك طلب علاقة جديد.', 'You have a new relationship request.');
    if (type.contains('gift')) return tr('تم استلام إشعار هدية جديد.', 'A new gift notification was received.');
    if (type.contains('message')) return tr('لديك رسالة جديدة.', 'You have a new message.');
    return body.isNotEmpty ? body : tr('لا توجد تفاصيل إضافية.', 'No additional details.');
  }

  bool _looksEnglish(String value) {
    final latin = RegExp(r'[A-Za-z]');
    final arabic = RegExp(r'[\u0600-\u06FF]');
    return latin.hasMatch(value) && !arabic.hasMatch(value);
  }

  bool _isBranchInvite(Map<String, dynamic> item) {
    if (item['type'] != 'AGENCY_INVITE') return false;
    dynamic data = item['data'];
    if (data is String) {
      try { data = jsonDecode(data); } catch (_) { return false; }
    }
    return (data is Map ? data['role'] : item['role']) == 'BRANCH';
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
      _tabController.animateTo(1);
      return;
    }

    if (type.contains('relation')) {
      _tabController.animateTo(2);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(tr('الإشعارات ${_unreadCount > 0 ? "($_unreadCount)" : ""}', 'Notifications ${_unreadCount > 0 ? "($_unreadCount)" : ""}')),
          actions: [
            TextButton(
              onPressed: _loading || _unreadCount == 0 ? null : _markAllRead,
              child: Text(tr('تحديد الكل كمقروء', 'Mark all as read')),
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: tr('الإشعارات', 'Notifications')),
              Tab(text: tr('طلبات المتابعة', 'Follow requests')),
              Tab(text: tr('طلبات العلاقة', 'Relationship requests')),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _notifications.isEmpty
                      ? Center(child: Text(tr('لا توجد إشعارات حالياً', 'No notifications yet')))
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _notifications.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = _notifications[index];
                            final id = (item['id'] as num?)?.toInt() ?? 0;
                            final isRead = item['isRead'] == true;
                            final type = (item['type'] as String?) ?? 'system';
                            final isAgencyInvite = type == 'AGENCY_INVITE' && !isRead;
                            return Card(
                              color: isRead ? null : Colors.deepPurple.withOpacity(0.2),
                              child: ListTile(
                                onTap: () => _openNotification(item),
                                leading: Icon(_iconForType(type)),
                                title: Text(_titleForNotification(item)),
                                subtitle: isAgencyInvite
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(_bodyForNotification(item)),
                                          Row(
                                            children: [
                                              TextButton(
                                                onPressed: () => _respondAgencyInvite(item, true),
                                                child: Text(tr('قبول', 'Accept')),
                                              ),
                                              TextButton(
                                                onPressed: () => _respondAgencyInvite(item, false),
                                                child: Text(tr('رفض', 'Reject')),
                                              ),
                                            ],
                                          ),
                                        ],
                                      )
                                    : Text(_bodyForNotification(item)),
                                trailing: (isRead || isAgencyInvite
                                    ? null
                                    : TextButton(
                                        onPressed: id == 0 ? null : () => _markRead(id),
                                        child: Text(tr('مقروء', 'Read')),
                                      )),
                              ),
                            );
                          },
                        ),
                  _requests.isEmpty
                      ? Center(child: Text(tr('لا توجد طلبات متابعة حالياً', 'No follow requests yet')))
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
                                title: Text(tr('${follower['name'] ?? 'مستخدم'} (@${follower['displayId'] ?? '-'}) يريد متابعتك', '${follower['name'] ?? 'User'} (@${follower['displayId'] ?? '-'}) wants to follow you')),
                                subtitle: Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => _respond(followId, 'accept'),
                                      child: Text(tr('قبول', 'Accept')),
                                    ),
                                    TextButton(
                                      onPressed: () => _respond(followId, 'reject'),
                                      child: Text(tr('رفض', 'Reject')),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  _relationRequests.isEmpty
                      ? Center(child: Text(tr('لا توجد طلبات علاقة حالياً', 'No relationship requests yet')))
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
                                title: Text(tr('${from['name'] ?? 'مستخدم'} (@${from['displayId'] ?? '-'}) يريد علاقة معك', '${from['name'] ?? 'User'} (@${from['displayId'] ?? '-'}) wants a relationship with you')),
                                subtitle: Row(
                                  children: [
                                    TextButton(
                                      onPressed: () => _handleRelationResponse(relationId, 'accept'),
                                      child: Text(tr('قبول', 'Accept')),
                                    ),
                                    TextButton(
                                      onPressed: () => _handleRelationResponse(relationId, 'reject'),
                                      child: Text(tr('رفض', 'Reject')),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
      );
  }
}
