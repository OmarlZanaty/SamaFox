import 'package:flutter/material.dart';

import '../../services/follow_service.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/user_trail.dart';
import '../models/gift.dart';

/// هدايا الحظ — the card behind a tap on the ticker.
///
/// Client spec: *"لو ضغطت على الشريط ده يظهر صفحة صاحب الشريط كأنه في الغرفة
/// فيها متابعة… إرسال رسالة… مسار — ولو ضغطت على مسار أدخل الغرفة اللي هو
/// فيها"*. The three actions reuse what the rest of the app already does:
/// [FollowService], the `/chat` route, and [followUserTrail].
Future<void> showLuckyWinnerCard(BuildContext context, LuckyRollEvent e, {int? myUserId}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _LuckyWinnerCard(event: e, myUserId: myUserId),
  );
}

class _LuckyWinnerCard extends StatefulWidget {
  const _LuckyWinnerCard({required this.event, this.myUserId});
  final LuckyRollEvent event;
  final int? myUserId;

  @override
  State<_LuckyWinnerCard> createState() => _LuckyWinnerCardState();
}

class _LuckyWinnerCardState extends State<_LuckyWinnerCard> {
  String _followStatus = 'unknown';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadFollow();
  }

  Future<void> _loadFollow() async {
    try {
      final s = await FollowService.getFollowStatus(widget.event.senderId);
      if (mounted) setState(() => _followStatus = s);
    } catch (_) {
      if (mounted) setState(() => _followStatus = 'none');
    }
  }

  Future<void> _follow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_followStatus == 'none' || _followStatus == 'unknown') {
        await FollowService.sendFollowRequest(widget.event.senderId);
        if (mounted) setState(() => _followStatus = 'pending');
        _snack('تم إرسال طلب المتابعة');
      } else if (_followStatus == 'accepted' || _followStatus == 'following') {
        await FollowService.unfollow(widget.event.senderId);
        if (mounted) setState(() => _followStatus = 'none');
        _snack('تم إلغاء المتابعة');
      }
    } catch (_) {
      _snack('تعذّر تنفيذ الطلب');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _message() {
    final e = widget.event;
    Navigator.of(context).pop();
    Navigator.of(context).pushNamed('/chat', arguments: {
      'partnerId': e.senderId,
      'partnerName': e.senderName ?? '',
      'partnerAvatarUrl': e.senderAvatarUrl,
    });
  }

  Future<void> _trail() async {
    final e = widget.event;
    final nav = Navigator.of(context);
    nav.pop();
    // The room the win happened in is the best guess; the lookup inside
    // followUserTrail is the truth if they have moved since.
    await followUserTrail(nav.context, e.senderId);
  }

  String get _followLabel {
    switch (_followStatus) {
      case 'accepted':
      case 'following':
        return 'متابَع ✓';
      case 'pending':
        return 'بانتظار القبول';
      default:
        return 'متابعة';
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final isMe = e.senderId == widget.myUserId;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E1347), Color(0xFF2B1760)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFFB300).withOpacity(0.6)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: (e.senderAvatarUrl == null || e.senderAvatarUrl!.isEmpty)
                          ? Container(color: Colors.white24, child: const Icon(Icons.person, color: Colors.white70, size: 34))
                          : AppNetworkImage(e.senderAvatarUrl!, width: 64, height: 64, fit: BoxFit.cover, cacheWidth: 160),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.senderName ?? 'مستخدم',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'كسب ×${e.multiplier} — ${e.payoutCoins} كوينز'
                          '${e.giftName != null ? ' من ${e.giftName}' : ''}',
                          style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        if (e.recipientName != null)
                          Text(
                            'على ${e.recipientName}',
                            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFFFFB300), borderRadius: BorderRadius.circular(12)),
                    child: Text('×${e.multiplier}',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 20)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (!isMe)
                Row(
                  children: [
                    Expanded(child: _ActionBtn(icon: Icons.favorite, label: _followLabel, color: const Color(0xFF22D3EE), onTap: _busy ? null : _follow)),
                    const SizedBox(width: 10),
                    Expanded(child: _ActionBtn(icon: Icons.chat_bubble_rounded, label: 'إرسال رسالة', color: const Color(0xFFF472B6), onTap: _message)),
                    const SizedBox(width: 10),
                    Expanded(child: _ActionBtn(icon: Icons.route_rounded, label: 'مسار', color: const Color(0xFF00C853), onTap: _trail)),
                  ],
                )
              else
                Text('ده أنت 😄', style: TextStyle(color: Colors.white.withOpacity(0.7))),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.icon, required this.label, required this.color, this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.18),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
