import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../repositories/cp_repository.dart';
import 'profile_screen.dart';

/// #20 — "في الصفحة الرئيسية يعمل مربع باسم CP … يظهر له كل الاشخاص اللي عامل
/// معاهم CP، ولما يضغط على شخص منهم يجيله: الغاء CP مع فلان؟ نعم / لا. لو ضغط
/// نعم يتم الالغاء ولا تظهر له مره اخري الا لو عمل CP تاني."
class CpListScreen extends StatefulWidget {
  const CpListScreen({super.key, this.userId, this.title});

  /// Someone else's list when set; my own when null.
  final int? userId;
  final String? title;

  @override
  State<CpListScreen> createState() => _CpListScreenState();
}

const _kGold = Color(0xFFF5C242);
const _kPink = Color(0xFFFF4081);
const _kBg = Color(0xFF0D0620);
const _kCard = Color(0xFF1A0E3E);

class _CpListScreenState extends State<CpListScreen> {
  final CpRepository _repo = CpRepository();
  late Future<List<CpPartner>> _future;

  bool get _isMine => widget.userId == null;

  @override
  void initState() {
    super.initState();
    _future = _repo.partners(userId: widget.userId);
  }

  void _reload() => setState(() => _future = _repo.partners(userId: widget.userId));

  String? _resolveAvatar(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = AppConfig.socketUrl.endsWith('/')
        ? AppConfig.socketUrl.substring(0, AppConfig.socketUrl.length - 1)
        : AppConfig.socketUrl;
    return raw.startsWith('/') ? '$base$raw' : '$base/$raw';
  }

  Future<void> _confirmCancel(CpPartner partner) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _kCard,
          title: const Text('إلغاء الـ CP', style: TextStyle(color: Colors.white)),
          content: Text(
            'إلغاء CP مع ${partner.name}؟',
            style: const TextStyle(color: Colors.white70, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('لا', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('نعم', style: TextStyle(color: _kPink, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _repo.removePartner(partner.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إلغاء الـ CP مع ${partner.name}')),
      );
      _reload();
    } on CpException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red[700]),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: _kCard,
          elevation: 0,
          centerTitle: true,
          title: Text(
            widget.title ?? 'الـ CP',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: FutureBuilder<List<CpPartner>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: _kPink));
            }
            if (snap.hasError) {
              return _message('تعذّر تحميل قائمة الـ CP', retry: true);
            }
            final partners = snap.data ?? const <CpPartner>[];
            if (partners.isEmpty) {
              return _message(
                _isMine
                    ? 'لا يوجد لديك CP بعد — أرسل هدية CP لشخص وانتظر قبوله'
                    : 'لا يوجد CP',
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                final f = _repo.partners(userId: widget.userId);
                setState(() => _future = f);
                await f;
              },
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 28),
                itemCount: partners.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _row(partners[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _row(CpPartner p) {
    final avatar = _resolveAvatar(p.avatarUrl);
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kPink.withOpacity(0.35)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ProfileScreen(userId: p.userId)),
        ),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFF2A1A5E),
              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
              child: avatar == null
                  ? Text(
                      p.name.isNotEmpty ? p.name.characters.first.toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white),
                    )
                  : null,
            ),
            const Positioned(
              bottom: -2,
              right: -2,
              child: Text('💞', style: TextStyle(fontSize: 15)),
            ),
          ],
        ),
        title: Text(
          p.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: Row(
          children: [
            if (p.displayId != null)
              Text('ID ${p.displayId}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
            if (p.giftIconUrl != null && p.giftIconUrl!.isNotEmpty) ...[
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  _resolveAvatar(p.giftIconUrl)!,
                  width: 16,
                  height: 16,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
        // Only my own list can be edited; a profile visitor just sees the pairs.
        trailing: _isMine
            ? IconButton(
                icon: const Icon(Icons.heart_broken, color: Colors.white38),
                tooltip: 'إلغاء الـ CP',
                onPressed: () => _confirmCancel(p),
              )
            : null,
      ),
    );
  }

  Widget _message(String text, {bool retry = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('💞', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, height: 1.6),
            ),
            if (retry) ...[
              const SizedBox(height: 14),
              TextButton(onPressed: _reload, child: const Text('إعادة المحاولة')),
            ],
          ],
        ),
      ),
    );
  }
}
