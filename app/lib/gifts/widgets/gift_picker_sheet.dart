import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../models/gift.dart';
import '../services/gift_repository.dart';

/// A recipient candidate for the gift picker.
class GiftRecipient {
  final int id;
  final String name;
  final String? avatarUrl;
  const GiftRecipient({required this.id, required this.name, this.avatarUrl});
}

// Tab definitions: label + backend category filter (null = show all)
const List<(String label, String? category)> _kTabs = [
  ('عادي', null),
  ('محظوظ', 'lucky'),
  ('العلاقة', 'love'),
  ('خاص', 'luxury'),
  ('علم', 'flag'),
  ('كيس', 'bag'),
];

/// Bottom-sheet gift picker with 6 category tabs and role-aware recipient row.
class GiftPickerSheet extends StatefulWidget {
  const GiftPickerSheet({
    super.key,
    required this.repository,
    required this.recipients,
    this.roomId,
    required this.balance,
    required this.onBalanceChanged,
    this.initialRecipientIds = const [],
  });

  final GiftRepository repository;
  final List<GiftRecipient> recipients;
  final int? roomId;
  final int balance;
  final void Function(int newBalance) onBalanceChanged;
  final List<int> initialRecipientIds;

  static Future<void> show(
    BuildContext context, {
    required GiftRepository repository,
    required List<GiftRecipient> recipients,
    int? roomId,
    required int balance,
    required void Function(int) onBalanceChanged,
    List<int> initialRecipientIds = const [],
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0E3E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.60,
          child: GiftPickerSheet(
            repository: repository,
            recipients: recipients,
            roomId: roomId,
            balance: balance,
            onBalanceChanged: onBalanceChanged,
            initialRecipientIds: initialRecipientIds,
          ),
        ),
      ),
    );
  }

  @override
  State<GiftPickerSheet> createState() => _GiftPickerSheetState();
}

class _GiftPickerSheetState extends State<GiftPickerSheet> with SingleTickerProviderStateMixin {
  late TabController _tab;
  Future<GiftCatalog>? _catalog;
  int _balance = 0;
  String? _selectedGiftId;
  int _quantity = 1;
  bool _sending = false;
  late Set<int> _selectedRecipientIds;

  @override
  void initState() {
    super.initState();
    _balance = widget.balance;
    _tab = TabController(length: _kTabs.length, vsync: this);
    _catalog = widget.repository.fetchCatalog();
    _selectedRecipientIds = {
      ...widget.initialRecipientIds.where(
        (id) => widget.recipients.any((r) => r.id == id),
      ),
    };
    if (_selectedRecipientIds.isEmpty && widget.recipients.isNotEmpty) {
      _selectedRecipientIds.add(widget.recipients.first.id);
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  String _resolveIconUrl(String iconUrl) {
    if (iconUrl.isEmpty) return iconUrl;
    if (iconUrl.startsWith('http://') || iconUrl.startsWith('https://')) return iconUrl;
    final base = AppConfig.socketUrl.endsWith('/')
        ? AppConfig.socketUrl.substring(0, AppConfig.socketUrl.length - 1)
        : AppConfig.socketUrl;
    return iconUrl.startsWith('/') ? '$base$iconUrl' : '$base/$iconUrl';
  }

  String? _resolveAvatarUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    final base = AppConfig.socketUrl.endsWith('/')
        ? AppConfig.socketUrl.substring(0, AppConfig.socketUrl.length - 1)
        : AppConfig.socketUrl;
    return raw.startsWith('/') ? '$base$raw' : '$base/$raw';
  }

  List<Gift> _giftsForTab(GiftCatalog catalog, String? category) {
    final all = catalog.all;
    if (category == null) return all;
    return all.where((g) => g.category == category).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        _recipientsRow(),
        TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: const Color(0xFFFF4081),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabAlignment: TabAlignment.start,
          tabs: _kTabs.map((t) => Tab(text: t.$1)).toList(),
        ),
        Expanded(
          child: FutureBuilder<GiftCatalog>(
            future: _catalog,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('فشل تحميل الهدايا: ${snapshot.error}',
                      style: const TextStyle(color: Colors.white70)),
                );
              }
              final catalog = snapshot.data!;
              return TabBarView(
                controller: _tab,
                children: _kTabs.map(((String, String?) t) {
                  final gifts = _giftsForTab(catalog, t.$2);
                  if (gifts.isEmpty) {
                    return const Center(
                        child: Text('لا توجد هدايا بعد', style: TextStyle(color: Colors.white60)));
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: gifts.length,
                    itemBuilder: (_, i) => _giftCell(gifts[i]),
                  );
                }).toList(),
              );
            },
          ),
        ),
        _footer(),
      ],
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2D2560))),
      ),
      child: Row(
        children: [
          const Text('إرسال هدية',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF261D52),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🪙', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(_balance.toString(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recipientsRow() {
    if (widget.recipients.isEmpty) {
      return Container(
        height: 80,
        alignment: Alignment.center,
        child: const Text('لا يوجد مستلمون', style: TextStyle(color: Colors.white60)),
      );
    }
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: widget.recipients.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _recipientChip(widget.recipients[i]),
      ),
    );
  }

  Widget _recipientChip(GiftRecipient r) {
    final selected = _selectedRecipientIds.contains(r.id);
    final avatarUrl = _resolveAvatarUrl(r.avatarUrl);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (selected) {
            _selectedRecipientIds.remove(r.id);
          } else {
            _selectedRecipientIds.add(r.id);
          }
        });
      },
      child: SizedBox(
        width: 60,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? const Color(0xFFFF4081) : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: selected
                    ? [const BoxShadow(color: Color(0xFFFF4081), blurRadius: 8, spreadRadius: 1)]
                    : null,
              ),
              padding: const EdgeInsets.all(2),
              child: ClipOval(
                child: avatarUrl != null
                    ? Image.network(avatarUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _avatarFallback(r.name))
                    : _avatarFallback(r.name),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              r.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? const Color(0xFFFF80AB) : Colors.white70,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback(String name) {
    final initial = name.trim().isNotEmpty ? name.trim().characters.first.toUpperCase() : '?';
    return Container(
      color: const Color(0xFF3D2B7A),
      alignment: Alignment.center,
      child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
    );
  }

  Widget _giftCell(Gift gift) {
    final selected = _selectedGiftId == gift.id;
    final resolvedUrl = _resolveIconUrl(gift.iconUrl);
    return GestureDetector(
      onTap: () => setState(() => _selectedGiftId = gift.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF3D2B7A) : const Color(0xFF1E1547),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFFFF4081) : Colors.transparent,
            width: 2,
          ),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: resolvedUrl.isNotEmpty
                    ? Image.network(resolvedUrl, fit: BoxFit.cover, width: double.infinity,
                        errorBuilder: (_, __, ___) => _giftFallback(gift))
                    : _giftFallback(gift),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              gift.nameAr ?? gift.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🪙', style: TextStyle(fontSize: 9)),
                const SizedBox(width: 3),
                Text('${gift.coinCost}',
                    style: const TextStyle(color: Color(0xFFFFD700), fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _giftFallback(Gift gift) {
    String emoji;
    switch (gift.category) {
      case 'love': emoji = '💖'; break;
      case 'lucky': emoji = '🍀'; break;
      case 'luxury': emoji = '💎'; break;
      case 'flag': emoji = '🚩'; break;
      case 'bag': emoji = '👜'; break;
      default: emoji = '🎁';
    }
    return Container(
      color: const Color(0xFF2D1F6E),
      alignment: Alignment.center,
      child: Text(emoji, style: const TextStyle(fontSize: 28)),
    );
  }

  Widget _footer() {
    final disabled = _selectedGiftId == null || _selectedRecipientIds.isEmpty || _sending;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF2D2560))),
        ),
        child: Row(
          children: [
            // Quantity
            _qtyButton('-', () => setState(() => _quantity = (_quantity - 1).clamp(1, 99))),
            Container(
              width: 44,
              alignment: Alignment.center,
              child: Text(_quantity.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            _qtyButton('+', () => setState(() => _quantity = (_quantity + 1).clamp(1, 99))),
            const SizedBox(width: 8),
            // Send button
            Expanded(
              child: ElevatedButton(
                onPressed: disabled ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4081),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _sending
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        _selectedRecipientIds.length > 1
                            ? 'إرسال (${_selectedRecipientIds.length})'
                            : 'إرسال',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ),
            const SizedBox(width: 8),
            // Recharge button
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                decoration: BoxDecoration(
                  color: const Color(0xFF261D52),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF4A3B8C)),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🪙', style: TextStyle(fontSize: 16)),
                    Text('إعادة\nالشحن',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 9, height: 1.2)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _qtyButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFF261D52),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 18)),
      ),
    );
  }

  Future<void> _send() async {
    final giftId = _selectedGiftId;
    final recipients = _selectedRecipientIds.toList();
    if (giftId == null || recipients.isEmpty) return;
    setState(() => _sending = true);
    int successCount = 0;
    GiftSendResult? lastResult;
    String? firstErrorMessage;
    try {
      for (final rid in recipients) {
        try {
          final result = await widget.repository.send(
            giftId: giftId,
            recipientId: rid,
            roomId: widget.roomId,
            quantity: _quantity,
          );
          lastResult = result;
          successCount++;
        } on GiftRepositoryException catch (e) {
          firstErrorMessage ??= e.message;
          if (e.code == 'INSUFFICIENT_BALANCE' || e.code == 'RATE_LIMIT' || e.code == 'UNAUTHORIZED') {
            break;
          }
        }
      }
      if (lastResult != null) {
        setState(() => _balance = lastResult!.senderBalance);
        widget.onBalanceChanged(lastResult.senderBalance);
      }
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      if (successCount > 0 && firstErrorMessage == null) {
        messenger.showSnackBar(SnackBar(
          content: Text(successCount > 1 ? 'تم إرسال الهدية إلى $successCount مستلمين' : 'تم إرسال الهدية!'),
          duration: const Duration(seconds: 1),
        ));
      } else if (successCount > 0 && firstErrorMessage != null) {
        messenger.showSnackBar(SnackBar(
          content: Text('تم إرسال $successCount من ${recipients.length}: $firstErrorMessage'),
          backgroundColor: Colors.orange[800],
        ));
      } else {
        messenger.showSnackBar(SnackBar(
          content: Text(firstErrorMessage ?? 'فشل إرسال الهدية'),
          backgroundColor: Colors.red[700],
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
