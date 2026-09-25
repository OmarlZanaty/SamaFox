import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/InventoryItem.dart';
import '../providers/auth_provider.dart';
import '../services/store_service.dart';
import '../utils/storage_service.dart';
import '../widgets/app_network_image.dart';
import '../widgets/product_video_layer.dart';

/// «خلفيات خاصتي» — the profile backgrounds this user OWNS, and nothing else.
///
/// The store shows every background (free ones to everybody); showing up there
/// is not ownership. Ownership is a `user_items` row on the server, created by
/// a purchase or by an admin grant for this user only. This list is read from
/// the server every time it opens (`GET /store/inventory`), so a new device or
/// a reinstall shows the same backgrounds, and an expired rental is gone.
class MyBackgroundsScreen extends ConsumerStatefulWidget {
  const MyBackgroundsScreen({super.key});

  @override
  ConsumerState<MyBackgroundsScreen> createState() => _MyBackgroundsScreenState();
}

const _kBg = Color(0xFF0D0620);
const _kCard = Color(0xFF1A0E3E);

class _MyBackgroundsScreenState extends ConsumerState<MyBackgroundsScreen> {
  final StoreService _service = StoreService();
  late Future<List<InventoryItem>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<InventoryItem>> _load() async {
    final token = await StorageService.getAccessToken();
    final all = await _service.getInventory(token ?? '');
    return all.where((e) => e.type == 'profile_background').toList();
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _toggle(InventoryItem item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final token = await StorageService.getAccessToken() ?? '';
      if (item.isActive) {
        await _service.deactivateItem(token, item.id);
      } else {
        await _service.activateItem(token, item.id);
      }
      // The page paints its background from the USER row, so re-read it.
      await ref.read(authStateProvider.notifier).refreshMe();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(item.isActive ? 'تم إلغاء استخدام الخلفية' : 'تم تركيب الخلفية على صفحتك'),
      ));
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر تنفيذ العملية'), backgroundColor: Colors.red[700]),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
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
          title: const Text('خلفيات خاصتي', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        body: FutureBuilder<List<InventoryItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _message('تعذّر تحميل خلفياتك', retry: true);
            }
            final items = snap.data ?? const <InventoryItem>[];
            if (items.isEmpty) {
              return _message('لا تملك خلفيات بعد.\nالخلفيات اللي تشتريها من المتجر أو تتمنح لك هتظهر هنا.');
            }
            return RefreshIndicator(
              onRefresh: () async {
                final f = _load();
                setState(() => _future = f);
                await f;
              },
              child: GridView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.58,
                ),
                itemBuilder: (_, i) => _card(items[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _card(InventoryItem item) {
    return Container(
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.isActive ? Colors.greenAccent : Colors.white12,
          width: item.isActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AppNetworkImage(
                    item.previewUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported, color: Colors.white24),
                  ),
                  // A clip plays over its poster; renders nothing until ready.
                  if (isProductVideoUrl(item.fileUrl))
                    ProductVideoLayer(url: item.fileUrl, fit: BoxFit.cover),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _chip(item.remainingLabel, urgent: !item.isPermanent && (item.daysRemaining ?? 0) <= 3),
                  ),
                  if (item.isActive)
                    Positioned(top: 6, left: 6, child: _chip('مستخدمة', color: Colors.green[700]!)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: SizedBox(
              height: 34,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: item.isActive ? Colors.redAccent : const Color(0xFF4ECDC4),
                ),
                onPressed: _busy ? null : () => _toggle(item),
                child: Text(
                  item.isActive ? 'إلغاء الاستخدام' : 'استخدام',
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text, {bool urgent = false, Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color ?? (urgent ? const Color(0xFFFF9800) : Colors.black.withOpacity(0.75)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      );

  Widget _message(String text, {bool retry = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wallpaper, color: Colors.white24, size: 48),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60, height: 1.6)),
              if (retry) ...[
                const SizedBox(height: 14),
                TextButton(onPressed: _reload, child: const Text('إعادة المحاولة')),
              ],
            ],
          ),
        ),
      );
}
