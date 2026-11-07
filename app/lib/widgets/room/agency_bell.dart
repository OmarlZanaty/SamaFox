import '../../l10n/tr.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/notification_service.dart';
import '../../services/agency_service.dart';
import '../../services/dio_client.dart';
import '../../services/socket_service.dart';

/// Shared invitation actions for the room bell and notifications screen.
class AgencyInvitationActions {
  static Map<String, dynamic> data(Map<String, dynamic> item) {
    dynamic value = item['data'];
    if (value is String) {
      try { value = jsonDecode(value); } catch (_) { return {}; }
    }
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  static int? inviteId(Map<String, dynamic> item) =>
      int.tryParse('${data(item)['inviteId']}');

  // Read state is not response state. Fetch the server's actionable invites.
  static Future<Set<int>> pendingIds() async {
    final response = await DioClient.dio.get('/agencies/my-invites');
    return (response.data['data'] as List).whereType<Map>()
        .map((invite) => (invite['id'] as num).toInt()).toSet();
  }

  static Future<String> respond(Map<String, dynamic> item, bool accept) async {
    final id = inviteId(item);
    if (id == null) {
      throw AgencyActionException(tr('تعذر تحديد الدعوة', 'Unable to identify invitation'));
    }
    await AgencyService().respondInvite(id, accept);
    // The response endpoint marks the invitation's notifications read.
    return accept
        ? (data(item)['role'] == 'BRANCH'
            ? tr('✓ انضممت كفرع للوكالة', '✓ Joined the agency as a branch')
            : tr('✓ انضممت إلى الوكالة', '✓ Joined the agency'))
        : tr('تم رفض الدعوة', 'Invitation rejected');
  }

  static void toast(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(builder: (context) => Positioned(
      left: 24, right: 24, bottom: MediaQuery.of(context).padding.bottom + 32,
      child: IgnorePointer(child: Material(
        color: const Color(0xFF323232),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Text(message, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white)),
        ),
      )),
    ));
    overlay.insert(entry);
    Timer(const Duration(seconds: 3), () { entry.remove(); entry.dispose(); });
  }
}

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
  Set<int> _pendingInvites = {};
  final Set<int> _responding = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pending = await AgencyInvitationActions.pendingIds();
      final r = await NotificationService.getNotifications(limit: 50, category: 'agency');
      final list = (r['data'] as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (!mounted) return;
      setState(() {
        _items = list;
        _pendingInvites = pending;
        _error = null;
        _loading = false;
      });
      // Opening the list reads them.
      unawaited(NotificationService.markAllRead(category: 'agency')
          .then((_) => AgencyInbox.instance.refreshCount()).catchError((_) {}));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = tr('تعذر تحميل الإشعارات', "Could not load notifications");
      });
    }
  }

  Future<void> _respondInvite(Map<String, dynamic> item, bool accept) async {
    final id = AgencyInvitationActions.inviteId(item);
    if (id == null || _responding.contains(id)) return;
    setState(() => _responding.add(id));
    try {
      final message = await AgencyInvitationActions.respond(item, accept);
      if (!mounted) return;
      setState(() => _pendingInvites.remove(id));
      AgencyInvitationActions.toast(context, message);
    } catch (e) {
      if (mounted) AgencyInvitationActions.toast(context, agencyErrorMessage(e));
    } finally {
      if (mounted) {
        await _load();
        if (mounted) setState(() => _responding.remove(id));
      }
      await AgencyInbox.instance.refreshCount();
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
          Padding(
            padding: EdgeInsets.all(12),
            child: Row(children: [
              Icon(Icons.notifications_rounded, color: Color(0xFFFFD54F)),
              SizedBox(width: 8),
              Text(tr('إشعارات الوكالة', "Agency notifications"), style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white54)))
                    : _items.isEmpty
                        ? Center(child: Text(tr('لا توجد إشعارات', "No notifications"), style: TextStyle(color: Colors.white54)))
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
    final data = AgencyInvitationActions.data(n);
    final inviteId = AgencyInvitationActions.inviteId(n);
    final canRespond = n['type'] == 'AGENCY_INVITE' && _pendingInvites.contains(inviteId);
    final at = DateTime.tryParse('${n['createdAt'] ?? ''}')?.toLocal();
    final date = at == null ? '' : '${at.year}/${_two(at.month)}/${_two(at.day)}';
    final time = at == null ? '' : '${_two(at.hour)}:${_two(at.minute)}';
    final unread = n['isRead'] != true;
    String? fmt(dynamic v) => v == null ? null : '$v';
    final rows = <(String, String?)>[
      (tr('الوكالة', "Agency"), fmt(data['agencyName'])),
      (tr('النسبة', "Rate"), data['ratePercent'] == null ? null : '${data['ratePercent']}%'),
      (tr('الفترة', "Period"), fmt(data['period'])),
      (tr('الإنتاج المرتبط', "Related production"), data['productionCoins'] == null ? null : tr('${data['productionCoins']} كوينز', "${data['productionCoins']} coins")),
      (tr('قيمة العمولة', "Commission amount"), data['commissionCoins'] == null ? null : tr('${data['commissionCoins']} كوينز', "${data['commissionCoins']} coins")),
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
          if (canRespond)
            Row(children: [
              TextButton(
                onPressed: _responding.contains(inviteId) ? null : () => _respondInvite(n, true),
                child: Text(tr('قبول', 'Accept')),
              ),
              TextButton(
                onPressed: _responding.contains(inviteId) ? null : () => _respondInvite(n, false),
                child: Text(tr('رفض', 'Reject')),
              ),
            ]),
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
