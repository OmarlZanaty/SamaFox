import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../services/dio_client.dart';
import '../widgets/app_network_image.dart';

/// SPEC52 #41 — the owner's own store lists (e.g. «ID مميز»), one tab each.
/// The purchase is decided entirely on the server (lock → checks → debit →
/// assign); this screen only asks and shows the result.
class CustomStoreScreen extends StatefulWidget {
  const CustomStoreScreen({super.key});

  @override
  State<CustomStoreScreen> createState() => _CustomStoreScreenState();
}

class _CustomStoreScreenState extends State<CustomStoreScreen> {
  List<Map<String, dynamic>>? _cats;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await DioClient.dio.get('/store/custom-categories');
      final list = (r.data is Map ? r.data['data'] : null) as List? ?? const [];
      if (mounted) setState(() => _cats = list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر تحميل المتجر');
    }
  }

  String _msg(Object e) {
    try {
      final d = (e as dynamic).response?.data;
      if (d is Map && d['message'] != null) return d['message'].toString();
    } catch (_) {}
    return 'تعذر إتمام الشراء';
  }

  Future<void> _buy(Map p) async {
    final isId = p['kind'] == 'special_id';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(isId ? 'شراء الرقم المميز ${p['specialDisplayId']}' : 'شراء ${p['name']}'),
        content: Text('السعر: ${p['priceCoins']} كوينز${isId ? '\nسيصبح هذا رقم حسابك الظاهر (ID) ويُحرَّر رقمك الحالي.' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('شراء')),
        ],
      ),
    );
    if (ok != true) return;
    final key = const Uuid().v4(); // one key per intent: a retry never charges twice
    try {
      final r = await DioClient.dio.post('/store/custom/${p['id']}/buy',
          options: Options(headers: {'Idempotency-Key': key}));
      final d = r.data['data'] as Map;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(d['newDisplayId'] != null ? '🎉 رقمك الجديد ${d['newDisplayId']}' : '✅ تم الشراء'),
      ));
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_msg(e))));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = _cats;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: cats == null || cats.isEmpty
          ? Scaffold(
              appBar: AppBar(title: const Text('قوائم خاصة')),
              body: Center(
                child: _error != null
                    ? Text(_error!)
                    : cats == null
                        ? const CircularProgressIndicator()
                        : const Text('لا توجد قوائم حالياً'),
              ),
            )
          : DefaultTabController(
              length: cats.length,
              child: Scaffold(
                appBar: AppBar(
                  title: const Text('قوائم خاصة'),
                  bottom: TabBar(isScrollable: true, tabs: [
                    for (final c in cats)
                      Tab(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if ((c['imageUrl'] ?? '').toString().isNotEmpty) ...[
                            AppNetworkImage(c['imageUrl'].toString(), width: 20, height: 20),
                            const SizedBox(width: 6),
                          ],
                          Text('${c['name']}'),
                        ]),
                      ),
                  ]),
                ),
                body: TabBarView(children: [for (final c in cats) _grid(c)]),
              ),
            ),
    );
  }

  Widget _grid(Map c) {
    final products = (c['products'] as List? ?? const []).whereType<Map>().toList();
    if (products.isEmpty) return const Center(child: Text('لا توجد منتجات متاحة'));
    return LayoutBuilder(
      builder: (_, box) => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: box.maxWidth >= 600 ? 4 : 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
        ),
        itemCount: products.length,
        itemBuilder: (_, i) {
          final p = products[i];
          final isId = p['kind'] == 'special_id';
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _buy(p),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(colors: [Color(0xFF3A1C71), Color(0xFF1A0E3E)]),
                border: Border.all(color: const Color(0xFFFFD54F).withOpacity(0.5)),
              ),
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isId)
                    FittedBox(
                      child: Text('${p['specialDisplayId']}',
                          style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    )
                  else if ((p['imageUrl'] ?? '').toString().isNotEmpty)
                    Expanded(child: AppNetworkImage(p['imageUrl'].toString(), fit: BoxFit.contain))
                  else
                    const Icon(Icons.shopping_bag, color: Colors.white54, size: 40),
                  const SizedBox(height: 6),
                  Text('${p['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('🪙 ${p['priceCoins']}', style: const TextStyle(color: Color(0xFFFFE082), fontWeight: FontWeight.w700)),
                  if (p['durationDays'] != null)
                    Text('${p['durationDays']} يوم', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
