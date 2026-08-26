import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/dio_client.dart';
import '../services/level_catalog_service.dart';
import '../utils/storage_service.dart';

/// Buy a VIP tier with coins (شراء VIP).
///
/// Only tiers the dashboard put a price on are offered; everything else is
/// earned by recharging as before. A bought tier grants exactly the same
/// rewards as an earned one — the server shares that code path — so this sheet
/// only has to take the money and refresh.
class VipBuySheet extends StatefulWidget {
  const VipBuySheet({super.key, required this.currentVipLevel, this.coinsBalance});

  final int currentVipLevel;
  final int? coinsBalance;

  static Future<bool?> show(
    BuildContext context, {
    required int currentVipLevel,
    int? coinsBalance,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1E1347),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => VipBuySheet(
        currentVipLevel: currentVipLevel,
        coinsBalance: coinsBalance,
      ),
    );
  }

  @override
  State<VipBuySheet> createState() => _VipBuySheetState();
}

class _VipBuySheetState extends State<VipBuySheet> {
  List<Map<String, dynamic>> _tiers = [];
  bool _loading = true;
  int? _buyingLevel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await DioClient.dio.get('/vip/levels');
      final list = (res.data is Map) ? (res.data['data'] as List? ?? const []) : const [];
      final tiers = list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          // On sale, and above what the user already holds.
          .where((t) => (t['priceCoins'] is num) && (t['priceCoins'] as num) > 0)
          .where((t) => ((t['level'] as num?)?.toInt() ?? 0) > widget.currentVipLevel)
          .toList()
        ..sort((a, b) => ((a['level'] as num).toInt()).compareTo((b['level'] as num).toInt()));
      if (mounted) setState(() { _tiers = tiers; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _tiers = []; _loading = false; });
    }
  }

  Future<void> _buy(Map<String, dynamic> tier) async {
    final level = (tier['level'] as num).toInt();
    final price = (tier['priceCoins'] as num).toInt();
    final days = (tier['durationDays'] as num?)?.toInt();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1347),
        title: const Text('تأكيد الشراء', style: TextStyle(color: Colors.white)),
        content: Text(
          'شراء VIP $level مقابل ${_fmt(price)} كوينز'
          '${days != null ? '\nالمدة: $days يوم' : '\nبدون مدة (أبدي)'}',
          style: const TextStyle(color: Colors.white70, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('شراء', style: TextStyle(color: Color(0xFFFFD700))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _buyingLevel = level);
    try {
      final token = await StorageService.getAccessToken();
      final res = await DioClient.dio.post(
        '/vip/buy',
        data: {'level': level},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final ok = res.data is Map && res.data['success'] == true;
      if (!mounted) return;
      if (ok) {
        // The tier's badge may have changed — drop the cached catalog so the
        // new badge is picked up instead of the old chip.
        LevelCatalogService.invalidate();
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تهانينا! أصبحت VIP $level')),
        );
      } else {
        setState(() => _buyingLevel = null);
        _error(res.data is Map ? res.data['message']?.toString() : null);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _buyingLevel = null);
      final msg = e.response?.data is Map ? e.response?.data['message']?.toString() : null;
      _error(msg);
    } catch (_) {
      if (!mounted) return;
      setState(() => _buyingLevel = null);
      _error(null);
    }
  }

  void _error(String? msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg ?? 'تعذّر إتمام الشراء')),
    );
  }

  static String _fmt(int n) =>
      n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'شراء VIP',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              widget.coinsBalance != null
                  ? 'رصيدك: ${_fmt(widget.coinsBalance!)} كوينز'
                  : 'اختر المستوى الذي تريده',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_tiers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  'لا توجد مستويات معروضة للبيع حالياً',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _tiers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _tierRow(_tiers[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tierRow(Map<String, dynamic> tier) {
    final level = (tier['level'] as num).toInt();
    final price = (tier['priceCoins'] as num).toInt();
    final days = (tier['durationDays'] as num?)?.toInt();
    final name = (tier['name'] as String?)?.trim();
    final badge = LevelCatalogService.absoluteBadgeUrl(tier['badgeUrl']?.toString());
    final busy = _buyingLevel != null;
    final affordable = widget.coinsBalance == null || widget.coinsBalance! >= price;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.35)),
      ),
      child: Row(
        children: [
          if (badge != null)
            Image.network(badge, width: 38, height: 38, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.workspace_premium,
                    color: Color(0xFFFFD700), size: 32))
          else
            const Icon(Icons.workspace_premium, color: Color(0xFFFFD700), size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name?.isNotEmpty == true ? name! : 'VIP $level',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_fmt(price)} كوينز • ${days != null ? '$days يوم' : 'أبدي'}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: busy || !affordable ? null : () => _buy(tier),
              child: _buyingLevel == level
                  ? const SizedBox(
                      width: 15, height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
                  : Text(
                      affordable ? 'شراء' : 'رصيد غير كافٍ',
                      style: const TextStyle(
                          color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
