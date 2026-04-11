import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/follow_service.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _requests = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await FollowService.getPendingRequests();
      if (mounted) {
        setState(() {
          _requests = data;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
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
    );
  }
}
