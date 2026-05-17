import 'package:flutter/material.dart';

import '../models/gift.dart';
import '../services/gift_repository.dart';

/// Bottom-sheet gift picker for the gift catalog.
/// Caller provides the recipient + room context and a balance fetcher.
class GiftPickerSheet extends StatefulWidget {
  const GiftPickerSheet({
    super.key,
    required this.repository,
    required this.recipientId,
    this.roomId,
    required this.balance,
    required this.onBalanceChanged,
  });

  final GiftRepository repository;
  final int recipientId;
  final int? roomId;
  final int balance;
  final void Function(int newBalance) onBalanceChanged;

  static Future<void> show(
    BuildContext context, {
    required GiftRepository repository,
    required int recipientId,
    int? roomId,
    required int balance,
    required void Function(int) onBalanceChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0E3E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: GiftPickerSheet(
          repository: repository,
          recipientId: recipientId,
          roomId: roomId,
          balance: balance,
          onBalanceChanged: onBalanceChanged,
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

  @override
  void initState() {
    super.initState();
    _balance = widget.balance;
    _tab = TabController(length: GiftTier.values.length, vsync: this);
    _catalog = widget.repository.fetchCatalog();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        TabBar(
          controller: _tab,
          indicatorColor: const Color(0xFFFF4081),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Small'),
            Tab(text: 'Medium'),
            Tab(text: 'Large'),
            Tab(text: 'Legendary'),
          ],
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
                  child: Text('Failed to load gifts: ${snapshot.error}',
                      style: const TextStyle(color: Colors.white70)),
                );
              }
              final catalog = snapshot.data!;
              return TabBarView(
                controller: _tab,
                children: GiftTier.values.map((tier) {
                  final gifts = catalog.byTier[tier] ?? const [];
                  if (gifts.isEmpty) {
                    return const Center(
                        child: Text('No gifts yet', style: TextStyle(color: Colors.white60)));
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
          const Text('Send a gift',
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

  Widget _giftCell(Gift gift) {
    final selected = _selectedGiftId == gift.id;
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
                child: gift.iconUrl.isNotEmpty
                    ? Image.network(
                        gift.iconUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF2A1A5E)),
                      )
                    : const ColoredBox(color: Color(0xFF2A1A5E)),
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

  Widget _footer() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF2D2560))),
        ),
        child: Row(
          children: [
            _qtyButton('-', () {
              setState(() => _quantity = (_quantity - 1).clamp(1, 99));
            }),
            Container(
              width: 50,
              alignment: Alignment.center,
              child: Text(
                _quantity.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
            _qtyButton('+', () {
              setState(() => _quantity = (_quantity + 1).clamp(1, 99));
            }),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _selectedGiftId == null || _sending ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4081),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Send', style: TextStyle(fontWeight: FontWeight.w600)),
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
        width: 36,
        height: 36,
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
    if (_selectedGiftId == null) return;
    setState(() => _sending = true);
    try {
      final result = await widget.repository.send(
        giftId: _selectedGiftId!,
        recipientId: widget.recipientId,
        roomId: widget.roomId,
        quantity: _quantity,
      );
      setState(() => _balance = result.senderBalance);
      widget.onBalanceChanged(result.senderBalance);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gift sent!'), duration: Duration(seconds: 1)),
        );
      }
    } on GiftRepositoryException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
