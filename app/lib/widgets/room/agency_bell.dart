import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/notification_service.dart';
import '../../services/socket_service.dart';

/// SPEC52 #31 — agency notices (commission %, targets, invites…) no longer
/// slide a bar across the room. They collect behind this 🔔 above the room's
/// messages, with an unread badge; tapping opens a list like the messages.
///
/// The server only ever returns the caller's OWN notifications, and the
/// commission amount is only written into the notice of the agency owner it
/// was paid to — so no one sees financial figures that are not theirs.
class AgencyInbox {
  AgencyInbox._();
  static final AgencyInbox instance = AgencyInbox._();

  final ValueNotifier<int> unread = ValueNotifier<int>(0);
  bool _wired = false;

  static bool isAgencyType(String type) {
    final t = type.toLowerCase();
    return t.contains('commission') || t.contains('agency') || t.contains('target');
  }

  void ensureWired() {
    if (_wired) return;
    _wired = true;
    SocketService().notificationStream.listen((data) {
      final type = data['type']?.toString() ?? '';
      if (isAgencyType(type)) unread.value = unread.value + 1;
    });
    unawaited(refreshCount());
  }

  Future<void> refreshCount() async {
    try {
      final r = await NotificationService.getNotifications(limit: 1, category: 'agency');
      unread.value = (r['unreadCount'] as num?)?.toInt() ?? 0;
    } catch (_) {}
  }
}

class AgencyBell extends StatefulWidget {
  const AgencyBell({super.key});

  @override
  State<AgencyBell> createState() => _AgencyBellState();
}

class _AgencyBellState extends State<AgencyBell> {
  @override
  void initState() {
    super.initState();
    AgencyInbox.instance.ensureWired();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AgencyInbox.instance.unread,
      builder: (_, n, __) => GestureDetector(
        onTap: () => AgencyNoticesSheet.show(context),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.35),
                border: Border.all(color: Colors.white.withOpacity(0.14)),
              ),
              child: const Icon(Icons.notifications_rounded, color: Color(0xFFFFD54F), size: 16),
            ),
            if (n > 0)
              Positioned(
                top: -5,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(8)),
                  child: Text(n > 99 ? '99+' : '$n',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AgencyNoticesSheet extends StatefulWidget {
  const AgencyNoticesSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const Directionality(textDirection: TextDirection.rtl, child: AgencyNoticesSheet()),
      );

  @override
  State<AgencyNoticesSheet> createState() => _AgencyNoticesSheetState();
}

class _AgencyNoticesSheetState extends State<AgencyNoticesSheet> {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await NotificationService.getNotifications(limit: 50, category: 'agency');
      final list = (r['data'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
      // Opening the list reads them.
      unawaited(NotificationService.markAllRead(category: 'agency').then((_) => AgencyInbox.instance.unread.value = 0));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل الإشعارات';
      });
    }
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Container(
      height: h * 0.62,
      decoration: const BoxDecoration(
        color: Color(0xFF160C33),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Row(children: [
              Icon(Icons.notifications_rounded, color: Color(0xFFFFD54F)),
              SizedBox(width: 8),
              Text('إشعارات الوكالة', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white54)))
                    : _items.isEmpty
                        ? const Center(child: Text('لا توجد إشعارات', style: TextStyle(color: Colors.white54)))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _tile(_items[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _tile(Map<String, dynamic> n) {
    final data = (n['data'] is Map) ? Map<String, dynamic>.from(n['data'] as Map) : <String, dynamic>{};
    final at = DateTime.tryParse('${n['createdAt'] ?? ''}')?.toLocal();
    final date = at == null ? '' : '${at.year}/${_two(at.month)}/${_two(at.day)}';
    final time = at == null ? '' : '${_two(at.hour)}:${_two(at.minute)}';
    final unread = n['isRead'] != true;
    String? fmt(dynamic v) => v == null ? null : '$v';
    final rows = <(String, String?)>[
      ('الوكالة', fmt(data['agencyName'])),
      ('النسبة', data['ratePercent'] == null ? null : '${data['ratePercent']}%'),
      ('الفترة', fmt(data['period'])),
      ('الإنتاج المرتبط', data['productionCoins'] == null ? null : '${data['productionCoins']} كوينز'),
      ('قيمة العمولة', data['commissionCoins'] == null ? null : '${data['commissionCoins']} كوينز'),
    ].where((r) => r.$2 != null && r.$2!.isNotEmpty && r.$2 != 'null').toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(unread ? 0.10 : 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: unread ? const Color(0xFFFFD54F).withOpacity(0.4) : Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('${n['title'] ?? ''}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            Text('$date  $time', style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ]),
          if ('${n['body'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('${n['body']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in rows)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                    child: Text('${r.$1}: ${r.$2}', style: const TextStyle(color: Color(0xFFFFE082), fontSize: 11)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
